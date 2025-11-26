# frozen_string_literal: true

module RubyLLM
  module Agents
    class AgentsController < ApplicationController
      include Paginatable
      include Filterable

      def index
        @agents = AgentRegistry.all_with_details
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agents: #{e.message}")
        @agents = []
        flash.now[:alert] = "Error loading agents list"
      end

      def show
        @agent_type = params[:id]
        @agent_class = AgentRegistry.find(@agent_type)
        @agent_active = @agent_class.present?

        load_agent_stats
        load_filter_options
        load_filtered_executions
        load_chart_data

        load_agent_config if @agent_class
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agent #{@agent_type}: #{e.message}")
        redirect_to ruby_llm_agents.agents_path, alert: "Error loading agent details"
      end

      private

      def load_agent_stats
        @stats = Execution.stats_for(@agent_type, period: :all_time)
        @stats_today = Execution.stats_for(@agent_type, period: :today)
      end

      def load_filter_options
        # Single query to get all filter options (fixes N+1)
        filter_data = Execution.by_agent(@agent_type)
                               .where.not(agent_version: nil)
                               .or(Execution.by_agent(@agent_type).where.not(model_id: nil))
                               .or(Execution.by_agent(@agent_type).where.not(temperature: nil))
                               .pluck(:agent_version, :model_id, :temperature)

        @versions = filter_data.map(&:first).compact.uniq.sort.reverse
        @models = filter_data.map { |d| d[1] }.compact.uniq.sort
        @temperatures = filter_data.map(&:last).compact.uniq.sort
      end

      def load_filtered_executions
        base_scope = build_filtered_scope
        result = paginate(base_scope)
        @executions = result[:records]
        @pagination = result[:pagination]

        @filter_stats = {
          total_count: result[:pagination][:total_count],
          total_cost: base_scope.sum(:total_cost),
          total_tokens: base_scope.sum(:total_tokens)
        }
      end

      def build_filtered_scope
        scope = Execution.by_agent(@agent_type)

        # Apply status filter with validation
        statuses = parse_array_param(:statuses)
        scope = apply_status_filter(scope, statuses) if statuses.any?

        # Apply version filter
        versions = parse_array_param(:versions)
        scope = scope.where(agent_version: versions) if versions.any?

        # Apply model filter
        models = parse_array_param(:models)
        scope = scope.where(model_id: models) if models.any?

        # Apply temperature filter
        temperatures = parse_array_param(:temperatures)
        scope = scope.where(temperature: temperatures) if temperatures.any?

        # Apply time range filter with validation
        days = parse_days_param
        scope = apply_time_filter(scope, days)

        scope
      end

      def load_chart_data
        @trend_data = Execution.trend_analysis(agent_type: @agent_type, days: 30)
        @status_distribution = Execution.by_agent(@agent_type).group(:status).count
      end

      def load_agent_config
        @config = {
          model: @agent_class.model,
          temperature: @agent_class.temperature,
          version: @agent_class.version,
          timeout: @agent_class.timeout,
          cache_enabled: @agent_class.cache_enabled?,
          cache_ttl: @agent_class.cache_ttl,
          params: @agent_class.params
        }
      end
    end
  end
end
