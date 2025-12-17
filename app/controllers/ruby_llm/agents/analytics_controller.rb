# frozen_string_literal: true

module RubyLLM
  module Agents
    # Analytics controller for the RubyLLM::Agents observability UI
    #
    # Displays comprehensive analytics including cost trends, agent comparisons,
    # and performance metrics over configurable date ranges.
    #
    # @see DashboardController For real-time monitoring
    # @see ExecutionsController For detailed execution browsing
    # @api private
    class AnalyticsController < ApplicationController
      # Renders the main analytics view
      #
      # Loads summary data, trend analysis, agent comparisons,
      # and performance metrics for the selected date range.
      #
      # @return [void]
      def show
        @selected_range = params[:range].presence || "7d"
        @days = range_to_days(@selected_range)

        # Summary data
        @summary = build_summary_data

        # Trend data for charts
        @trend_data = Execution.trend_analysis(days: @days)

        # Agent comparison data
        @agent_stats = build_agent_comparison

        # Top errors
        @top_errors = build_top_errors

        # Hourly heatmap
        @hourly_heatmap = build_hourly_heatmap

        # Performance metrics
        @performance = build_performance_metrics

        # Key insights
        @insights = build_key_insights
      end

      private

      # Converts range parameter to number of days
      #
      # @param range [String] Range parameter (7d, 14d, 30d, 90d)
      # @return [Integer] Number of days
      def range_to_days(range)
        case range
        when "14d" then 14
        when "30d" then 30
        when "90d" then 90
        else 7
        end
      end

      # Builds summary statistics for the selected period
      #
      # @return [Hash] Summary metrics
      def build_summary_data
        scope = Execution.last_n_days(@days)
        total = scope.count
        successful = scope.successful.count

        {
          total_executions: total,
          total_cost: scope.sum(:total_cost) || 0,
          total_tokens: scope.sum(:total_tokens) || 0,
          avg_duration_ms: scope.average(:duration_ms)&.round || 0,
          success_rate: total > 0 ? (successful.to_f / total * 100).round(1) : 0
        }
      end

      # Builds per-agent comparison statistics
      #
      # @return [Array<Hash>] Array of agent stats sorted by cost descending
      def build_agent_comparison
        scope = Execution.last_n_days(@days)
        agent_types = scope.distinct.pluck(:agent_type)

        agent_types.map do |agent_type|
          agent_scope = scope.where(agent_type: agent_type)
          count = agent_scope.count
          total_cost = agent_scope.sum(:total_cost) || 0
          successful = agent_scope.successful.count

          {
            agent_type: agent_type,
            executions: count,
            total_cost: total_cost,
            avg_cost: count > 0 ? (total_cost / count).round(6) : 0,
            total_tokens: agent_scope.sum(:total_tokens) || 0,
            avg_duration_ms: agent_scope.average(:duration_ms)&.round || 0,
            success_rate: count > 0 ? (successful.to_f / count * 100).round(1) : 0
          }
        end.sort_by { |a| -(a[:total_cost] || 0) }
      end

      # Builds top errors list
      #
      # @return [Array<Hash>] Top 10 error classes with counts
      def build_top_errors
        scope = Execution.last_n_days(@days).where(status: "error")
        total_errors = scope.count

        scope.group(:error_class)
             .select("error_class, COUNT(*) as count, MAX(created_at) as last_seen")
             .order("count DESC")
             .limit(10)
             .map do |row|
          {
            error_class: row.error_class || "Unknown Error",
            count: row.count,
            percentage: total_errors > 0 ? (row.count.to_f / total_errors * 100).round(1) : 0,
            last_seen: row.last_seen
          }
        end
      end

      # Builds hourly heatmap data for the last 7 days
      #
      # @return [Hash] Heatmap data with day labels
      def build_hourly_heatmap
        heatmap_data = []
        zone = Time.zone || Time.now.zone

        7.times do |days_ago|
          date = days_ago.days.ago.to_date

          24.times do |hour|
            start_time = zone.local(date.year, date.month, date.day, hour)
            end_time = start_time + 1.hour
            count = Execution.where(created_at: start_time...end_time).count

            # [x (hour), y (day index), value]
            heatmap_data << [hour, 6 - days_ago, count]
          end
        end

        {
          data: heatmap_data,
          days: 7.times.map { |i| (6 - i).days.ago.to_date.strftime("%a %m/%d") }
        }
      end

      # Builds performance metrics for the selected period
      #
      # @return [Hash] Performance metrics
      def build_performance_metrics
        scope = Execution.last_n_days(@days)
        total = scope.count
        successful = scope.successful.count
        failed = scope.failed.count

        {
          success_rate: total > 0 ? (successful.to_f / total * 100).round(1) : 0,
          error_rate: total > 0 ? (failed.to_f / total * 100).round(1) : 0,
          avg_duration_ms: scope.average(:duration_ms)&.round || 0,
          cache_hit_rate: calculate_cache_hit_rate(scope),
          streaming_rate: calculate_streaming_rate(scope),
          rate_limited_rate: calculate_rate_limited_rate(scope)
        }
      end

      # Calculates cache hit rate for a scope
      #
      # @param scope [ActiveRecord::Relation] The execution scope
      # @return [Float] Cache hit rate as percentage
      def calculate_cache_hit_rate(scope)
        total = scope.count
        return 0.0 if total.zero?

        cached = scope.where.not(cached_at: nil).count
        (cached.to_f / total * 100).round(1)
      end

      # Calculates streaming rate for a scope
      #
      # @param scope [ActiveRecord::Relation] The execution scope
      # @return [Float] Streaming rate as percentage
      def calculate_streaming_rate(scope)
        total = scope.count
        return 0.0 if total.zero?

        streaming = scope.where(streaming: true).count
        (streaming.to_f / total * 100).round(1)
      end

      # Calculates rate limited rate for a scope
      #
      # @param scope [ActiveRecord::Relation] The execution scope
      # @return [Float] Rate limited rate as percentage
      def calculate_rate_limited_rate(scope)
        total = scope.count
        return 0.0 if total.zero?

        rate_limited = scope.where(rate_limited: true).count
        (rate_limited.to_f / total * 100).round(1)
      end

      # Builds key insights for the analytics page
      #
      # @return [Hash] Key insights data
      def build_key_insights
        scope = Execution.last_n_days(@days)
        insights = []

        # Most expensive agent
        if @agent_stats.any?
          top_agent = @agent_stats.first
          insights << {
            type: "cost",
            icon: "currency",
            title: "Highest Cost Agent",
            value: top_agent[:agent_type],
            detail: "$#{format("%.4f", top_agent[:total_cost])} total",
            color: "yellow"
          }
        end

        # Busiest hour (from heatmap)
        if @hourly_heatmap[:data].any?
          busiest = @hourly_heatmap[:data].max_by { |d| d[2] }
          hour = busiest[0]
          hour_label = "#{hour.to_s.rjust(2, "0")}:00"
          insights << {
            type: "time",
            icon: "clock",
            title: "Peak Activity Hour",
            value: hour_label,
            detail: "#{busiest[2]} executions",
            color: "purple"
          }
        end

        # Error rate assessment
        error_rate = @performance[:error_rate] || 0
        if error_rate > 10
          insights << {
            type: "warning",
            icon: "alert",
            title: "High Error Rate",
            value: "#{error_rate}%",
            detail: "Consider investigating errors",
            color: "red"
          }
        elsif error_rate > 0
          insights << {
            type: "info",
            icon: "info",
            title: "Error Rate",
            value: "#{error_rate}%",
            detail: "Within normal range",
            color: "gray"
          }
        else
          insights << {
            type: "success",
            icon: "check",
            title: "Error Rate",
            value: "0%",
            detail: "No errors in this period",
            color: "green"
          }
        end

        # Average execution time assessment
        avg_duration = @summary[:avg_duration_ms] || 0
        if avg_duration > 30_000
          insights << {
            type: "performance",
            icon: "timer",
            title: "Avg Response Time",
            value: "#{(avg_duration / 1000.0).round(1)}s",
            detail: "Consider optimization",
            color: "yellow"
          }
        elsif avg_duration > 0
          insights << {
            type: "performance",
            icon: "timer",
            title: "Avg Response Time",
            value: "#{(avg_duration / 1000.0).round(1)}s",
            detail: "Good performance",
            color: "green"
          }
        end

        insights.take(6) # Limit to 6 insights for layout
      end
    end
  end
end
