# frozen_string_literal: true

module RubyLLM
  module Agents
    # Dashboard controller for the RubyLLM::Agents observability UI
    #
    # Displays high-level statistics, recent executions, and activity charts
    # for monitoring agent performance at a glance.
    #
    # @see ExecutionsController For detailed execution browsing
    # @see AgentsController For per-agent analytics
    # @api private
    class DashboardController < ApplicationController
      # Renders the main dashboard view
      #
      # Loads daily statistics (cached), recent executions, and hourly
      # activity data for the chart visualization.
      #
      # @return [void]
      def index
        @stats = daily_stats
        @recent_executions = Execution.recent(RubyLLM::Agents.configuration.recent_executions_limit)
        @hourly_activity = Execution.hourly_activity_chart
      end

      private

      # Fetches cached daily statistics for the dashboard
      #
      # Results are cached for 1 minute to reduce database load while
      # keeping the dashboard reasonably up-to-date.
      #
      # @return [Hash] Daily statistics
      # @option return [Integer] :total_executions Total execution count today
      # @option return [Integer] :successful Successful execution count
      # @option return [Integer] :failed Failed execution count
      # @option return [Float] :total_cost Combined cost of all executions
      # @option return [Integer] :total_tokens Combined token usage
      # @option return [Integer] :avg_duration_ms Average execution duration
      # @option return [Float] :success_rate Percentage of successful executions
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

      # Calculates the success rate percentage for a scope
      #
      # @param scope [ActiveRecord::Relation] The execution scope to calculate from
      # @return [Float] Success rate as a percentage (0.0-100.0)
      def calculate_success_rate(scope)
        total = scope.count
        return 0.0 if total.zero?
        (scope.successful.count.to_f / total * 100).round(1)
      end
    end
  end
end
