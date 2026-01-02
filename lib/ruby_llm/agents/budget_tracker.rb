# frozen_string_literal: true

require_relative "cache_helper"

module RubyLLM
  module Agents
    # Cache-based budget tracking for cost governance
    #
    # Tracks spending against configured budget limits using cache counters.
    # Supports daily and monthly budgets at both global and per-agent levels.
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
    # @see RubyLLM::Agents::Configuration
    # @see RubyLLM::Agents::Reliability::BudgetExceededError
    # @api public
    module BudgetTracker
      extend CacheHelper

      class << self
        # Checks if the current spend exceeds budget limits
        #
        # @param agent_type [String] The agent class name
        # @raise [Reliability::BudgetExceededError] If hard cap is exceeded
        # @return [void]
        def check_budget!(agent_type)
          config = RubyLLM::Agents.configuration
          return unless config.budgets_enabled?

          budgets = config.budgets
          enforcement = config.budget_enforcement

          # Only block on hard enforcement
          return unless enforcement == :hard

          # Check global daily budget
          if budgets[:global_daily]
            current = current_spend(:global, :daily)
            if current >= budgets[:global_daily]
              raise Reliability::BudgetExceededError.new(:global_daily, budgets[:global_daily], current)
            end
          end

          # Check global monthly budget
          if budgets[:global_monthly]
            current = current_spend(:global, :monthly)
            if current >= budgets[:global_monthly]
              raise Reliability::BudgetExceededError.new(:global_monthly, budgets[:global_monthly], current)
            end
          end

          # Check per-agent daily budget
          agent_daily_limit = budgets[:per_agent_daily]&.dig(agent_type)
          if agent_daily_limit
            current = current_spend(:agent, :daily, agent_type: agent_type)
            if current >= agent_daily_limit
              raise Reliability::BudgetExceededError.new(:per_agent_daily, agent_daily_limit, current, agent_type: agent_type)
            end
          end

          # Check per-agent monthly budget
          agent_monthly_limit = budgets[:per_agent_monthly]&.dig(agent_type)
          if agent_monthly_limit
            current = current_spend(:agent, :monthly, agent_type: agent_type)
            if current >= agent_monthly_limit
              raise Reliability::BudgetExceededError.new(:per_agent_monthly, agent_monthly_limit, current, agent_type: agent_type)
            end
          end
        end

        # Records spend and checks for soft cap alerts
        #
        # @param agent_type [String] The agent class name
        # @param amount [Float] The amount spent in USD
        # @return [void]
        def record_spend!(agent_type, amount)
          return if amount.nil? || amount <= 0

          config = RubyLLM::Agents.configuration
          budgets = config.budgets

          # Increment all relevant counters
          increment_spend(:global, :daily, amount)
          increment_spend(:global, :monthly, amount)
          increment_spend(:agent, :daily, amount, agent_type: agent_type)
          increment_spend(:agent, :monthly, amount, agent_type: agent_type)

          # Check for soft cap alerts if budgets are configured
          return unless budgets.is_a?(Hash)

          check_soft_cap_alerts(agent_type, budgets, config)
        end

        # Returns the current spend for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @return [Float] Current spend in USD
        def current_spend(scope, period, agent_type: nil)
          key = budget_cache_key(scope, period, agent_type: agent_type)
          (BudgetTracker.cache_read(key) || 0).to_f
        end

        # Returns the remaining budget for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @return [Float, nil] Remaining budget in USD, or nil if no limit configured
        def remaining_budget(scope, period, agent_type: nil)
          config = RubyLLM::Agents.configuration
          budgets = config.budgets
          return nil unless budgets.is_a?(Hash)

          limit = case [scope, period]
          when [:global, :daily]
            budgets[:global_daily]
          when [:global, :monthly]
            budgets[:global_monthly]
          when [:agent, :daily]
            budgets[:per_agent_daily]&.dig(agent_type)
          when [:agent, :monthly]
            budgets[:per_agent_monthly]&.dig(agent_type)
          end

          return nil unless limit

          [limit - current_spend(scope, period, agent_type: agent_type), 0].max
        end

        # Returns a summary of all budget statuses
        #
        # @param agent_type [String, nil] Optional agent type for per-agent budgets
        # @return [Hash] Budget status information
        def status(agent_type: nil)
          config = RubyLLM::Agents.configuration
          budgets = config.budgets || {}

          {
            enabled: config.budgets_enabled?,
            enforcement: config.budget_enforcement,
            global_daily: budget_status(:global, :daily, budgets[:global_daily]),
            global_monthly: budget_status(:global, :monthly, budgets[:global_monthly]),
            per_agent_daily: agent_type ? budget_status(:agent, :daily, budgets[:per_agent_daily]&.dig(agent_type), agent_type: agent_type) : nil,
            per_agent_monthly: agent_type ? budget_status(:agent, :monthly, budgets[:per_agent_monthly]&.dig(agent_type), agent_type: agent_type) : nil,
            forecast: calculate_forecast
          }.compact
        end

        # Calculates budget forecasts based on current spending trends
        #
        # @return [Hash, nil] Forecast information
        def calculate_forecast
          config = RubyLLM::Agents.configuration
          budgets = config.budgets || {}

          return nil unless config.budgets_enabled?
          return nil unless budgets[:global_daily] || budgets[:global_monthly]

          daily_current = current_spend(:global, :daily)
          monthly_current = current_spend(:global, :monthly)

          # Calculate hours elapsed today and days elapsed this month
          hours_elapsed = Time.current.hour + (Time.current.min / 60.0)
          hours_elapsed = [hours_elapsed, 1].max # Avoid division by zero
          days_in_month = Time.current.end_of_month.day
          day_of_month = Time.current.day
          days_elapsed = day_of_month - 1 + (hours_elapsed / 24.0)
          days_elapsed = [days_elapsed, 1].max

          forecast = {}

          # Daily forecast
          if budgets[:global_daily]
            daily_rate = daily_current / hours_elapsed
            projected_daily = daily_rate * 24
            forecast[:daily] = {
              current: daily_current.round(4),
              projected: projected_daily.round(4),
              limit: budgets[:global_daily],
              on_track: projected_daily <= budgets[:global_daily],
              hours_remaining: (24 - hours_elapsed).round(1),
              rate_per_hour: daily_rate.round(6)
            }
          end

          # Monthly forecast
          if budgets[:global_monthly]
            monthly_rate = monthly_current / days_elapsed
            projected_monthly = monthly_rate * days_in_month
            days_remaining = days_in_month - day_of_month
            forecast[:monthly] = {
              current: monthly_current.round(4),
              projected: projected_monthly.round(4),
              limit: budgets[:global_monthly],
              on_track: projected_monthly <= budgets[:global_monthly],
              days_remaining: days_remaining,
              rate_per_day: monthly_rate.round(4)
            }
          end

          forecast.presence
        end

        # Resets all budget counters (useful for testing)
        #
        # @return [void]
        def reset!
          # Note: This is a simple implementation. In production, you might want
          # to iterate over all known keys or use cache namespacing.
          today = Date.current.to_s
          month = Date.current.strftime("%Y-%m")

          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", "global", today))
          BudgetTracker.cache_delete(BudgetTracker.cache_key("budget", "global", month))
        end

        private

        # Increments the spend counter for a scope and period
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param amount [Float] Amount to add
        # @param agent_type [String, nil] Required when scope is :agent
        # @return [Float] New total
        def increment_spend(scope, period, amount, agent_type: nil)
          key = budget_cache_key(scope, period, agent_type: agent_type)
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
        # @return [String] Cache key
        def budget_cache_key(scope, period, agent_type: nil)
          date_part = period == :daily ? Date.current.to_s : Date.current.strftime("%Y-%m")

          case scope
          when :global
            BudgetTracker.cache_key("budget", "global", date_part)
          when :agent
            BudgetTracker.cache_key("budget", "agent", agent_type, date_part)
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
        # @return [Hash, nil] Status hash or nil if no limit
        def budget_status(scope, period, limit, agent_type: nil)
          return nil unless limit

          current = current_spend(scope, period, agent_type: agent_type)
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
        # @param budgets [Hash] Budget configuration
        # @param config [Configuration] The configuration
        # @return [void]
        def check_soft_cap_alerts(agent_type, budgets, config)
          return unless config.alerts_enabled?
          return unless config.alert_events.include?(:budget_soft_cap) || config.alert_events.include?(:budget_hard_cap)

          # Check global daily
          check_budget_alert(:global_daily, budgets[:global_daily], current_spend(:global, :daily), agent_type, config)

          # Check global monthly
          check_budget_alert(:global_monthly, budgets[:global_monthly], current_spend(:global, :monthly), agent_type, config)

          # Check per-agent daily
          agent_daily_limit = budgets[:per_agent_daily]&.dig(agent_type)
          if agent_daily_limit
            check_budget_alert(:per_agent_daily, agent_daily_limit, current_spend(:agent, :daily, agent_type: agent_type), agent_type, config)
          end

          # Check per-agent monthly
          agent_monthly_limit = budgets[:per_agent_monthly]&.dig(agent_type)
          if agent_monthly_limit
            check_budget_alert(:per_agent_monthly, agent_monthly_limit, current_spend(:agent, :monthly, agent_type: agent_type), agent_type, config)
          end
        end

        # Checks if an alert should be fired for a budget
        #
        # @param scope [Symbol] Budget scope
        # @param limit [Float, nil] Budget limit
        # @param current [Float] Current spend
        # @param agent_type [String] Agent type
        # @param config [Configuration] Configuration
        # @return [void]
        def check_budget_alert(scope, limit, current, agent_type, config)
          return unless limit
          return if current <= limit

          event = config.budget_enforcement == :hard ? :budget_hard_cap : :budget_soft_cap
          return unless config.alert_events.include?(event)

          # Prevent duplicate alerts by using a cache key
          alert_key = BudgetTracker.cache_key("budget_alert", scope, Date.current.to_s)
          return if BudgetTracker.cache_exist?(alert_key)

          BudgetTracker.cache_write(alert_key, true, expires_in: 1.hour)

          AlertManager.notify(event, {
            scope: scope,
            limit: limit,
            total: current.round(6),
            agent_type: agent_type,
            timestamp: Date.current.to_s
          })
        end
      end
    end
  end
end
