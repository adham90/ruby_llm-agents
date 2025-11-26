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
      # Loads daily statistics (cached), recent executions, hourly
      # activity data, budget status, and circuit breaker states.
      #
      # @return [void]
      def index
        @stats = daily_stats
        @recent_executions = Execution.recent(RubyLLM::Agents.configuration.recent_executions_limit)
        @hourly_activity = Execution.hourly_activity_chart
        @hourly_cost = Execution.hourly_cost_chart
        @budget_status = load_budget_status
        @open_breakers = load_open_breakers
        @recent_alerts = load_recent_alerts
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
    end
  end
end
