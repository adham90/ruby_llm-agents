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
    #     llm_tenant
    #   end
    #
    # @example With custom ID method
    #   class Organization < ApplicationRecord
    #     llm_tenant id: :slug
    #   end
    #
    # @example With auto-created budget
    #   class Organization < ApplicationRecord
    #     llm_tenant id: :slug, budget: true
    #   end
    #
    # @example With limits (auto-creates budget)
    #   class Organization < ApplicationRecord
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
    # @see RubyLLM::Agents::TenantBudget
    # @api public
    module LLMTenant
      extend ActiveSupport::Concern

      included do
        # Executions tracked for this tenant
        has_many :llm_executions,
                 class_name: "RubyLLM::Agents::Execution",
                 as: :tenant_record,
                 dependent: :nullify

        # Budget association (optional)
        has_one :llm_budget,
                class_name: "RubyLLM::Agents::TenantBudget",
                as: :tenant_record,
                dependent: :destroy

        # Store options at class level
        class_attribute :llm_tenant_options, default: {}
      end

      class_methods do
        # Declares this model as an LLM tenant
        #
        # @param id [Symbol] Method to call for tenant_id string (default: :id)
        # @param name [Symbol] Method for budget display name (default: :to_s)
        # @param budget [Boolean] Auto-create TenantBudget on model creation (default: false)
        # @param limits [Hash] Default budget limits (implies budget: true)
        # @param enforcement [Symbol] Budget enforcement mode (:none, :soft, :hard)
        # @param inherit_global [Boolean] Inherit from global config (default: true)
        # @return [void]
        def llm_tenant(id: :id, name: :to_s, budget: false, limits: nil, enforcement: nil, inherit_global: true)
          self.llm_tenant_options = {
            id: id,
            name: name,
            budget: budget || limits.present?,
            limits: normalize_limits(limits),
            enforcement: enforcement,
            inherit_global: inherit_global
          }

          # Auto-create budget callback
          after_create :create_default_llm_budget if llm_tenant_options[:budget]
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

      # Returns cost for a given period
      #
      # @param period [Symbol, Range, nil] Time period (:today, :this_month, etc.)
      # @return [BigDecimal] Total cost
      def llm_cost(period: nil)
        scope = llm_executions
        scope = apply_period_scope(scope, period) if period
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
        scope = apply_period_scope(scope, period) if period
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
        scope = apply_period_scope(scope, period) if period
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

      # Returns or builds the associated TenantBudget
      #
      # @return [TenantBudget] The budget record
      def llm_budget
        super || build_llm_budget(tenant_id: llm_tenant_id)
      end

      # Configure budget with a block
      #
      # @yield [budget] The budget to configure
      # @return [TenantBudget] The saved budget
      def llm_configure_budget
        budget = llm_budget
        yield(budget) if block_given?
        budget.save!
        budget
      end

      # Returns the budget status from BudgetTracker
      #
      # @return [Hash] Budget status
      def llm_budget_status
        BudgetTracker.status(tenant_id: llm_tenant_id)
      end

      # Checks if within budget for a given limit type
      #
      # @param type [Symbol] Limit type (:daily_cost, :monthly_cost, :daily_tokens, etc.)
      # @return [Boolean] true if within budget
      def llm_within_budget?(type: :daily_cost)
        status = llm_budget_status
        return true unless status[:enabled]

        key = budget_status_key(type)
        status.dig(key, :percentage_used).to_f < 100
      end

      # Returns remaining budget for a given limit type
      #
      # @param type [Symbol] Limit type
      # @return [Numeric, nil] Remaining amount
      def llm_remaining_budget(type: :daily_cost)
        status = llm_budget_status
        key = budget_status_key(type)
        status.dig(key, :remaining)
      end

      # Raises an error if over budget
      #
      # @raise [BudgetExceededError] if budget is exceeded
      # @return [void]
      def llm_check_budget!
        BudgetTracker.check_budget!(self.class.name, tenant_id: llm_tenant_id)
      end

      private

      # Applies a period scope to an execution query
      #
      # @param scope [ActiveRecord::Relation] The query scope
      # @param period [Symbol, Range] The period to filter by
      # @return [ActiveRecord::Relation] Filtered scope
      def apply_period_scope(scope, period)
        case period
        when :today then scope.where(created_at: Time.current.all_day)
        when :yesterday then scope.where(created_at: 1.day.ago.all_day)
        when :this_week then scope.where(created_at: Time.current.all_week)
        when :this_month then scope.where(created_at: Time.current.all_month)
        when Range then scope.where(created_at: period)
        else scope
        end
      end

      # Maps user-friendly type to budget status key
      #
      # @param type [Symbol] User-friendly type
      # @return [Symbol] Status key
      def budget_status_key(type)
        case type
        when :daily_cost then :global_daily
        when :monthly_cost then :global_monthly
        when :daily_tokens then :global_daily_tokens
        when :monthly_tokens then :global_monthly_tokens
        when :daily_executions then :global_daily_executions
        when :monthly_executions then :global_monthly_executions
        else :global_daily
        end
      end

      # Creates the default budget on model creation
      #
      # @return [void]
      def create_default_llm_budget
        return if self.class.llm_tenant_options.blank?
        return if llm_budget&.persisted?

        options = self.class.llm_tenant_options
        limits = options[:limits] || {}
        name_method = options[:name] || :to_s

        budget = build_llm_budget(
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

        budget.tenant_record = self
        budget.save!
      end
    end
  end
end
