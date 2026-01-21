# frozen_string_literal: true

require_relative "../cache_helper"

module RubyLLM
  module Agents
    module Budget
      # Records spend and token usage, and handles soft cap alerting
      #
      # @api private
      module SpendRecorder
        extend CacheHelper

        class << self
          # Records spend and checks for soft cap alerts
          #
          # @param agent_type [String] The agent class name
          # @param amount [Float] The amount spent in USD
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [void]
          def record_spend!(agent_type, amount, tenant_id:, budget_config:)
            return if amount.nil? || amount <= 0

            # Increment all relevant counters
            increment_spend(:global, :daily, amount, tenant_id: tenant_id)
            increment_spend(:global, :monthly, amount, tenant_id: tenant_id)
            increment_spend(:agent, :daily, amount, agent_type: agent_type, tenant_id: tenant_id)
            increment_spend(:agent, :monthly, amount, agent_type: agent_type, tenant_id: tenant_id)

            # Check for soft cap alerts
            check_soft_cap_alerts(agent_type, tenant_id, budget_config) if budget_config[:enabled]
          end

          # Records token usage and checks for soft cap alerts
          #
          # @param agent_type [String] The agent class name
          # @param tokens [Integer] The number of tokens used
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [void]
          def record_tokens!(agent_type, tokens, tenant_id:, budget_config:)
            return if tokens.nil? || tokens <= 0

            # Increment global token counters (daily and monthly)
            # Note: We only track global token usage, not per-agent (scope is ignored in increment_tokens)
            increment_tokens(:global, :daily, tokens, tenant_id: tenant_id)
            increment_tokens(:global, :monthly, tokens, tenant_id: tenant_id)

            # Check for soft cap alerts
            check_soft_token_alerts(agent_type, tenant_id, budget_config) if budget_config[:enabled]
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
            current = (SpendRecorder.cache_read(key) || 0).to_f
            new_total = current + amount
            SpendRecorder.cache_write(key, new_total, expires_in: ttl)
            new_total
          end

          # Increments the token counter for a period
          #
          # @param scope [Symbol] :global (only global supported for tokens)
          # @param period [Symbol] :daily or :monthly
          # @param tokens [Integer] Tokens to add
          # @param agent_type [String, nil] Not used for tokens
          # @param tenant_id [String, nil] The tenant identifier
          # @return [Integer] New total
          def increment_tokens(scope, period, tokens, agent_type: nil, tenant_id: nil)
            # For now, we only track global token usage (not per-agent)
            key = token_cache_key(period, tenant_id: tenant_id)
            ttl = period == :daily ? 1.day : 31.days

            current = (SpendRecorder.cache_read(key) || 0).to_i
            new_total = current + tokens
            SpendRecorder.cache_write(key, new_total, expires_in: ttl)
            new_total
          end

          # Returns the tenant key part for cache keys
          #
          # @param tenant_id [String, nil] The tenant identifier
          # @return [String] "tenant:{id}" or "global"
          def tenant_key_part(tenant_id)
            tenant_id.present? ? "tenant:#{tenant_id}" : "global"
          end

          # Returns the date key part for cache keys based on period
          #
          # @param period [Symbol] :daily or :monthly
          # @return [String] Date string
          def date_key_part(period)
            period == :daily ? Date.current.to_s : Date.current.strftime("%Y-%m")
          end

          # Generates an alert cache key
          #
          # @param alert_type [String] Type of alert (e.g., "budget_alert", "token_alert")
          # @param scope [Symbol] Alert scope
          # @param tenant_id [String, nil] The tenant identifier
          # @return [String] Cache key
          def alert_cache_key(alert_type, scope, tenant_id)
            SpendRecorder.cache_key(alert_type, tenant_key_part(tenant_id), scope, Date.current.to_s)
          end

          # Generates a cache key for budget tracking
          #
          # @param scope [Symbol] :global or :agent
          # @param period [Symbol] :daily or :monthly
          # @param agent_type [String, nil] Required when scope is :agent
          # @param tenant_id [String, nil] The tenant identifier
          # @return [String] Cache key
          def budget_cache_key(scope, period, agent_type: nil, tenant_id: nil)
            date_part = date_key_part(period)
            tenant_part = tenant_key_part(tenant_id)

            case scope
            when :global
              SpendRecorder.cache_key("budget", tenant_part, date_part)
            when :agent
              SpendRecorder.cache_key("budget", tenant_part, "agent", agent_type, date_part)
            else
              raise ArgumentError, "Unknown scope: #{scope}"
            end
          end

          # Generates a cache key for token tracking
          #
          # @param period [Symbol] :daily or :monthly
          # @param tenant_id [String, nil] The tenant identifier
          # @return [String] Cache key
          def token_cache_key(period, tenant_id: nil)
            SpendRecorder.cache_key("tokens", tenant_key_part(tenant_id), date_key_part(period))
          end

          private

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
                              BudgetQuery.current_spend(:global, :daily, tenant_id: tenant_id),
                              agent_type, tenant_id, budget_config)

            # Check global monthly
            check_budget_alert(:global_monthly, budget_config[:global_monthly],
                              BudgetQuery.current_spend(:global, :monthly, tenant_id: tenant_id),
                              agent_type, tenant_id, budget_config)

            # Check per-agent daily
            agent_daily_limit = budget_config[:per_agent_daily]&.dig(agent_type)
            if agent_daily_limit
              check_budget_alert(:per_agent_daily, agent_daily_limit,
                                BudgetQuery.current_spend(:agent, :daily, agent_type: agent_type, tenant_id: tenant_id),
                                agent_type, tenant_id, budget_config)
            end

            # Check per-agent monthly
            agent_monthly_limit = budget_config[:per_agent_monthly]&.dig(agent_type)
            if agent_monthly_limit
              check_budget_alert(:per_agent_monthly, agent_monthly_limit,
                                BudgetQuery.current_spend(:agent, :monthly, agent_type: agent_type, tenant_id: tenant_id),
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
            key = alert_cache_key("budget_alert", scope, tenant_id)
            return if SpendRecorder.cache_exist?(key)

            SpendRecorder.cache_write(key, true, expires_in: 1.hour)

            AlertManager.notify(event, {
              scope: scope,
              limit: limit,
              total: current.round(6),
              agent_type: agent_type,
              tenant_id: tenant_id,
              timestamp: Date.current.to_s
            })
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
                             BudgetQuery.current_tokens(:daily, tenant_id: tenant_id),
                             agent_type, tenant_id, budget_config)

            # Check global monthly tokens
            check_token_alert(:global_monthly_tokens, budget_config[:global_monthly_tokens],
                             BudgetQuery.current_tokens(:monthly, tenant_id: tenant_id),
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
            key = alert_cache_key("token_alert", scope, tenant_id)
            return if SpendRecorder.cache_exist?(key)

            SpendRecorder.cache_write(key, true, expires_in: 1.hour)

            AlertManager.notify(event, {
              scope: scope,
              limit: limit,
              total: current,
              agent_type: agent_type,
              tenant_id: tenant_id,
              timestamp: Date.current.to_s
            })
          end
        end
      end
    end
  end
end
