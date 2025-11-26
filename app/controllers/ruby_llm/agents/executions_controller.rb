# frozen_string_literal: true

module RubyLLM
  module Agents
    class ExecutionsController < ApplicationController
      include Paginatable
      include Filterable

      def index
        load_filter_options
        load_executions_with_stats

        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      def show
        @execution = Execution.find(params[:id])
      end

      def search
        load_filter_options
        load_executions_with_stats

        respond_to do |format|
          format.html { render :index }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "executions_list",
              partial: "ruby_llm/agents/executions/list",
              locals: { executions: @executions, pagination: @pagination, filter_stats: @filter_stats }
            )
          end
        end
      end

      private

      def load_filter_options
        @agent_types = available_agent_types
        @statuses = Execution.statuses.keys
      end

      def available_agent_types
        @available_agent_types ||= Execution.distinct.pluck(:agent_type)
      end

      def load_executions_with_stats
        result = paginate(filtered_executions)
        @executions = result[:records]
        @pagination = result[:pagination]
        load_filter_stats
      end

      def load_filter_stats
        scope = filtered_executions
        @filter_stats = {
          total_count: scope.count,
          total_cost: scope.sum(:total_cost) || 0,
          total_tokens: scope.sum(:total_tokens) || 0
        }
      end

      def filtered_executions
        scope = Execution.all

        # Apply agent type filter
        agent_types = parse_array_param(:agent_types)
        if agent_types.any?
          scope = scope.where(agent_type: agent_types)
        elsif params[:agent_type].present?
          scope = scope.by_agent(params[:agent_type])
        end

        # Apply status filter with validation
        statuses = parse_array_param(:statuses)
        if statuses.any?
          scope = apply_status_filter(scope, statuses)
        elsif params[:status].present?
          scope = apply_status_filter(scope, [params[:status]])
        end

        # Apply time filter with validation
        days = parse_days_param
        scope = apply_time_filter(scope, days)

        scope
      end
    end
  end
end
