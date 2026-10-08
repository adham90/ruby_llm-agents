# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for cost intelligence and analytics
    #
    # Provides interactive, filterable cost analysis across agents, models,
    # and tenants. The filter bar (agent/model/tenant) applies to all sections,
    # making this an exploration tool rather than a static report.
    #
    # @api private
    class AnalyticsController < ApplicationController
      VALID_RANGES = %w[7d 30d 90d custom].freeze
      DEFAULT_RANGE = "30d"

      # Every section covers the same filtered range, so they are all derived
      # from one Breakdown of it: the page scans the range once, plus one
      # aggregate each for the prior period and the month to date. Results
      # are cached, since these ranges are wide and move slowly.
      def index
        @selected_range = sanitize_range(params[:range])
        @days = range_to_days(@selected_range)
        parse_custom_dates if @selected_range == "custom"

        load_filter_options
        base = apply_filters(time_scoped(tenant_scoped_executions))
        prior = apply_filters(prior_period_scope(tenant_scoped_executions))
        breakdown = Execution::Breakdown.new(cached_analytics(:breakdown) { base.breakdown.rows })

        load_summary(breakdown, cached_analytics(:prior) { aggregate(prior) })
        load_projection(base)
        load_savings_opportunity(breakdown)
        @efficiency = breakdown.model_stats
        load_error_cost(breakdown)
      end

      # Returns chart JSON: current period + prior period overlay
      def chart_data
        @selected_range = sanitize_range(params[:range])
        @days = range_to_days(@selected_range)
        parse_custom_dates if @selected_range == "custom"

        set_active_filters
        current_scope = apply_filters(time_scoped(tenant_scoped_executions))
        prior_scope = apply_filters(prior_period_scope(tenant_scoped_executions))

        render json: cached_analytics(:chart) { build_overlay_chart_json(current_scope, prior_scope) }
      end

      private

      # ── Time helpers ──────────────────────────

      def sanitize_range(range)
        VALID_RANGES.include?(range) ? range : DEFAULT_RANGE
      end

      def range_to_days(range)
        case range
        when "7d" then 7
        when "30d" then 30
        when "90d" then 90
        else 30
        end
      end

      def parse_date(value)
        return nil if value.blank?
        date = Date.parse(value)
        return nil if date > Date.current
        return nil if date < 1.year.ago.to_date
        date
      rescue ArgumentError
        nil
      end

      def parse_custom_dates
        from = parse_date(params[:from])
        to = parse_date(params[:to])

        if from && to
          from, to = [from, to].sort
          @custom_from = from
          @custom_to = [to, Date.current].min
          @days = (@custom_to - @custom_from).to_i + 1
        else
          @selected_range = DEFAULT_RANGE
          @days = 30
        end
      end

      def time_scoped(scope)
        if @selected_range == "custom" && @custom_from && @custom_to
          scope.where(created_at: @custom_from.beginning_of_day..@custom_to.end_of_day)
        else
          scope.last_n_days(@days)
        end
      end

      def prior_period_scope(scope)
        if @selected_range == "custom" && @custom_from && @custom_to
          duration = @custom_to - @custom_from + 1
          prior_end = @custom_from - 1.day
          prior_start = prior_end - duration.days + 1.day
          scope.where(created_at: prior_start.beginning_of_day..prior_end.end_of_day)
        else
          scope.where(created_at: (@days * 2).days.ago...@days.days.ago)
        end
      end

      # ── Filters ──────────────────────────

      def load_filter_options
        @available_agents = available_agent_types
        @available_models = available_model_ids
        @available_tenants = if tenant_filter_enabled? && Tenant.table_exists?
          Tenant.pluck(:tenant_id, :name).map { |tid, name| [tid, name.presence || tid] }.sort_by(&:last)
        else
          []
        end

        set_active_filters
      end

      # Resolves the active agent/model/tenant filters from request params.
      # Shared by index (which also loads dropdown options) and chart_data
      # (JSON only) so apply_filters behaves consistently on both endpoints.
      def set_active_filters
        @filter_agent = params[:agent].presence
        @filter_model = params[:model].presence
        @filter_tenant = params[:filter_tenant].presence
        @any_filter = @filter_agent || @filter_model || @filter_tenant
      end

      def apply_filters(scope)
        scope = scope.where(agent_type: @filter_agent) if @filter_agent.present?
        scope = scope.where(model_id: @filter_model) if @filter_model.present?
        scope = scope.where(tenant_id: @filter_tenant) if @filter_tenant.present?
        scope
      end

      # ── Data loaders ──────────────────────────

      # Caches one of the page's figures under the selected range and filters
      def cached_analytics(name, &block)
        cached_stats(:analytics, name, @selected_range, @custom_from, @custom_to,
          @filter_agent, @filter_model, @filter_tenant, expires_in: 5.minutes, &block)
      end

      def load_summary(breakdown, prior_agg)
        totals = breakdown.totals

        @summary = {
          total_cost: totals[:cost],
          total_runs: totals[:total],
          total_tokens: totals[:tokens],
          avg_cost: (totals[:total] > 0) ? (totals[:cost] / totals[:total]) : 0,
          avg_tokens: (totals[:total] > 0) ? (totals[:tokens].to_f / totals[:total]).round : 0,
          cost_change: pct_change(prior_agg[:cost], totals[:cost]),
          runs_change: pct_change(prior_agg[:count], totals[:total]),
          prior_cost: prior_agg[:cost],
          prior_runs: prior_agg[:count]
        }
      end

      def load_projection(base)
        return @projection = nil if @days.nil? || @summary[:total_cost].zero?

        # Calculate daily burn rate and project to end of month
        daily_rate = @summary[:total_cost].to_f / @days
        days_left = (Date.current.end_of_month - Date.current).to_i
        month_so_far = cached_analytics(:month_so_far) do
          base.where("created_at >= ?", Date.current.beginning_of_month.beginning_of_day)
            .sum(:total_cost).to_f
        end

        @projection = {
          daily_rate: daily_rate,
          month_so_far: month_so_far,
          projected_month: month_so_far + (daily_rate * days_left),
          days_left: days_left
        }
      end

      def load_savings_opportunity(breakdown)
        # Find the most expensive model and suggest switching to the cheapest
        model_data = breakdown.configured_model_usage

        @savings = nil
        return if model_data.size < 2

        expensive = model_data.first
        cheapest = model_data.min_by { |m| m[:cost_per_run] }

        return if expensive[:model_id] == cheapest[:model_id]
        return if expensive[:cost_per_run] <= cheapest[:cost_per_run]

        potential_savings = (expensive[:cost_per_run] - cheapest[:cost_per_run]) * expensive[:runs]
        return if potential_savings < 0.001

        @savings = {
          expensive_model: expensive[:model_id],
          expensive_runs: expensive[:runs],
          expensive_cost_per_run: expensive[:cost_per_run],
          cheap_model: cheapest[:model_id],
          cheap_cost_per_run: cheapest[:cost_per_run],
          potential_savings: potential_savings
        }
      end

      def load_error_cost(breakdown)
        error_cost = breakdown.error_cost(limit: 10)

        @error_total_cost = error_cost[:total_cost]
        @error_total_count = error_cost[:total_count]
        @error_breakdown = error_cost[:breakdown]
      end

      # ── Helpers ──────────────────────────

      def aggregate(scope)
        result = scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COALESCE(SUM(total_cost), 0)"),
          Arel.sql("COALESCE(SUM(total_tokens), 0)")
        )
        {count: result[0].to_i, cost: result[1].to_f, tokens: result[2].to_i}
      end

      def pct_change(old_val, new_val)
        return 0.0 if old_val.nil? || old_val.to_f.zero?
        ((new_val.to_f - old_val.to_f) / old_val.to_f * 100).round(1)
      end

      def date_bucket_sql
        if ::ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
          "strftime('%Y-%m-%d', created_at)"
        else
          "date_trunc('day', created_at)::date"
        end
      end

      # Builds current + prior period overlay chart
      def build_overlay_chart_json(current_scope, prior_scope)
        current_daily = daily_cost(current_scope)
        prior_daily = daily_cost(prior_scope)

        current_series = current_daily.sort.map { |date, cost| [date_to_ms(date), cost.round(6)] }
        # Shift prior dates forward so they overlay on the same x-axis
        prior_series = if prior_daily.any? && current_daily.any?
          offset = (Date.parse(current_daily.keys.min) - Date.parse(prior_daily.keys.min)).to_i
          prior_daily.sort.map { |date, cost| [date_to_ms(date, offset_days: offset), cost.round(6)] }
        else
          []
        end

        {
          series: [
            {name: "Current period", data: current_series, type: "areaspline"},
            {name: "Prior period", data: prior_series, type: "spline", dashStyle: "Dash"}
          ]
        }
      end

      def daily_cost(scope)
        scope.select(
          Arel.sql("#{date_bucket_sql} AS bucket"),
          Arel.sql("COALESCE(SUM(total_cost), 0) AS sum_cost")
        ).group(Arel.sql("bucket"))
          .each_with_object({}) { |row, h| h[row["bucket"].to_s] = row["sum_cost"].to_f }
      end

      def date_to_ms(date_str, offset_days: 0)
        (Date.parse(date_str) + offset_days.days).strftime("%s").to_i * 1000
      end
    end
  end
end
