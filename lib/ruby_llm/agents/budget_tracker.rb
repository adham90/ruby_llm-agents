# frozen_string_literal: true

require_relative "cache_helper"
require_relative "budget/config_resolver"
require_relative "budget/spend_recorder"
require_relative "budget/budget_query"
require_relative "budget/forecaster"

module RubyLLM
  module Agents
    # Cache-based budget tracking for cost governance
    #
    # Tracks spending against configured budget limits using cache counters.
    # Supports daily and monthly budgets at both global and per-agent levels.
    # In multi-tenant mode, budgets are tracked separately per tenant.
    #
    # Note: Uses best-effort enforcement with cache counters. In high-concurrency
    # scenarios, slight overruns may occur due to race conditions. This is an
    # acceptable trade-off for performance.
    #
    # @example Checking budget before execution
    #   BudgetTracker.check_budget!("MyAgent")  # raises BudgetExceededError if over limit
    #
    # @example Recording spend after execution
    #   BudgetTracker.record_spend!("MyAgent", 0.05)
    #
    # @example Multi-tenant usage
    #   BudgetTracker.check_budget!("MyAgent", tenant_id: "acme_corp")
    #   BudgetTracker.record_spend!("MyAgent", 0.05, tenant_id: "acme_corp")
    #
    # @see RubyLLM::Agents::Configuration
    # @see RubyLLM::Agents::Reliability::BudgetExceededError
    # @see RubyLLM::Agents::TenantBudget
    # @api public
    module BudgetTracker
      extend CacheHelper

      class << self
        # Checks if the current spend exceeds budget limits
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @param tenant_config [Hash, nil] Optional runtime tenant config (takes priority over resolver/DB)
        # @raise [Reliability::BudgetExceededError] If hard cap is exceeded
        # @return [void]
        def check_budget!(agent_type, tenant_id: nil, tenant_config: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id, runtime_config: tenant_config)

          return unless budget_config[:enabled]
          return unless budget_config[:enforcement] == :hard

          check_budget_limits!(agent_type, tenant_id, budget_config)
        end

        # Checks if the current token usage exceeds budget limits
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @param tenant_config [Hash, nil] Optional runtime tenant config (takes priority over resolver/DB)
        # @raise [Reliability::BudgetExceededError] If hard cap is exceeded
        # @return [void]
        def check_token_budget!(agent_type, tenant_id: nil, tenant_config: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id, runtime_config: tenant_config)

          return unless budget_config[:enabled]
          return unless budget_config[:enforcement] == :hard

          check_token_limits!(agent_type, tenant_id, budget_config)
        end

        # Records spend and checks for soft cap alerts
        #
        # @param agent_type [String] The agent class name
        # @param amount [Float] The amount spent in USD
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @param tenant_config [Hash, nil] Optional runtime tenant config (takes priority over resolver/DB)
        # @return [void]
        def record_spend!(agent_type, amount, tenant_id: nil, tenant_config: nil)
          return if amount.nil? || amount <= 0

          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id, runtime_config: tenant_config)

          Budget::SpendRecorder.record_spend!(agent_type, amount, tenant_id: tenant_id, budget_config: budget_config)
        end

        # Records token usage and checks for soft cap alerts
        #
        # @param agent_type [String] The agent class name
        # @param tokens [Integer] The number of tokens used
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @param tenant_config [Hash, nil] Optional runtime tenant config (takes priority over resolver/DB)
        # @return [void]
        def record_tokens!(agent_type, tokens, tenant_id: nil, tenant_config: nil)
          return if tokens.nil? || tokens <= 0

          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id, runtime_config: tenant_config)

          Budget::SpendRecorder.record_tokens!(agent_type, tokens, tenant_id: tenant_id, budget_config: budget_config)
        end

        # Returns the current spend for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Float] Current spend in USD
        def current_spend(scope, period, agent_type: nil, tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          Budget::BudgetQuery.current_spend(scope, period, agent_type: agent_type, tenant_id: tenant_id)
        end

        # Returns the current token usage for a period (global only)
        #
        # @param period [Symbol] :daily or :monthly
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Integer] Current token usage
        def current_tokens(period, tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          Budget::BudgetQuery.current_tokens(period, tenant_id: tenant_id)
        end

        # Returns the remaining budget for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Float, nil] Remaining budget in USD, or nil if no limit configured
        def remaining_budget(scope, period, agent_type: nil, tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id)

          Budget::BudgetQuery.remaining_budget(scope, period, agent_type: agent_type, tenant_id: tenant_id, budget_config: budget_config)
        end

        # Returns the remaining token budget for a period (global only)
        #
        # @param period [Symbol] :daily or :monthly
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Integer, nil] Remaining token budget, or nil if no limit configured
        def remaining_token_budget(period, tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id)

          Budget::BudgetQuery.remaining_token_budget(period, tenant_id: tenant_id, budget_config: budget_config)
        end

        # Returns a summary of all budget statuses
        #
        # @param agent_type [String, nil] Optional agent type for per-agent budgets
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Hash] Budget status information
        def status(agent_type: nil, tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id)

          Budget::BudgetQuery.status(agent_type: agent_type, tenant_id: tenant_id, budget_config: budget_config)
        end

        # Calculates budget forecasts based on current spending trends
        #
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Hash, nil] Forecast information
        def calculate_forecast(tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          budget_config = Budget::ConfigResolver.resolve_budget_config(tenant_id)

          Budget::Forecaster.calculate_forecast(tenant_id: tenant_id, budget_config: budget_config)
        end

        # Resets all budget counters (useful for testing)
        #
        # @param tenant_id [String, nil] Optional tenant identifier to reset only that tenant's counters
        # @return [void]
        def reset!(tenant_id: nil)
          tenant_id = Budget::ConfigResolver.resolve_tenant_id(tenant_id)
          tenant_part = Budget::SpendRecorder.tenant_key_part(tenant_id)
          today = Budget::SpendRecorder.date_key_part(:daily)
          month = Budget::SpendRecorder.date_key_part(:monthly)

          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", tenant_part, today))
          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", tenant_part, month))

          # Reset memoized table existence check (useful for testing)
          Budget::ConfigResolver.reset_tenant_budget_table_check!
        end

        private

        # Checks budget limits and raises error if exceeded
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] The budget configuration
        # @raise [Reliability::BudgetExceededError] If limit exceeded
        # @return [void]
        def check_budget_limits!(agent_type, tenant_id, budget_config)
          # Check global daily budget
          if budget_config[:global_daily]
            current = Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: tenant_id)
            if current >= budget_config[:global_daily]
              raise Reliability::BudgetExceededError.new(:global_daily, budget_config[:global_daily], current, tenant_id: tenant_id)
            end
          end

          # Check global monthly budget
          if budget_config[:global_monthly]
            current = Budget::BudgetQuery.current_spend(:global, :monthly, tenant_id: tenant_id)
            if current >= budget_config[:global_monthly]
              raise Reliability::BudgetExceededError.new(:global_monthly, budget_config[:global_monthly], current, tenant_id: tenant_id)
            end
          end

          # Check per-agent daily budget
          agent_daily_limit = budget_config[:per_agent_daily]&.dig(agent_type)
          if agent_daily_limit
            current = Budget::BudgetQuery.current_spend(:agent, :daily, agent_type: agent_type, tenant_id: tenant_id)
            if current >= agent_daily_limit
              raise Reliability::BudgetExceededError.new(:per_agent_daily, agent_daily_limit, current, agent_type: agent_type, tenant_id: tenant_id)
            end
          end

          # Check per-agent monthly budget
          agent_monthly_limit = budget_config[:per_agent_monthly]&.dig(agent_type)
          if agent_monthly_limit
            current = Budget::BudgetQuery.current_spend(:agent, :monthly, agent_type: agent_type, tenant_id: tenant_id)
            if current >= agent_monthly_limit
              raise Reliability::BudgetExceededError.new(:per_agent_monthly, agent_monthly_limit, current, agent_type: agent_type, tenant_id: tenant_id)
            end
          end
        end

        # Checks token limits and raises error if exceeded
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] The budget configuration
        # @raise [Reliability::BudgetExceededError] If limit exceeded
        # @return [void]
        def check_token_limits!(agent_type, tenant_id, budget_config)
          # Check global daily token budget
          if budget_config[:global_daily_tokens]
            current = Budget::BudgetQuery.current_tokens(:daily, tenant_id: tenant_id)
            if current >= budget_config[:global_daily_tokens]
              raise Reliability::BudgetExceededError.new(
                :global_daily_tokens,
                budget_config[:global_daily_tokens],
                current,
                tenant_id: tenant_id
              )
            end
          end

          # Check global monthly token budget
          if budget_config[:global_monthly_tokens]
            current = Budget::BudgetQuery.current_tokens(:monthly, tenant_id: tenant_id)
            if current >= budget_config[:global_monthly_tokens]
              raise Reliability::BudgetExceededError.new(
                :global_monthly_tokens,
                budget_config[:global_monthly_tokens],
                current,
                tenant_id: tenant_id
              )
            end
          end
        end
      end
    end
  end
end
