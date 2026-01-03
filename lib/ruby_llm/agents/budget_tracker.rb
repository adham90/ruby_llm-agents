# frozen_string_literal: true

require_relative "cache_helper"

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
        # @raise [Reliability::BudgetExceededError] If hard cap is exceeded
        # @return [void]
        def check_budget!(agent_type, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id)

          return unless budget_config[:enabled]
          return unless budget_config[:enforcement] == :hard

          check_budget_limits!(agent_type, tenant_id, budget_config)
        end

        # Records spend and checks for soft cap alerts
        #
        # @param agent_type [String] The agent class name
        # @param amount [Float] The amount spent in USD
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [void]
        def record_spend!(agent_type, amount, tenant_id: nil)
          return if amount.nil? || amount <= 0

          tenant_id = resolve_tenant_id(tenant_id)

          # Increment all relevant counters
          increment_spend(:global, :daily, amount, tenant_id: tenant_id)
          increment_spend(:global, :monthly, amount, tenant_id: tenant_id)
          increment_spend(:agent, :daily, amount, agent_type: agent_type, tenant_id: tenant_id)
          increment_spend(:agent, :monthly, amount, agent_type: agent_type, tenant_id: tenant_id)

          # Check for soft cap alerts
          budget_config = resolve_budget_config(tenant_id)
          check_soft_cap_alerts(agent_type, tenant_id, budget_config) if budget_config[:enabled]
        end

        # Returns the current spend for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Float] Current spend in USD
        def current_spend(scope, period, agent_type: nil, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          key = budget_cache_key(scope, period, agent_type: agent_type, tenant_id: tenant_id)
          (BudgetTracker.cache_read(key) || 0).to_f
        end

        # Returns the remaining budget for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Float, nil] Remaining budget in USD, or nil if no limit configured
        def remaining_budget(scope, period, agent_type: nil, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id)

          limit = case [scope, period]
          when [:global, :daily]
            budget_config[:global_daily]
          when [:global, :monthly]
            budget_config[:global_monthly]
          when [:agent, :daily]
            budget_config[:per_agent_daily]&.dig(agent_type)
          when [:agent, :monthly]
            budget_config[:per_agent_monthly]&.dig(agent_type)
          end

          return nil unless limit

          [limit - current_spend(scope, period, agent_type: agent_type, tenant_id: tenant_id), 0].max
        end

        # Returns a summary of all budget statuses
        #
        # @param agent_type [String, nil] Optional agent type for per-agent budgets
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Hash] Budget status information
        def status(agent_type: nil, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id)

          {
            tenant_id: tenant_id,
            enabled: budget_config[:enabled],
            enforcement: budget_config[:enforcement],
            global_daily: budget_status(:global, :daily, budget_config[:global_daily], tenant_id: tenant_id),
            global_monthly: budget_status(:global, :monthly, budget_config[:global_monthly], tenant_id: tenant_id),
            per_agent_daily: agent_type ? budget_status(:agent, :daily, budget_config[:per_agent_daily]&.dig(agent_type), agent_type: agent_type, tenant_id: tenant_id) : nil,
            per_agent_monthly: agent_type ? budget_status(:agent, :monthly, budget_config[:per_agent_monthly]&.dig(agent_type), agent_type: agent_type, tenant_id: tenant_id) : nil,
            forecast: calculate_forecast(tenant_id: tenant_id)
          }.compact
        end

        # Calculates budget forecasts based on current spending trends
        #
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Hash, nil] Forecast information
        def calculate_forecast(tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id)

          return nil unless budget_config[:enabled]
          return nil unless budget_config[:global_daily] || budget_config[:global_monthly]

          daily_current = current_spend(:global, :daily, tenant_id: tenant_id)
          monthly_current = current_spend(:global, :monthly, tenant_id: tenant_id)

          # Calculate hours elapsed today and days elapsed this month
          hours_elapsed = Time.current.hour + (Time.current.min / 60.0)
          hours_elapsed = [hours_elapsed, 1].max # Avoid division by zero
          days_in_month = Time.current.end_of_month.day
          day_of_month = Time.current.day
          days_elapsed = day_of_month - 1 + (hours_elapsed / 24.0)
          days_elapsed = [days_elapsed, 1].max

          forecast = {}

          # Daily forecast
          if budget_config[:global_daily]
            daily_rate = daily_current / hours_elapsed
            projected_daily = daily_rate * 24
            forecast[:daily] = {
              current: daily_current.round(4),
              projected: projected_daily.round(4),
              limit: budget_config[:global_daily],
              on_track: projected_daily <= budget_config[:global_daily],
              hours_remaining: (24 - hours_elapsed).round(1),
              rate_per_hour: daily_rate.round(6)
            }
          end

          # Monthly forecast
          if budget_config[:global_monthly]
            monthly_rate = monthly_current / days_elapsed
            projected_monthly = monthly_rate * days_in_month
            days_remaining = days_in_month - day_of_month
            forecast[:monthly] = {
              current: monthly_current.round(4),
              projected: projected_monthly.round(4),
              limit: budget_config[:global_monthly],
              on_track: projected_monthly <= budget_config[:global_monthly],
              days_remaining: days_remaining,
              rate_per_day: monthly_rate.round(4)
            }
          end

          forecast.presence
        end

        # Resets all budget counters (useful for testing)
        #
        # @param tenant_id [String, nil] Optional tenant identifier to reset only that tenant's counters
        # @return [void]
        def reset!(tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          today = Date.current.to_s
          month = Date.current.strftime("%Y-%m")

          tenant_part = tenant_id.present? ? "tenant:#{tenant_id}" : "global"

          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", tenant_part, today))
          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", tenant_part, month))

          # Reset memoized table existence check (useful for testing)
          remove_instance_variable(:@tenant_budget_table_exists) if defined?(@tenant_budget_table_exists)
        end

        private

        # Resolves the current tenant ID
        #
        # @param explicit_tenant_id [String, nil] Explicitly passed tenant ID
        # @return [String, nil] Resolved tenant ID or nil if multi-tenancy disabled
        def resolve_tenant_id(explicit_tenant_id)
          config = RubyLLM::Agents.configuration

          # Ignore tenant_id entirely when multi-tenancy is disabled
          return nil unless config.multi_tenancy_enabled?

          # Use explicit tenant_id if provided, otherwise use resolver
          return explicit_tenant_id if explicit_tenant_id.present?

          config.tenant_resolver&.call
        end

        # Resolves budget configuration for a tenant
        #
        # @param tenant_id [String, nil] The tenant identifier
        # @return [Hash] Budget configuration
        def resolve_budget_config(tenant_id)
          config = RubyLLM::Agents.configuration

          # If multi-tenancy is disabled or no tenant, use global config
          if tenant_id.nil? || !config.multi_tenancy_enabled?
            return {
              enabled: config.budgets_enabled?,
              enforcement: config.budget_enforcement,
              global_daily: config.budgets&.dig(:global_daily),
              global_monthly: config.budgets&.dig(:global_monthly),
              per_agent_daily: config.budgets&.dig(:per_agent_daily),
              per_agent_monthly: config.budgets&.dig(:per_agent_monthly)
            }
          end

          # Look up tenant-specific budget from database (if table exists)
          tenant_budget = lookup_tenant_budget(tenant_id)

          if tenant_budget
            tenant_budget.to_budget_config
          else
            # Fall back to global config for unknown tenants
            {
              enabled: config.budgets_enabled?,
              enforcement: config.budget_enforcement,
              global_daily: config.budgets&.dig(:global_daily),
              global_monthly: config.budgets&.dig(:global_monthly),
              per_agent_daily: config.budgets&.dig(:per_agent_daily),
              per_agent_monthly: config.budgets&.dig(:per_agent_monthly)
            }
          end
        end

        # Safely looks up tenant budget, handling missing table
        #
        # @param tenant_id [String] The tenant identifier
        # @return [TenantBudget, nil] The tenant budget or nil
        def lookup_tenant_budget(tenant_id)
          return nil unless tenant_budget_table_exists?

          TenantBudget.for_tenant(tenant_id)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents] Failed to lookup tenant budget: #{e.message}")
          nil
        end

        # Checks if the tenant_budgets table exists
        #
        # @return [Boolean] true if table exists
        def tenant_budget_table_exists?
          return @tenant_budget_table_exists if defined?(@tenant_budget_table_exists)

          @tenant_budget_table_exists = ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
        rescue StandardError
          @tenant_budget_table_exists = false
        end

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
            current = current_spend(:global, :daily, tenant_id: tenant_id)
            if current >= budget_config[:global_daily]
              raise Reliability::BudgetExceededError.new(:global_daily, budget_config[:global_daily], current, tenant_id: tenant_id)
            end
          end

          # Check global monthly budget
          if budget_config[:global_monthly]
            current = current_spend(:global, :monthly, tenant_id: tenant_id)
            if current >= budget_config[:global_monthly]
              raise Reliability::BudgetExceededError.new(:global_monthly, budget_config[:global_monthly], current, tenant_id: tenant_id)
            end
          end

          # Check per-agent daily budget
          agent_daily_limit = budget_config[:per_agent_daily]&.dig(agent_type)
          if agent_daily_limit
            current = current_spend(:agent, :daily, agent_type: agent_type, tenant_id: tenant_id)
            if current >= agent_daily_limit
              raise Reliability::BudgetExceededError.new(:per_agent_daily, agent_daily_limit, current, agent_type: agent_type, tenant_id: tenant_id)
            end
          end

          # Check per-agent monthly budget
          agent_monthly_limit = budget_config[:per_agent_monthly]&.dig(agent_type)
          if agent_monthly_limit
            current = current_spend(:agent, :monthly, agent_type: agent_type, tenant_id: tenant_id)
            if current >= agent_monthly_limit
              raise Reliability::BudgetExceededError.new(:per_agent_monthly, agent_monthly_limit, current, agent_type: agent_type, tenant_id: tenant_id)
            end
          end
        end

        # Increments the spend counter for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param amount [Float] Amount to add
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] The tenant identifier
        # @return [Float] New total
        def increment_spend(scope, period, amount, agent_type: nil, tenant_id: nil)
          key = budget_cache_key(scope, period, agent_type: agent_type, tenant_id: tenant_id)
          ttl = period == :daily ? 1.day : 31.days

          # Read-modify-write for float values (cache increment is for integers)
          current = (BudgetTracker.cache_read(key) || 0).to_f
          new_total = current + amount
          BudgetTracker.cache_write(key, new_total, expires_in: ttl)
          new_total
        end

        # Generates a cache key for budget tracking
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] The tenant identifier
        # @return [String] Cache key
        def budget_cache_key(scope, period, agent_type: nil, tenant_id: nil)
          date_part = period == :daily ? Date.current.to_s : Date.current.strftime("%Y-%m")
          tenant_part = tenant_id.present? ? "tenant:#{tenant_id}" : "global"

          case scope
          when :global
            BudgetTracker.cache_key("budget", tenant_part, date_part)
          when :agent
            BudgetTracker.cache_key("budget", tenant_part, "agent", agent_type, date_part)
          else
            raise ArgumentError, "Unknown scope: #{scope}"
          end
        end

        # Returns budget status for a scope/period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param limit [Float, nil] The budget limit
        # @param agent_type [String, nil] Required when scope is :agent
        # @param tenant_id [String, nil] The tenant identifier
        # @return [Hash, nil] Status hash or nil if no limit
        def budget_status(scope, period, limit, agent_type: nil, tenant_id: nil)
          return nil unless limit

          current = current_spend(scope, period, agent_type: agent_type, tenant_id: tenant_id)
          {
            limit: limit,
            current: current.round(6),
            remaining: [limit - current, 0].max.round(6),
            percentage_used: ((current / limit) * 100).round(2)
          }
        end

        # Checks for soft cap alerts after recording spend
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] Budget configuration
        # @return [void]
        def check_soft_cap_alerts(agent_type, tenant_id, budget_config)
          config = RubyLLM::Agents.configuration
          return unless config.alerts_enabled?
          return unless config.alert_events.include?(:budget_soft_cap) || config.alert_events.include?(:budget_hard_cap)

          # Check global daily
          check_budget_alert(:global_daily, budget_config[:global_daily],
                            current_spend(:global, :daily, tenant_id: tenant_id),
                            agent_type, tenant_id, budget_config)

          # Check global monthly
          check_budget_alert(:global_monthly, budget_config[:global_monthly],
                            current_spend(:global, :monthly, tenant_id: tenant_id),
                            agent_type, tenant_id, budget_config)

          # Check per-agent daily
          agent_daily_limit = budget_config[:per_agent_daily]&.dig(agent_type)
          if agent_daily_limit
            check_budget_alert(:per_agent_daily, agent_daily_limit,
                              current_spend(:agent, :daily, agent_type: agent_type, tenant_id: tenant_id),
                              agent_type, tenant_id, budget_config)
          end

          # Check per-agent monthly
          agent_monthly_limit = budget_config[:per_agent_monthly]&.dig(agent_type)
          if agent_monthly_limit
            check_budget_alert(:per_agent_monthly, agent_monthly_limit,
                              current_spend(:agent, :monthly, agent_type: agent_type, tenant_id: tenant_id),
                              agent_type, tenant_id, budget_config)
          end
        end

        # Checks if an alert should be fired for a budget
        #
        # @param scope [Symbol] Budget scope
        # @param limit [Float, nil] Budget limit
        # @param current [Float] Current spend
        # @param agent_type [String] Agent type
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] Budget configuration
        # @return [void]
        def check_budget_alert(scope, limit, current, agent_type, tenant_id, budget_config)
          return unless limit
          return if current <= limit

          event = budget_config[:enforcement] == :hard ? :budget_hard_cap : :budget_soft_cap
          config = RubyLLM::Agents.configuration
          return unless config.alert_events.include?(event)

          # Prevent duplicate alerts by using a cache key (include tenant for isolation)
          tenant_part = tenant_id.present? ? "tenant:#{tenant_id}" : "global"
          alert_key = BudgetTracker.cache_key("budget_alert", tenant_part, scope, Date.current.to_s)
          return if BudgetTracker.cache_exist?(alert_key)

          BudgetTracker.cache_write(alert_key, true, expires_in: 1.hour)

          AlertManager.notify(event, {
            scope: scope,
            limit: limit,
            total: current.round(6),
            agent_type: agent_type,
            tenant_id: tenant_id,
            timestamp: Date.current.to_s
          })
        end
      end
    end
  end
end
