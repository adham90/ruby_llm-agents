# frozen_string_literal: true

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
          key = cache_key(scope, period, agent_type: agent_type)
          (cache_store.read(key) || 0).to_f
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
            per_agent_monthly: agent_type ? budget_status(:agent, :monthly, budgets[:per_agent_monthly]&.dig(agent_type), agent_type: agent_type) : nil
          }.compact
        end

        # Resets all budget counters (useful for testing)
        #
        # @return [void]
        def reset!
          # Note: This is a simple implementation. In production, you might want
          # to iterate over all known keys or use cache namespacing.
          today = Date.current.to_s
          month = Date.current.strftime("%Y-%m")

          cache_store.delete("ruby_llm_agents:budget:global:#{today}")
          cache_store.delete("ruby_llm_agents:budget:global:#{month}")
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
          key = cache_key(scope, period, agent_type: agent_type)
          ttl = period == :daily ? 1.day : 31.days

          if cache_store.respond_to?(:increment)
            # Ensure key exists with TTL
            cache_store.write(key, 0, expires_in: ttl, unless_exist: true)
            # Note: increment typically works with integers, so we multiply by 1000000
            # to store as cents of a cent, then divide when reading
            # For simplicity, we use read-modify-write here
            current = (cache_store.read(key) || 0).to_f
            new_total = current + amount
            cache_store.write(key, new_total, expires_in: ttl)
            new_total
          else
            current = (cache_store.read(key) || 0).to_f
            new_total = current + amount
            cache_store.write(key, new_total, expires_in: ttl)
            new_total
          end
        end

        # Generates a cache key for budget tracking
        #
        # @param scope [Symbol] :global or :agent
        # @param period [Symbol] :daily or :monthly
        # @param agent_type [String, nil] Required when scope is :agent
        # @return [String] Cache key
        def cache_key(scope, period, agent_type: nil)
          date_part = period == :daily ? Date.current.to_s : Date.current.strftime("%Y-%m")

          case scope
          when :global
            "ruby_llm_agents:budget:global:#{date_part}"
          when :agent
            "ruby_llm_agents:budget:agent:#{agent_type}:#{date_part}"
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
          alert_key = "ruby_llm_agents:budget_alert:#{scope}:#{Date.current}"
          return if cache_store.exist?(alert_key)

          cache_store.write(alert_key, true, expires_in: 1.hour)

          AlertManager.notify(event, {
            scope: scope,
            limit: limit,
            total: current.round(6),
            agent_type: agent_type,
            timestamp: Date.current.to_s
          })
        end

        # Returns the cache store
        #
        # @return [ActiveSupport::Cache::Store]
        def cache_store
          RubyLLM::Agents.configuration.cache_store
        end
      end
    end
  end
end
