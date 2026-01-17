# frozen_string_literal: true

module RubyLLM
  module Agents
    # Database-backed budget configuration for multi-tenant environments
    #
    # Stores per-tenant budget limits that override the global configuration.
    # Supports runtime updates without application restarts.
    # Supports both cost-based (USD) and token-based limits.
    #
    # @!attribute [rw] tenant_id
    #   @return [String] Unique identifier for the tenant
    # @!attribute [rw] name
    #   @return [String, nil] Human-readable name for the tenant
    # @!attribute [rw] daily_limit
    #   @return [BigDecimal, nil] Daily budget limit in USD
    # @!attribute [rw] monthly_limit
    #   @return [BigDecimal, nil] Monthly budget limit in USD
    # @!attribute [rw] daily_token_limit
    #   @return [Integer, nil] Daily token limit (across all models)
    # @!attribute [rw] monthly_token_limit
    #   @return [Integer, nil] Monthly token limit (across all models)
    # @!attribute [rw] per_agent_daily
    #   @return [Hash] Per-agent daily cost limits: { "AgentName" => limit }
    # @!attribute [rw] per_agent_monthly
    #   @return [Hash] Per-agent monthly cost limits: { "AgentName" => limit }
    # @!attribute [rw] enforcement
    #   @return [String] Enforcement mode: "none", "soft", or "hard"
    # @!attribute [rw] inherit_global_defaults
    #   @return [Boolean] Whether to fall back to global config for unset limits
    #
    # @example Creating a tenant budget with cost and token limits
    #   TenantBudget.create!(
    #     tenant_id: "acme_corp",
    #     name: "Acme Corporation",
    #     daily_limit: 50.0,           # USD
    #     monthly_limit: 500.0,        # USD
    #     daily_token_limit: 1_000_000,
    #     monthly_token_limit: 10_000_000,
    #     per_agent_daily: { "ContentAgent" => 10.0 },
    #     enforcement: "hard"
    #   )
    #
    # @example Fetching budget for a tenant
    #   budget = TenantBudget.for_tenant("acme_corp")
    #   budget.effective_daily_limit        # => 50.0 (cost)
    #   budget.effective_daily_token_limit  # => 1_000_000 (tokens)
    #
    # @see RubyLLM::Agents::BudgetTracker
    # @api public
    class TenantBudget < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_tenant_budgets"

      # Valid enforcement modes
      ENFORCEMENT_MODES = %w[none soft hard].freeze

      # Validations
      validates :tenant_id, presence: true, uniqueness: true
      validates :enforcement, inclusion: { in: ENFORCEMENT_MODES }, allow_nil: true
      validates :daily_limit, :monthly_limit,
                numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :daily_token_limit, :monthly_token_limit,
                numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true

      # Finds a budget for the given tenant
      #
      # @param tenant_id [String] The tenant identifier
      # @return [TenantBudget, nil] The budget record or nil if not found
      def self.for_tenant(tenant_id)
        return nil if tenant_id.blank?

        find_by(tenant_id: tenant_id)
      end

      # Finds or creates a budget for the given tenant
      #
      # @param tenant_id [String] The tenant identifier
      # @param name [String, nil] Optional human-readable name
      # @return [TenantBudget] The budget record
      def self.for_tenant!(tenant_id, name: nil)
        find_or_create_by!(tenant_id: tenant_id) do |budget|
          budget.name = name
        end
      end

      # Returns the display name (name or tenant_id fallback)
      #
      # @return [String] The name to display
      def display_name
        name.presence || tenant_id
      end

      # Returns the effective daily limit, considering inheritance
      #
      # @return [Float, nil] The daily limit or nil if not set
      def effective_daily_limit
        return daily_limit if daily_limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:global_daily)
      end

      # Returns the effective monthly limit, considering inheritance
      #
      # @return [Float, nil] The monthly limit or nil if not set
      def effective_monthly_limit
        return monthly_limit if monthly_limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:global_monthly)
      end

      # Returns the effective per-agent daily limit
      #
      # @param agent_type [String] The agent class name
      # @return [Float, nil] The limit or nil if not set
      def effective_per_agent_daily(agent_type)
        limit = per_agent_daily&.dig(agent_type)
        return limit if limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:per_agent_daily, agent_type)
      end

      # Returns the effective per-agent monthly limit
      #
      # @param agent_type [String] The agent class name
      # @return [Float, nil] The limit or nil if not set
      def effective_per_agent_monthly(agent_type)
        limit = per_agent_monthly&.dig(agent_type)
        return limit if limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:per_agent_monthly, agent_type)
      end

      # Returns the effective daily token limit, considering inheritance
      #
      # @return [Integer, nil] The daily token limit or nil if not set
      def effective_daily_token_limit
        return daily_token_limit if daily_token_limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:global_daily_tokens)
      end

      # Returns the effective monthly token limit, considering inheritance
      #
      # @return [Integer, nil] The monthly token limit or nil if not set
      def effective_monthly_token_limit
        return monthly_token_limit if monthly_token_limit.present?
        return nil unless inherit_global_defaults

        global_config&.dig(:global_monthly_tokens)
      end

      # Returns the effective enforcement mode
      #
      # @return [Symbol] :none, :soft, or :hard
      def effective_enforcement
        return enforcement.to_sym if enforcement.present?
        return :soft unless inherit_global_defaults

        RubyLLM::Agents.configuration.budget_enforcement
      end

      # Checks if budget enforcement is enabled for this tenant
      #
      # @return [Boolean] true if enforcement is :soft or :hard
      def budgets_enabled?
        effective_enforcement != :none
      end

      # Returns a hash suitable for BudgetTracker
      #
      # @return [Hash] Budget configuration hash
      def to_budget_config
        {
          enabled: budgets_enabled?,
          enforcement: effective_enforcement,
          # Cost limits
          global_daily: effective_daily_limit,
          global_monthly: effective_monthly_limit,
          per_agent_daily: merged_per_agent_daily,
          per_agent_monthly: merged_per_agent_monthly,
          # Token limits (global only)
          global_daily_tokens: effective_daily_token_limit,
          global_monthly_tokens: effective_monthly_token_limit
        }
      end

      private

      # Returns the global budgets configuration
      #
      # @return [Hash, nil] Global budget config
      def global_config
        RubyLLM::Agents.configuration.budgets
      end

      # Merges per-agent daily limits with global defaults
      #
      # @return [Hash] Merged per-agent daily limits
      def merged_per_agent_daily
        return per_agent_daily || {} unless inherit_global_defaults

        (global_config&.dig(:per_agent_daily) || {}).merge(per_agent_daily || {})
      end

      # Merges per-agent monthly limits with global defaults
      #
      # @return [Hash] Merged per-agent monthly limits
      def merged_per_agent_monthly
        return per_agent_monthly || {} unless inherit_global_defaults

        (global_config&.dig(:per_agent_monthly) || {}).merge(per_agent_monthly || {})
      end
    end
  end
end
