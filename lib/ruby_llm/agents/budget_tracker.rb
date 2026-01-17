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
        # @param tenant_config [Hash, nil] Optional runtime tenant config (takes priority over resolver/DB)
        # @raise [Reliability::BudgetExceededError] If hard cap is exceeded
        # @return [void]
        def check_budget!(agent_type, tenant_id: nil, tenant_config: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id, runtime_config: tenant_config)

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
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id, runtime_config: tenant_config)

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

          tenant_id = resolve_tenant_id(tenant_id)

          # Increment all relevant counters
          increment_spend(:global, :daily, amount, tenant_id: tenant_id)
          increment_spend(:global, :monthly, amount, tenant_id: tenant_id)
          increment_spend(:agent, :daily, amount, agent_type: agent_type, tenant_id: tenant_id)
          increment_spend(:agent, :monthly, amount, agent_type: agent_type, tenant_id: tenant_id)

          # Check for soft cap alerts
          budget_config = resolve_budget_config(tenant_id, runtime_config: tenant_config)
          check_soft_cap_alerts(agent_type, tenant_id, budget_config) if budget_config[:enabled]
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

          tenant_id = resolve_tenant_id(tenant_id)

          # Increment all relevant token counters
          increment_tokens(:global, :daily, tokens, tenant_id: tenant_id)
          increment_tokens(:global, :monthly, tokens, tenant_id: tenant_id)
          increment_tokens(:agent, :daily, tokens, agent_type: agent_type, tenant_id: tenant_id)
          increment_tokens(:agent, :monthly, tokens, agent_type: agent_type, tenant_id: tenant_id)

          # Check for soft cap alerts
          budget_config = resolve_budget_config(tenant_id, runtime_config: tenant_config)
          check_soft_token_alerts(agent_type, tenant_id, budget_config) if budget_config[:enabled]
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

        # Returns the current token usage for a period (global only)
        #
        # @param period [Symbol] :daily or :monthly
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Integer] Current token usage
        def current_tokens(period, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          key = token_cache_key(period, tenant_id: tenant_id)
          (BudgetTracker.cache_read(key) || 0).to_i
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

        # Returns the remaining token budget for a period (global only)
        #
        # @param period [Symbol] :daily or :monthly
        # @param tenant_id [String, nil] Optional tenant identifier (uses resolver if not provided)
        # @return [Integer, nil] Remaining token budget, or nil if no limit configured
        def remaining_token_budget(period, tenant_id: nil)
          tenant_id = resolve_tenant_id(tenant_id)
          budget_config = resolve_budget_config(tenant_id)

          limit = case period
          when :daily
            budget_config[:global_daily_tokens]
          when :monthly
            budget_config[:global_monthly_tokens]
          end

          return nil unless limit

          [limit - current_tokens(period, tenant_id: tenant_id), 0].max
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
            # Cost budgets
            global_daily: budget_status(:global, :daily, budget_config[:global_daily], tenant_id: tenant_id),
            global_monthly: budget_status(:global, :monthly, budget_config[:global_monthly], tenant_id: tenant_id),
            per_agent_daily: agent_type ? budget_status(:agent, :daily, budget_config[:per_agent_daily]&.dig(agent_type), agent_type: agent_type, tenant_id: tenant_id) : nil,
            per_agent_monthly: agent_type ? budget_status(:agent, :monthly, budget_config[:per_agent_monthly]&.dig(agent_type), agent_type: agent_type, tenant_id: tenant_id) : nil,
            # Token budgets (global only)
            global_daily_tokens: token_status(:daily, budget_config[:global_daily_tokens], tenant_id: tenant_id),
            global_monthly_tokens: token_status(:monthly, budget_config[:global_monthly_tokens], tenant_id: tenant_id),
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
        # Priority order:
        # 1. runtime_config (passed to run())
        # 2. tenant_config_resolver (configured lambda)
        # 3. TenantBudget database record
        # 4. Global configuration
        #
        # @param tenant_id [String, nil] The tenant identifier
        # @param runtime_config [Hash, nil] Runtime config passed to run()
        # @return [Hash] Budget configuration
        def resolve_budget_config(tenant_id, runtime_config: nil)
          config = RubyLLM::Agents.configuration

          # Priority 1: Runtime config passed directly to run()
          if runtime_config.present?
            return normalize_budget_config(runtime_config, config)
          end

          # If multi-tenancy is disabled or no tenant, use global config
          if tenant_id.nil? || !config.multi_tenancy_enabled?
            return global_budget_config(config)
          end

          # Priority 2: tenant_config_resolver lambda
          if config.tenant_config_resolver.present?
            resolved_config = config.tenant_config_resolver.call(tenant_id)
            if resolved_config.present?
              return normalize_budget_config(resolved_config, config)
            end
          end

          # Priority 3: Look up tenant-specific budget from database
          tenant_budget = lookup_tenant_budget(tenant_id)

          if tenant_budget
            tenant_budget.to_budget_config
          else
            # Priority 4: Fall back to global config for unknown tenants
            global_budget_config(config)
          end
        end

        # Builds global budget config from configuration
        #
        # @param config [Configuration] The configuration object
        # @return [Hash] Budget configuration
        def global_budget_config(config)
          {
            enabled: config.budgets_enabled?,
            enforcement: config.budget_enforcement,
            global_daily: config.budgets&.dig(:global_daily),
            global_monthly: config.budgets&.dig(:global_monthly),
            per_agent_daily: config.budgets&.dig(:per_agent_daily),
            per_agent_monthly: config.budgets&.dig(:per_agent_monthly),
            global_daily_tokens: config.budgets&.dig(:global_daily_tokens),
            global_monthly_tokens: config.budgets&.dig(:global_monthly_tokens)
          }
        end

        # Normalizes runtime/resolver config to standard budget config format
        #
        # @param raw_config [Hash] Raw config from runtime or resolver
        # @param global_config [Configuration] Global config for fallbacks
        # @return [Hash] Normalized budget configuration
        def normalize_budget_config(raw_config, global_config)
          enforcement = raw_config[:enforcement]&.to_sym || global_config.budget_enforcement

          {
            enabled: enforcement != :none,
            enforcement: enforcement,
            # Cost/budget limits (USD)
            global_daily: raw_config[:daily_budget_limit],
            global_monthly: raw_config[:monthly_budget_limit],
            per_agent_daily: raw_config[:per_agent_daily] || {},
            per_agent_monthly: raw_config[:per_agent_monthly] || {},
            # Token limits
            global_daily_tokens: raw_config[:daily_token_limit],
            global_monthly_tokens: raw_config[:monthly_token_limit]
          }
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

          @tenant_budget_table_exists = ::ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
        rescue StandardError
          @tenant_budget_table_exists = false
        end

        # Resets the memoized tenant budget table existence check (useful for testing)
        #
        # @return [void]
        def reset_tenant_budget_table_check!
          remove_instance_variable(:@tenant_budget_table_exists) if defined?(@tenant_budget_table_exists)
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

        # Increments the token counter for a period
        #
        # @param scope [Symbol] :global (only global supported for tokens)
        # @param period [Symbol] :daily or :monthly
        # @param tokens [Integer] Tokens to add
        # @param tenant_id [String, nil] The tenant identifier
        # @return [Integer] New total
        def increment_tokens(scope, period, tokens, agent_type: nil, tenant_id: nil)
          # For now, we only track global token usage (not per-agent)
          key = token_cache_key(period, tenant_id: tenant_id)
          ttl = period == :daily ? 1.day : 31.days

          current = (BudgetTracker.cache_read(key) || 0).to_i
          new_total = current + tokens
          BudgetTracker.cache_write(key, new_total, expires_in: ttl)
          new_total
        end

        # Generates a cache key for token tracking
        #
        # @param period [Symbol] :daily or :monthly
        # @param tenant_id [String, nil] The tenant identifier
        # @return [String] Cache key
        def token_cache_key(period, tenant_id: nil)
          date_part = period == :daily ? Date.current.to_s : Date.current.strftime("%Y-%m")
          tenant_part = tenant_id.present? ? "tenant:#{tenant_id}" : "global"

          BudgetTracker.cache_key("tokens", tenant_part, date_part)
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
            current = current_tokens(:daily, tenant_id: tenant_id)
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
            current = current_tokens(:monthly, tenant_id: tenant_id)
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

        # Checks for soft cap token alerts after recording usage
        #
        # @param agent_type [String] The agent class name
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] Budget configuration
        # @return [void]
        def check_soft_token_alerts(agent_type, tenant_id, budget_config)
          config = RubyLLM::Agents.configuration
          return unless config.alerts_enabled?
          return unless config.alert_events.include?(:token_soft_cap) || config.alert_events.include?(:token_hard_cap)

          # Check global daily tokens
          check_token_alert(:global_daily_tokens, budget_config[:global_daily_tokens],
                           current_tokens(:daily, tenant_id: tenant_id),
                           agent_type, tenant_id, budget_config)

          # Check global monthly tokens
          check_token_alert(:global_monthly_tokens, budget_config[:global_monthly_tokens],
                           current_tokens(:monthly, tenant_id: tenant_id),
                           agent_type, tenant_id, budget_config)
        end

        # Checks if a token alert should be fired
        #
        # @param scope [Symbol] Token scope
        # @param limit [Integer, nil] Token limit
        # @param current [Integer] Current token usage
        # @param agent_type [String] Agent type
        # @param tenant_id [String, nil] The tenant identifier
        # @param budget_config [Hash] Budget configuration
        # @return [void]
        def check_token_alert(scope, limit, current, agent_type, tenant_id, budget_config)
          return unless limit
          return if current <= limit

          event = budget_config[:enforcement] == :hard ? :token_hard_cap : :token_soft_cap
          config = RubyLLM::Agents.configuration
          return unless config.alert_events.include?(event)

          # Prevent duplicate alerts
          tenant_part = tenant_id.present? ? "tenant:#{tenant_id}" : "global"
          alert_key = BudgetTracker.cache_key("token_alert", tenant_part, scope, Date.current.to_s)
          return if BudgetTracker.cache_exist?(alert_key)

          BudgetTracker.cache_write(alert_key, true, expires_in: 1.hour)

          AlertManager.notify(event, {
            scope: scope,
            limit: limit,
            total: current,
            agent_type: agent_type,
            tenant_id: tenant_id,
            timestamp: Date.current.to_s
          })
        end

        # Returns token status for a period
        #
        # @param period [Symbol] :daily or :monthly
        # @param limit [Integer, nil] The token limit
        # @param tenant_id [String, nil] The tenant identifier
        # @return [Hash, nil] Status hash or nil if no limit
        def token_status(period, limit, tenant_id: nil)
          return nil unless limit

          current = current_tokens(period, tenant_id: tenant_id)
          {
            limit: limit,
            current: current,
            remaining: [limit - current, 0].max,
            percentage_used: ((current.to_f / limit) * 100).round(2)
          }
        end
      end
    end
  end
end
