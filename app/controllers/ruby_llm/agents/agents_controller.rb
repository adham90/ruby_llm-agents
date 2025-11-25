# frozen_string_literal: true

module RubyLLM
  module Agents
    class AgentsController < ApplicationController
      def index
        @agents = AgentRegistry.all_with_details
      end

      def show
        @agent_type = params[:id]
        @agent_class = AgentRegistry.find(@agent_type)
        @agent_active = @agent_class.present?

        # Get stats for different time periods
        @stats = Execution.stats_for(@agent_type, period: :all_time)
        @stats_today = Execution.stats_for(@agent_type, period: :today)

        # Get available versions for this agent (for filter dropdown)
        @versions = Execution.by_agent(@agent_type).distinct.pluck(:agent_version).compact.sort.reverse

        # Build filtered scope
        base_scope = Execution.by_agent(@agent_type)

        # Apply status filter
        if params[:statuses].present?
          statuses = params[:statuses].is_a?(Array) ? params[:statuses] : params[:statuses].split(",")
          base_scope = base_scope.where(status: statuses) if statuses.any?(&:present?)
        end

        # Apply version filter
        if params[:versions].present?
          versions = params[:versions].is_a?(Array) ? params[:versions] : params[:versions].split(",")
          base_scope = base_scope.where(agent_version: versions) if versions.any?(&:present?)
        end

        # Apply time range filter
        base_scope = base_scope.where("created_at >= ?", params[:days].to_i.days.ago) if params[:days].present?

        # Paginate
        page = (params[:page] || 1).to_i
        per_page = 25
        offset = (page - 1) * per_page

        filtered_scope = base_scope.order(created_at: :desc)
        total_count = filtered_scope.count
        @executions = filtered_scope.limit(per_page).offset(offset)

        @pagination = {
          current_page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count.to_f / per_page).ceil
        }

        # Filter stats for summary display
        @filter_stats = {
          total_count: total_count,
          total_cost: base_scope.sum(:total_cost),
          total_tokens: base_scope.sum(:total_tokens)
        }

        # Get trend data for charts (30 days)
        @trend_data = Execution.trend_analysis(agent_type: @agent_type, days: 30)

        # Get status distribution for pie chart
        @status_distribution = Execution.by_agent(@agent_type)
                                         .group(:status)
                                         .count

        # Agent configuration (if class exists)
        if @agent_class
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
end
