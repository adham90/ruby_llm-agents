# frozen_string_literal: true

module RubyLLM
  module Agents
    class DashboardController < ApplicationController
      def index
        @period = params[:period]&.to_sym || :today
        @days = period_to_days(@period)

        @stats = daily_stats
        @recent_executions = Execution.recent(10)

        # Single activity chart showing success/failed over time
        @activity_chart = Execution.activity_chart(days: @days)
      end

      private

      def period_to_days(period)
        case period
        when :today then 1
        when :this_week then 7
        when :this_month then 30
        else 7
        end
      end

      def daily_stats
        scope = Execution.public_send(@period)
        {
          total_executions: scope.count,
          successful: scope.successful.count,
          failed: scope.failed.count,
          total_cost: scope.total_cost_sum || 0,
          total_tokens: scope.total_tokens_sum || 0,
          avg_duration_ms: scope.avg_duration&.round || 0,
          success_rate: calculate_success_rate(scope)
        }
      end

      def calculate_success_rate(scope)
        total = scope.count
        return 0.0 if total.zero?
        (scope.successful.count.to_f / total * 100).round(1)
      end
    end
  end
end
