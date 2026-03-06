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
        @selected_range = sanitize_range(params[:range])
        @days = range_to_days(@selected_range)
        parse_custom_dates if @selected_range == "custom"
        base_scope = tenant_scoped_executions
        @now_strip = build_now_strip(base_scope)
        @critical_alerts = load_critical_alerts(base_scope)
        @recent_executions = base_scope.recent(10)
        @agent_stats = build_agent_comparison(base_scope)
        @top_errors = build_top_errors(base_scope)
        @tenant_budget = load_tenant_budget(base_scope)
        @model_stats = build_model_stats(base_scope)
        @cache_savings = build_cache_savings(base_scope)
        @top_tenants = build_top_tenants
      end

      # Returns chart data as JSON for live updates
      #
      # @param range [String] Time range: "today", "7d", "30d", "90d", or "custom"
      # @return [JSON] Chart data with series
      def chart_data
        range = sanitize_range(params[:range])
        scope = tenant_scoped_executions

        data = if range == "custom"
          from = parse_date(params[:from])
          to = parse_date(params[:to])
          if from && to
            from, to = [from, to].sort
            to = [to, Date.current].min
            scope.activity_chart_json_for_dates(from: from, to: to)
          else
            scope.activity_chart_json(range: "today")
          end
        else
          scope.activity_chart_json(range: range)
        end

        render json: data
      end

      private

      # Whitelists valid range values, defaulting to "today"
      #
      # @param range [String, nil] Raw range parameter
      # @return [String] Sanitized range value
      def sanitize_range(range)
        %w[today 7d 30d 90d custom].include?(range) ? range : "today"
      end

      # Converts range parameter to number of days
      #
      # @param range [String] Range parameter (today, 7d, 30d, 90d, custom)
      # @return [Integer, nil] Number of days, or nil for custom
      def range_to_days(range)
        case range
        when "today" then 1
        when "7d" then 7
        when "30d" then 30
        when "90d" then 90
        when "custom" then nil
        else 1
        end
      end

      # Safely parses a date string with validation
      #
      # Rejects future dates and dates more than 1 year ago.
      #
      # @param value [String, nil] Date string (YYYY-MM-DD)
      # @return [Date, nil] Parsed date or nil if invalid
      def parse_date(value)
        return nil if value.blank?
        date = Date.parse(value)
        return nil if date > Date.current
        return nil if date < 1.year.ago.to_date
        date
      rescue ArgumentError
        nil
      end

      # Parses custom date range params and sets instance variables
      #
      # Falls back to "today" if dates are missing or invalid.
      #
      # @return [void]
      def parse_custom_dates
        from = parse_date(params[:from])
        to = parse_date(params[:to])

        if from && to
          from, to = [from, to].sort
          @custom_from = from
          @custom_to = [to, Date.current].min
          @days = (@custom_to - @custom_from).to_i + 1
        else
          @selected_range = "today"
          @days = 1
        end
      end

      # Returns the correct time scope for the current range
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter
      # @return [ActiveRecord::Relation] Time-scoped relation
      def time_scoped(base_scope)
        if @selected_range == "custom" && @custom_from && @custom_to
          base_scope.where(created_at: @custom_from.beginning_of_day..@custom_to.end_of_day)
        else
          base_scope.last_n_days(@days)
        end
      end

      # Routes to the correct now_strip_data method based on range
      #
      # @param base_scope [ActiveRecord::Relation] Base scope
      # @return [Hash] Now strip metrics
      def build_now_strip(base_scope)
        if @selected_range == "custom" && @custom_from && @custom_to
          base_scope.now_strip_data_for_dates(from: @custom_from, to: @custom_to)
        else
          base_scope.now_strip_data(range: @selected_range)
        end
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
        scope = time_scoped(base_scope)

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

      # Delegates to Execution.model_stats with time scoping
      def build_model_stats(base_scope = Execution)
        Execution.model_stats(scope: time_scoped(base_scope))
      end

      # Delegates to Execution.top_errors with time scoping
      def build_top_errors(base_scope = Execution)
        Execution.top_errors(scope: time_scoped(base_scope))
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
      rescue => e
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
          daily_percentage: (tenant.effective_daily_limit.to_f > 0) ? (daily_spend / tenant.effective_daily_limit * 100).round(1) : 0,
          monthly_percentage: (tenant.effective_monthly_limit.to_f > 0) ? (monthly_spend / tenant.effective_monthly_limit * 100).round(1) : 0,
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
          alerts << {type: :breaker, data: breaker}
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
          alerts << {type: :error_spike, data: {count: error_count_15m}}
        end

        alerts.take(3)
      end

      # Delegates to Execution.cache_savings with time scoping
      def build_cache_savings(base_scope)
        Execution.cache_savings(scope: time_scoped(base_scope))
      end

      # Delegates to Tenant.top_by_spend
      def build_top_tenants
        Tenant.top_by_spend(limit: 5)
      end

      # Delegates to Execution.batch_agent_stats with pre-filtered scope
      def batch_fetch_agent_stats(scope)
        Execution.batch_agent_stats(scope: scope)
      end
    end
  end
end
