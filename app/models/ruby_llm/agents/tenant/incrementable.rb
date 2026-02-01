# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Provides atomic SQL increment of usage counters after each execution.
      #
      # @example Recording an execution
      #   tenant.record_execution!(cost: 0.05, tokens: 1200)
      #   tenant.record_execution!(cost: 0.01, tokens: 500, error: true)
      #
      # @api public
      module Incrementable
        extend ActiveSupport::Concern

        # Records an execution by atomically incrementing all counter columns.
        #
        # @param cost [Numeric] The cost of the execution in USD
        # @param tokens [Integer] The number of tokens used
        # @param error [Boolean] Whether the execution was an error
        # @return [void]
        def record_execution!(cost:, tokens:, error: false)
          ensure_daily_reset!
          ensure_monthly_reset!

          error_inc = error ? 1 : 0
          status = error ? "error" : "success"

          self.class.where(id: id).update_all(
            self.class.sanitize_sql_array([
              <<~SQL,
                daily_cost_spent = daily_cost_spent + ?,
                monthly_cost_spent = monthly_cost_spent + ?,
                daily_tokens_used = daily_tokens_used + ?,
                monthly_tokens_used = monthly_tokens_used + ?,
                daily_executions_count = daily_executions_count + 1,
                monthly_executions_count = monthly_executions_count + 1,
                daily_error_count = daily_error_count + ?,
                monthly_error_count = monthly_error_count + ?,
                last_execution_at = ?,
                last_execution_status = ?
              SQL
              cost.to_f, cost.to_f,
              tokens.to_i, tokens.to_i,
              error_inc, error_inc,
              Time.current, status
            ])
          )

          reload
          check_soft_cap_alerts!
        end

        private

        # Checks soft cap alerts after recording an execution.
        #
        # @return [void]
        def check_soft_cap_alerts!
          return unless soft_enforcement?

          config = RubyLLM::Agents.configuration
          return unless config.alerts_enabled?

          check_cost_alerts!
          check_token_alerts!
          check_execution_alerts!
        end

        # @return [void]
        def check_cost_alerts!
          if effective_daily_limit && daily_cost_spent >= effective_daily_limit
            AlertManager.notify(:budget_soft_cap, {
              tenant_id: tenant_id, type: :daily_cost,
              limit: effective_daily_limit, total: daily_cost_spent
            })
          end
          if effective_monthly_limit && monthly_cost_spent >= effective_monthly_limit
            AlertManager.notify(:budget_soft_cap, {
              tenant_id: tenant_id, type: :monthly_cost,
              limit: effective_monthly_limit, total: monthly_cost_spent
            })
          end
        end

        # @return [void]
        def check_token_alerts!
          if effective_daily_token_limit && daily_tokens_used >= effective_daily_token_limit
            AlertManager.notify(:token_soft_cap, {
              tenant_id: tenant_id, type: :daily_tokens,
              limit: effective_daily_token_limit, total: daily_tokens_used
            })
          end
          if effective_monthly_token_limit && monthly_tokens_used >= effective_monthly_token_limit
            AlertManager.notify(:token_soft_cap, {
              tenant_id: tenant_id, type: :monthly_tokens,
              limit: effective_monthly_token_limit, total: monthly_tokens_used
            })
          end
        end

        # @return [void]
        def check_execution_alerts!
          if effective_daily_execution_limit && daily_executions_count >= effective_daily_execution_limit
            AlertManager.notify(:budget_soft_cap, {
              tenant_id: tenant_id, type: :daily_executions,
              limit: effective_daily_execution_limit, total: daily_executions_count
            })
          end
          if effective_monthly_execution_limit && monthly_executions_count >= effective_monthly_execution_limit
            AlertManager.notify(:budget_soft_cap, {
              tenant_id: tenant_id, type: :monthly_executions,
              limit: effective_monthly_execution_limit, total: monthly_executions_count
            })
          end
        end
      end
    end
  end
end
