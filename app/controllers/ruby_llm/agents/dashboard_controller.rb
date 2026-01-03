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
      end

      # Returns chart data as JSON for live updates
      #
      # @param range [String] Time range: "today", "7d", or "30d"
      # @return [JSON] Chart data with series
      def chart_data
        range = params[:range].presence || "today"
        render json: tenant_scoped_executions.activity_chart_json(range: range)
      end

      private

      # Converts range parameter to number of days
      #
      # @param range [String] Range parameter (today, 7d, 30d)
      # @return [Integer] Number of days
      def range_to_days(range)
        case range
        when "today" then 1
        when "7d" then 7
        when "30d" then 30
        else 1
        end
      end

      # Builds per-agent comparison statistics
      #
      # @param base_scope [ActiveRecord::Relation] Base scope to filter from
      # @return [Array<Hash>] Array of all stats sorted by cost descending
      def build_agent_comparison(base_scope = Execution)
        scope = base_scope.last_n_days(@days)
        agent_types = scope.distinct.pluck(:agent_type)

        all_stats = agent_types.map do |agent_type|
          agent_scope = scope.where(agent_type: agent_type)
          count = agent_scope.count
          total_cost = agent_scope.sum(:total_cost) || 0
          successful = agent_scope.successful.count

          # Detect if this is a workflow
          agent_class = AgentRegistry.find(agent_type)
          is_workflow = agent_class&.ancestors&.any? { |a| a.name&.include?("Workflow") }
          workflow_type = is_workflow ? detect_workflow_type(agent_class) : nil

          {
            agent_type: agent_type,
            executions: count,
            total_cost: total_cost,
            avg_cost: count > 0 ? (total_cost / count).round(6) : 0,
            avg_duration_ms: agent_scope.average(:duration_ms)&.round || 0,
            success_rate: count > 0 ? (successful.to_f / count * 100).round(1) : 0,
            is_workflow: is_workflow,
            workflow_type: workflow_type
          }
        end.sort_by { |a| -(a[:total_cost] || 0) }

        # Split into agents and workflows for tabbed display
        @workflow_stats = all_stats.select { |a| a[:is_workflow] }
        all_stats.reject { |a| a[:is_workflow] }
      end

      # Detects workflow type from class hierarchy
      #
      # @param agent_class [Class] The agent class
      # @return [String, nil] "pipeline", "parallel", "router", or nil
      def detect_workflow_type(agent_class)
        return nil unless agent_class

        ancestors = agent_class.ancestors.map { |a| a.name.to_s }

        if ancestors.include?("RubyLLM::Agents::Workflow::Pipeline")
          "pipeline"
        elsif ancestors.include?("RubyLLM::Agents::Workflow::Parallel")
          "parallel"
        elsif ancestors.include?("RubyLLM::Agents::Workflow::Router")
          "router"
        end
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
    end
  end
end
