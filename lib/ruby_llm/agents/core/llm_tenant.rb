# frozen_string_literal: true

require "active_support/concern"

module RubyLLM
  module Agents
    # DSL for declaring Rails models as LLM tenants
    #
    # Provides automatic budget management and usage tracking when included
    # in ActiveRecord models. Models using this concern can be passed as
    # the `tenant:` parameter to agents.
    #
    # @example Basic usage
    #   class Organization < ApplicationRecord
    #     include RubyLLM::Agents::LLMTenant
    #     llm_tenant
    #   end
    #
    # @example With custom ID method
    #   class Organization < ApplicationRecord
    #     include RubyLLM::Agents::LLMTenant
    #     llm_tenant id: :slug
    #   end
    #
    # @example With auto-created budget
    #   class Organization < ApplicationRecord
    #     include RubyLLM::Agents::LLMTenant
    #     llm_tenant id: :slug, budget: true
    #   end
    #
    # @example With limits (auto-creates budget)
    #   class Organization < ApplicationRecord
    #     include RubyLLM::Agents::LLMTenant
    #     llm_tenant(
    #       id: :slug,
    #       name: :company_name,
    #       limits: {
    #         daily_cost: 100,
    #         monthly_cost: 1000,
    #         daily_executions: 500
    #       },
    #       enforcement: :hard
    #     )
    #   end
    #
    # @example With API keys from model columns/methods
    #   class Organization < ApplicationRecord
    #     include RubyLLM::Agents::LLMTenant
    #     encrypts :openai_api_key, :anthropic_api_key  # Rails 7+ encryption
    #
    #     llm_tenant(
    #       id: :slug,
    #       api_keys: {
    #         openai: :openai_api_key,        # column name
    #         anthropic: :anthropic_api_key,  # column name
    #         gemini: :fetch_gemini_key       # custom method
    #       }
    #     )
    #
    #     def fetch_gemini_key
    #       Vault.read("secret/#{slug}/gemini")
    #     end
    #   end
    #
    # @see RubyLLM::Agents::Tenant
    # @api public
    module LLMTenant
      extend ActiveSupport::Concern

      included do
        # Link to gem's Tenant model via polymorphic association
        has_one :llm_tenant_record,
                class_name: "RubyLLM::Agents::Tenant",
                as: :tenant_record,
                dependent: :destroy

        # Backward compatible alias (llm_budget points to same Tenant record)
        # @deprecated Use llm_tenant_record instead
        alias_method :llm_budget_association, :llm_tenant_record

        # Store options at class level
        class_attribute :llm_tenant_options, default: {}
      end

      class_methods do
        # Declares this model as an LLM tenant
        #
        # @param id [Symbol] Method to call for tenant_id string (default: :id)
        # @param name [Symbol] Method for budget display name (default: :to_s)
        # @param budget [Boolean] Auto-create Tenant record on model creation (default: false)
        # @param limits [Hash] Default budget limits (implies budget: true)
        # @param enforcement [Symbol] Budget enforcement mode (:none, :soft, :hard)
        # @param inherit_global [Boolean] Inherit from global config (default: true)
        # @param api_keys [Hash] Provider API keys mapping (e.g., { openai: :openai_api_key })
        # @return [void]
        def llm_tenant(id: :id, name: :to_s, budget: false, limits: nil, enforcement: nil, inherit_global: true, api_keys: nil)
          self.llm_tenant_options = {
            id: id,
            name: name,
            budget: budget || limits.present?,
            limits: normalize_limits(limits),
            enforcement: enforcement,
            inherit_global: inherit_global,
            api_keys: api_keys
          }

          # Executions tracked for this tenant via tenant_id string column
          has_many :llm_executions,
                   class_name: "RubyLLM::Agents::Execution",
                   foreign_key: :tenant_id,
                   primary_key: id,
                   dependent: :nullify

          # Auto-create tenant record callback
          after_create :create_default_llm_tenant if llm_tenant_options[:budget]
        end

        private

        # Normalizes the limits hash to internal column names
        #
        # @param limits [Hash, nil] User-provided limits
        # @return [Hash] Normalized limits
        def normalize_limits(limits)
          return {} if limits.blank?

          {
            daily_cost: limits[:daily_cost],
            monthly_cost: limits[:monthly_cost],
            daily_tokens: limits[:daily_tokens],
            monthly_tokens: limits[:monthly_tokens],
            daily_executions: limits[:daily_executions],
            monthly_executions: limits[:monthly_executions]
          }.compact
        end
      end

      # Returns the tenant_id string for this model
      #
      # @return [String] The tenant identifier
      def llm_tenant_id
        id_method = self.class.llm_tenant_options[:id] || :id
        send(id_method).to_s
      end

      # Returns API keys resolved from the DSL configuration
      #
      # Maps provider names (e.g., :openai, :anthropic) to their resolved values
      # by calling the configured method/column on this model instance.
      #
      # @return [Hash] Provider to API key mapping (e.g., { openai: "sk-..." })
      # @example
      #   org.llm_api_keys
      #   # => { openai: "sk-abc123", anthropic: "sk-ant-xyz789" }
      def llm_api_keys
        api_keys_config = self.class.llm_tenant_options[:api_keys]
        return {} if api_keys_config.blank?

        api_keys_config.transform_values do |method_name|
          value = send(method_name)
          value.presence
        end.compact
      end

      # Returns or builds the associated Tenant record
      #
      # @return [Tenant] The tenant record
      def llm_tenant
        llm_tenant_record || build_llm_tenant_record(tenant_id: llm_tenant_id)
      end

      # Backward compatible alias for llm_tenant
      # @deprecated Use llm_tenant instead
      alias_method :llm_budget, :llm_tenant

      # Configure tenant with a block
      #
      # @yield [tenant] The tenant to configure
      # @return [Tenant] The saved tenant
      def llm_configure(&block)
        tenant = llm_tenant
        yield(tenant) if block_given?
        tenant.save!
        tenant
      end

      # Backward compatible alias
      # @deprecated Use llm_configure instead
      alias_method :llm_configure_budget, :llm_configure

      # Tracking methods using llm_executions association
      # These query executions via the polymorphic tenant_record association

      # Returns cost for a given period
      #
      # @param period [Symbol, Range, nil] Time period (:today, :this_month, etc.)
      # @return [BigDecimal] Total cost
      def llm_cost(period: nil)
        scope = llm_executions
        scope = apply_llm_period_scope(scope, period) if period
        scope.sum(:total_cost) || 0
      end

      # Returns cost for today
      #
      # @return [BigDecimal] Today's cost
      def llm_cost_today
        llm_cost(period: :today)
      end

      # Returns cost for this month
      #
      # @return [BigDecimal] This month's cost
      def llm_cost_this_month
        llm_cost(period: :this_month)
      end

      # Returns token count for a given period
      #
      # @param period [Symbol, Range, nil] Time period
      # @return [Integer] Total tokens
      def llm_tokens(period: nil)
        scope = llm_executions
        scope = apply_llm_period_scope(scope, period) if period
        scope.sum(:total_tokens) || 0
      end

      # Returns tokens for today
      #
      # @return [Integer] Today's tokens
      def llm_tokens_today
        llm_tokens(period: :today)
      end

      # Returns tokens for this month
      #
      # @return [Integer] This month's tokens
      def llm_tokens_this_month
        llm_tokens(period: :this_month)
      end

      # Returns execution count for a given period
      #
      # @param period [Symbol, Range, nil] Time period
      # @return [Integer] Execution count
      def llm_execution_count(period: nil)
        scope = llm_executions
        scope = apply_llm_period_scope(scope, period) if period
        scope.count
      end

      # Returns executions for today
      #
      # @return [Integer] Today's execution count
      def llm_executions_today
        llm_execution_count(period: :today)
      end

      # Returns executions for this month
      #
      # @return [Integer] This month's execution count
      def llm_executions_this_month
        llm_execution_count(period: :this_month)
      end

      # Returns a usage summary for a given period
      #
      # @param period [Symbol] Time period (default: :this_month)
      # @return [Hash] Usage summary with cost, tokens, and executions
      def llm_usage_summary(period: :this_month)
        {
          cost: llm_cost(period: period),
          tokens: llm_tokens(period: period),
          executions: llm_execution_count(period: period),
          period: period
        }
      end

      # Delegate budget methods to the Tenant record

      # Returns the budget status from BudgetTracker
      #
      # @return [Hash] Budget status
      def llm_budget_status
        llm_tenant.budget_status
      end

      # Checks if within budget for a given limit type
      #
      # @param type [Symbol] Limit type (:daily_cost, :monthly_cost, :daily_tokens, etc.)
      # @return [Boolean] true if within budget
      def llm_within_budget?(type: :daily_cost)
        llm_tenant.within_budget?(type: type)
      end

      # Returns remaining budget for a given limit type
      #
      # @param type [Symbol] Limit type
      # @return [Numeric, nil] Remaining amount
      def llm_remaining_budget(type: :daily_cost)
        llm_tenant.remaining_budget(type: type)
      end

      # Raises an error if over budget
      #
      # @raise [BudgetExceededError] if budget is exceeded
      # @return [void]
      def llm_check_budget!
        llm_tenant.check_budget!(self.class.name)
      end

      private

      # Applies a period scope to an execution query
      #
      # @param scope [ActiveRecord::Relation] The query scope
      # @param period [Symbol, Range] The period to filter by
      # @return [ActiveRecord::Relation] Filtered scope
      def apply_llm_period_scope(scope, period)
        case period
        when :today then scope.where(created_at: Time.current.all_day)
        when :yesterday then scope.where(created_at: 1.day.ago.all_day)
        when :this_week then scope.where(created_at: Time.current.all_week)
        when :this_month then scope.where(created_at: Time.current.all_month)
        when Range then scope.where(created_at: period)
        else scope
        end
      end

      # Creates the default tenant record on model creation
      #
      # @return [void]
      def create_default_llm_tenant
        return if self.class.llm_tenant_options.blank?
        return if llm_tenant_record&.persisted?

        options = self.class.llm_tenant_options
        limits = options[:limits] || {}
        name_method = options[:name] || :to_s

        tenant = build_llm_tenant_record(
          tenant_id: llm_tenant_id,
          name: send(name_method).to_s,
          daily_limit: limits[:daily_cost],
          monthly_limit: limits[:monthly_cost],
          daily_token_limit: limits[:daily_tokens],
          monthly_token_limit: limits[:monthly_tokens],
          daily_execution_limit: limits[:daily_executions],
          monthly_execution_limit: limits[:monthly_executions],
          enforcement: options[:enforcement]&.to_s || "soft",
          inherit_global_defaults: options.fetch(:inherit_global, true)
        )

        tenant.tenant_record = self
        tenant.save!
      end
    end
  end
end
