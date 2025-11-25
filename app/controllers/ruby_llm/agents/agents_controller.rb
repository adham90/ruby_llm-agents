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

        # Get recent executions for this agent
        @executions = Execution.by_agent(@agent_type).recent(20)

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
