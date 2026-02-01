# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Handles lazy reset of usage counters when periods roll over,
      # and provides refresh_counters! for reconciliation from the executions table.
      #
      # @api public
      module Resettable
        extend ActiveSupport::Concern

        # Resets daily counters if the day has rolled over.
        # Uses a WHERE guard to prevent race conditions with concurrent requests.
        #
        # @return [void]
        def ensure_daily_reset!
          return if daily_reset_date == Date.current

          rows = self.class.where(id: id)
            .where("daily_reset_date IS NULL OR daily_reset_date < ?", Date.current)
            .update_all(
              daily_cost_spent: 0,
              daily_tokens_used: 0,
              daily_executions_count: 0,
              daily_error_count: 0,
              daily_reset_date: Date.current
            )

          reload if rows > 0
        end

        # Resets monthly counters if the month has rolled over.
        # Uses a WHERE guard to prevent race conditions with concurrent requests.
        #
        # @return [void]
        def ensure_monthly_reset!
          bom = Date.current.beginning_of_month
          return if monthly_reset_date == bom

          rows = self.class.where(id: id)
            .where("monthly_reset_date IS NULL OR monthly_reset_date < ?", bom)
            .update_all(
              monthly_cost_spent: 0,
              monthly_tokens_used: 0,
              monthly_executions_count: 0,
              monthly_error_count: 0,
              monthly_reset_date: bom
            )

          reload if rows > 0
        end

        # Recalculates all counters from the source-of-truth executions table.
        #
        # Use when counters have drifted due to manual DB edits, failed writes,
        # or after deleting/updating execution records.
        #
        # @return [void]
        def refresh_counters!
          today = Date.current
          bom = today.beginning_of_month

          daily_stats = aggregate_stats(
            executions.where("created_at >= ?", today.beginning_of_day)
          )
          monthly_stats = aggregate_stats(
            executions.where("created_at >= ?", bom.beginning_of_day)
          )

          last_exec = executions.order(created_at: :desc).pick(:created_at, :status)

          update_columns(
            daily_cost_spent:        daily_stats[:cost],
            daily_tokens_used:       daily_stats[:tokens],
            daily_executions_count:  daily_stats[:count],
            daily_error_count:       daily_stats[:errors],
            daily_reset_date:        today,

            monthly_cost_spent:       monthly_stats[:cost],
            monthly_tokens_used:      monthly_stats[:tokens],
            monthly_executions_count: monthly_stats[:count],
            monthly_error_count:      monthly_stats[:errors],
            monthly_reset_date:       bom,

            last_execution_at:     last_exec&.first,
            last_execution_status: last_exec&.last
          )

          reload
        end

        class_methods do
          # Refresh counters for all tenants
          #
          # @return [void]
          def refresh_all_counters!
            find_each(&:refresh_counters!)
          end

          # Refresh counters for active tenants only
          #
          # @return [void]
          def refresh_active_counters!
            active.find_each(&:refresh_counters!)
          end
        end

        private

        # Aggregates cost, tokens, count, and errors from an executions scope.
        #
        # @param scope [ActiveRecord::Relation]
        # @return [Hash] { cost:, tokens:, count:, errors: }
        def aggregate_stats(scope)
          agg = scope.pick(
            Arel.sql("COALESCE(SUM(total_cost), 0)"),
            Arel.sql("COALESCE(SUM(total_tokens), 0)"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END), 0)")
          )

          { cost: agg[0], tokens: agg[1], count: agg[2], errors: agg[3] }
        end
      end
    end
  end
end
