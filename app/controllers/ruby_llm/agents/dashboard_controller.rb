# frozen_string_literal: true

module RubyLLM
  module Agents
    class DashboardController < ApplicationController
      def index
        @stats = daily_stats
        @recent_executions = Execution.recent(RubyLLM::Agents.configuration.recent_executions_limit)
        @hourly_activity = Execution.hourly_activity_chart
      end

      private

      def daily_stats
        Rails.cache.fetch("ruby_llm_agents/daily_stats/#{Date.current}", expires_in: 1.minute) do
          scope = Execution.today
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
      end

      def calculate_success_rate(scope)
        total = scope.count
        return 0.0 if total.zero?
        (scope.successful.count.to_f / total * 100).round(1)
      end
    end
  end
end
