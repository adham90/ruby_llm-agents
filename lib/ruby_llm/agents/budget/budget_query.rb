# frozen_string_literal: true

require_relative "../cache_helper"

module RubyLLM
  module Agents
    module Budget
      # Query methods for current spend, remaining budget, and status
      #
      # @api private
      module BudgetQuery
        extend CacheHelper

        class << self
          # Returns the current spend for a scope and period
          #
          # @param scope [Symbol] :global or :agent
          # @param period [Symbol] :daily or :monthly
          # @param agent_type [String, nil] Required when scope is :agent
          # @param tenant_id [String, nil] The tenant identifier
          # @return [Float] Current spend in USD
          def current_spend(scope, period, agent_type: nil, tenant_id: nil)
            key = SpendRecorder.budget_cache_key(scope, period, agent_type: agent_type, tenant_id: tenant_id)
            (BudgetQuery.cache_read(key) || 0).to_f
          end

          # Returns the current token usage for a period (global only)
          #
          # @param period [Symbol] :daily or :monthly
          # @param tenant_id [String, nil] The tenant identifier
          # @return [Integer] Current token usage
          def current_tokens(period, tenant_id: nil)
            key = SpendRecorder.token_cache_key(period, tenant_id: tenant_id)
            (BudgetQuery.cache_read(key) || 0).to_i
          end

          # Returns the remaining budget for a scope and period
          #
          # @param scope [Symbol] :global or :agent
          # @param period [Symbol] :daily or :monthly
          # @param agent_type [String, nil] Required when scope is :agent
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [Float, nil] Remaining budget in USD, or nil if no limit configured
          def remaining_budget(scope, period, agent_type: nil, tenant_id: nil, budget_config:)
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
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [Integer, nil] Remaining token budget, or nil if no limit configured
          def remaining_token_budget(period, tenant_id: nil, budget_config:)
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
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [Hash] Budget status information
          def status(agent_type: nil, tenant_id: nil, budget_config:)
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
              forecast: Forecaster.calculate_forecast(tenant_id: tenant_id, budget_config: budget_config)
            }.compact
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
end
