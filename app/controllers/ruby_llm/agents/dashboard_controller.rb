# frozen_string_literal: true

module RubyLLM
  module Agents
    class DashboardController < ApplicationController
      def index
        @stats = daily_stats
        @recent_executions = Execution.recent(10)
        @agent_types = Execution.distinct.pluck(:agent_type)
        @cost_by_agent = Execution.cost_by_agent(period: :today)
        @trend = Execution.trend_analysis(days: 7)
      end

      private

      def daily_stats
        today_scope = Execution.today
        {
          total_executions: today_scope.count,
          successful: today_scope.successful.count,
          failed: today_scope.failed.count,
          total_cost: today_scope.total_cost_sum || 0,
          total_tokens: today_scope.total_tokens_sum || 0,
          avg_duration_ms: today_scope.avg_duration&.round || 0,
          success_rate: calculate_success_rate(today_scope)
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
