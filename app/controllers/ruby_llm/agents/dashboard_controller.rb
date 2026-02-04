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
      # Loads now strip data, critical alerts, hourly activity,
      # recent executions, agent comparison, and top errors.
      #
      # @return [void]
      def index
        @selected_range = params[:range].presence || "today"
        @days = range_to_days(@selected_range)
        base_scope = tenant_scoped_executions
        @now_strip = base_scope.now_strip_data(range: @selected_range)
        @critical_alerts = load_critical_alerts(base_scope)
        @recent_executions = base_scope.recent(10)
        @agent_stats = build_agent_comparison(base_scope)
        @top_errors = build_top_errors(base_scope)
        @tenant_budget = load_tenant_budget(base_scope)
        @model_stats = build_model_stats(base_scope)
      end

      # Returns chart data as JSON for live updates
      #
      # @param range [String] Time range: "today", "7d", "30d", "60d", "90d", or custom "YYYY-MM-DD_YYYY-MM-DD"
      # @param compare [String] If "true", include comparison data from previous period
      # @return [JSON] Chart data with series (and optional comparison series)
      def chart_data
        range = params[:range].presence || "today"
        compare = params[:compare] == "true"

        if custom_range?(range)
          from_date, to_date = parse_custom_range(range)
          data = tenant_scoped_executions.activity_chart_json_for_dates(from: from_date, to: to_date)
        else
          data = tenant_scoped_executions.activity_chart_json(range: range)
        end

        if compare
          offset_days = range_to_days(range)
          comparison_data = if custom_range?(range)
            from_date, to_date = parse_custom_range(range)
            tenant_scoped_executions.activity_chart_json_for_dates(
              from: from_date - offset_days.days,
              to: to_date - offset_days.days
            )
          else
            tenant_scoped_executions.activity_chart_json(
              range: range,
              offset_days: offset_days
            )
          end
          data[:comparison] = comparison_data
        end

        render json: data
      end

      private

      # Converts range parameter to number of days
      #
      # @param range [String] Range parameter (today, 7d, 30d, 60d, 90d, or custom YYYY-MM-DD_YYYY-MM-DD)
      # @return [Integer] Number of days
      def range_to_days(range)
        case range
        when "today" then 1
        when "7d" then 7
        when "30d" then 30
        when "60d" then 60
        when "90d" then 90
        else
          # Handle custom range format "YYYY-MM-DD_YYYY-MM-DD"
          if range&.include?("_")
            from_str, to_str = range.split("_")
            from_date = Date.parse(from_str) rescue nil
            to_date = Date.parse(to_str) rescue nil
            if from_date && to_date
              (to_date - from_date).to_i + 1
            else
              1
            end
          else
            1
          end
        end
      end

      # Checks if a range is a custom date range
      #
      # @param range [String] Range parameter
      # @return [Boolean] True if custom date range format
      def custom_range?(range)
        range&.match?(/\A\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\z/)
      end

      # Parses a custom range string into date objects
      #
      # @param range [String] Custom range in format "YYYY-MM-DD_YYYY-MM-DD"
      # @return [Array<Date>] [from_date, to_date]
      def parse_custom_range(range)
        from_str, to_str = range.split("_")
        [Date.parse(from_str), Date.parse(to_str)]
      end

      # Builds per-agent comparison statistics for all agent types
      #
      # Creates separate instance variables for each agent type:
      # - @agent_stats: Base agents
      # - @embedder_stats: Embedders
      # - @transcriber_stats: Transcribers
      # - @speaker_stats: Speakers
      # - @image_generator_stats: Image generators
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter from
      # @return [Array<Hash>] Array of base agent stats (for backward compatibility)
      def build_agent_comparison(base_scope = Execution)
        scope = base_scope.last_n_days(@days)

        # Get ALL agents from registry (file system + execution history)
        all_agent_types = AgentRegistry.all

        # Batch fetch stats for executed agents (4 queries total)
        execution_stats = batch_fetch_agent_stats(scope)

        all_stats = all_agent_types.map do |agent_type|
          agent_class = AgentRegistry.find(agent_type)
          detected_type = AgentRegistry.send(:detect_agent_type, agent_class)

          # Get stats from batch or use zeros for never-executed agents
          stats = execution_stats[agent_type] || {
            count: 0, total_cost: 0, avg_cost: 0, avg_duration_ms: 0, success_rate: 0
          }

          {
            agent_type: agent_type,
            detected_type: detected_type,
            executions: stats[:count],
            total_cost: stats[:total_cost],
            avg_cost: stats[:avg_cost],
            avg_duration_ms: stats[:avg_duration_ms],
            success_rate: stats[:success_rate]
          }
        end.sort_by { |a| [-(a[:executions] || 0), -(a[:total_cost] || 0)] }

        # Split stats by agent type for 5-tab display
        @agent_stats = all_stats.select { |a| a[:detected_type] == "agent" }
        @embedder_stats = all_stats.select { |a| a[:detected_type] == "embedder" }
        @transcriber_stats = all_stats.select { |a| a[:detected_type] == "transcriber" }
        @speaker_stats = all_stats.select { |a| a[:detected_type] == "speaker" }
        @image_generator_stats = all_stats.select { |a| a[:detected_type] == "image_generator" }

        # Return base agents for backward compatibility
        @agent_stats
      end

      # Builds per-model statistics for model comparison and cost breakdown
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter from
      # @return [Array<Hash>] Array of model stats sorted by total cost descending
      def build_model_stats(base_scope = Execution)
        scope = base_scope.last_n_days(@days).where.not(model_id: nil)

        # Batch fetch stats grouped by model
        counts = scope.group(:model_id).count
        costs = scope.group(:model_id).sum(:total_cost)
        tokens = scope.group(:model_id).sum(:total_tokens)
        durations = scope.group(:model_id).average(:duration_ms)
        success_counts = scope.successful.group(:model_id).count

        total_cost = costs.values.sum

        model_ids = counts.keys
        model_ids.map do |model_id|
          count = counts[model_id] || 0
          model_cost = costs[model_id] || 0
          model_tokens = tokens[model_id] || 0
          successful = success_counts[model_id] || 0

          {
            model_id: model_id,
            executions: count,
            total_cost: model_cost,
            total_tokens: model_tokens,
            avg_duration_ms: durations[model_id]&.round || 0,
            success_rate: count > 0 ? (successful.to_f / count * 100).round(1) : 0,
            cost_per_1k_tokens: model_tokens > 0 ? (model_cost / model_tokens * 1000).round(4) : 0,
            cost_percentage: total_cost > 0 ? (model_cost / total_cost * 100).round(1) : 0
          }
        end.sort_by { |m| -(m[:total_cost] || 0) }
      end

      # Builds top errors list
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter from
      # @return [Array<Hash>] Top 5 error classes with counts
      def build_top_errors(base_scope = Execution)
        scope = base_scope.last_n_days(@days).where(status: "error")
        total_errors = scope.count

        scope.group(:error_class)
             .select("error_class, COUNT(*) as count, MAX(created_at) as last_seen")
             .order("count DESC")
             .limit(5)
             .map do |row|
          {
            error_class: row.error_class || "Unknown Error",
            count: row.count,
            percentage: total_errors > 0 ? (row.count.to_f / total_errors * 100).round(1) : 0,
            last_seen: row.last_seen
          }
        end
      end

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

      # Loads budget status for display on dashboard
      #
      # @return [Hash] Budget status with global daily and monthly info
      def load_budget_status
        BudgetTracker.status
      end

      # Loads all open circuit breakers across agents
      #
      # @return [Array<Hash>] Array of open breaker information
      def load_open_breakers
        open_breakers = []

        # Get all agents from execution history
        agent_types = Execution.distinct.pluck(:agent_type)

        agent_types.each do |agent_type|
          # Get the agent class if available
          agent_class = AgentRegistry.find(agent_type)
          next unless agent_class

          # Get circuit breaker config from class methods
          cb_config = agent_class.respond_to?(:circuit_breaker_config) ? agent_class.circuit_breaker_config : nil
          next unless cb_config

          # Get models to check (primary + fallbacks)
          primary_model = agent_class.respond_to?(:model) ? agent_class.model : RubyLLM::Agents.configuration.default_model
          fallbacks = agent_class.respond_to?(:fallback_models) ? agent_class.fallback_models : []
          models_to_check = [primary_model, *fallbacks].compact.uniq

          models_to_check.each do |model_id|
            breaker = CircuitBreaker.from_config(agent_type, model_id, cb_config)
            next unless breaker

            if breaker.open?
              open_breakers << {
                agent_type: agent_type,
                model_id: model_id,
                cooldown_remaining: breaker.time_until_close,
                failure_count: breaker.failure_count,
                threshold: cb_config[:errors] || 5
              }
            end
          end
        end

        open_breakers
      rescue StandardError => e
        Rails.logger.debug("[RubyLLM::Agents] Error loading open breakers: #{e.message}")
        []
      end

      # Loads tenant budget info for the current tenant using counter columns
      #
      # @param base_scope [ActiveRecord::Relation] Base scope (unused, kept for backward compat)
      # @return [Hash, nil] Tenant budget data with usage info, or nil if not applicable
      def load_tenant_budget(base_scope)
        return nil unless tenant_filter_enabled? && current_tenant_id.present?
        return nil unless Tenant.table_exists?

        tenant = Tenant.for(current_tenant_id)
        return nil unless tenant

        tenant.ensure_daily_reset!
        tenant.ensure_monthly_reset!

        daily_spend = tenant.daily_cost_spent
        monthly_spend = tenant.monthly_cost_spent

        {
          tenant_id: current_tenant_id,
          daily_limit: tenant.effective_daily_limit,
          monthly_limit: tenant.effective_monthly_limit,
          daily_spend: daily_spend,
          monthly_spend: monthly_spend,
          daily_percentage: tenant.effective_daily_limit.to_f > 0 ? (daily_spend / tenant.effective_daily_limit * 100).round(1) : 0,
          monthly_percentage: tenant.effective_monthly_limit.to_f > 0 ? (monthly_spend / tenant.effective_monthly_limit * 100).round(1) : 0,
          enforcement: tenant.effective_enforcement,
          per_agent_daily: tenant.per_agent_daily || {}
        }
      end

      # Loads recent alerts from cache
      #
      # @return [Array<Hash>] Array of recent alert events
      def load_recent_alerts
        Rails.cache.fetch("ruby_llm_agents/recent_alerts", expires_in: 1.minute) do
          # Fetch from cache-based alert store (ephemeral for Phase 1)
          alerts_key = "ruby_llm_agents:alerts:recent"
          cached_alerts = RubyLLM::Agents.configuration.cache_store.read(alerts_key) || []
          cached_alerts.take(10)
        end
      end

      # Loads critical alerts for the Action Center
      #
      # Combines open circuit breakers, budget breaches, and error spikes
      # into a single prioritized list (max 3 items).
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter from
      # @return [Array<Hash>] Critical alerts with type and data
      def load_critical_alerts(base_scope = Execution)
        alerts = []

        # Open circuit breakers
        load_open_breakers.each do |breaker|
          alerts << { type: :breaker, data: breaker }
        end

        # Budget breaches (>100% of limit)
        budget_status = load_budget_status
        daily_budget = budget_status&.dig(:global_daily)
        monthly_budget = budget_status&.dig(:global_monthly)

        if daily_budget && daily_budget[:percentage_used].to_f >= 100
          alerts << {
            type: :budget_breach,
            data: {
              period: :daily,
              current: daily_budget[:current_spend],
              limit: daily_budget[:limit]
            }
          }
        end

        if monthly_budget && monthly_budget[:percentage_used].to_f >= 100
          alerts << {
            type: :budget_breach,
            data: {
              period: :monthly,
              current: monthly_budget[:current_spend],
              limit: monthly_budget[:limit]
            }
          }
        end

        # Error spike detection (>5 errors in last 15 minutes)
        error_count_15m = base_scope.status_error.where("created_at > ?", 15.minutes.ago).count
        if error_count_15m >= 5
          alerts << { type: :error_spike, data: { count: error_count_15m } }
        end

        alerts.take(3)
      end

      # Batch fetches execution stats for all agents in a time period
      #
      # @param scope [ActiveRecord::Relation] Base scope with time filter
      # @return [Hash<String, Hash>] Agent type => stats hash
      def batch_fetch_agent_stats(scope)
        counts = scope.group(:agent_type).count
        costs = scope.group(:agent_type).sum(:total_cost)
        success_counts = scope.successful.group(:agent_type).count
        durations = scope.group(:agent_type).average(:duration_ms)

        agent_types = (counts.keys + costs.keys).uniq
        agent_types.each_with_object({}) do |agent_type, hash|
          count = counts[agent_type] || 0
          total_cost = costs[agent_type] || 0
          successful = success_counts[agent_type] || 0

          hash[agent_type] = {
            count: count,
            total_cost: total_cost,
            avg_cost: count > 0 ? (total_cost / count).round(6) : 0,
            avg_duration_ms: durations[agent_type]&.round || 0,
            success_rate: count > 0 ? (successful.to_f / count * 100).round(1) : 0
          }
        end
      end
    end
  end
end
