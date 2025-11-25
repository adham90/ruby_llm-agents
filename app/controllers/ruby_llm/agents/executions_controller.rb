# frozen_string_literal: true

module RubyLLM
  module Agents
    class ExecutionsController < ApplicationController
      def index
        @agent_types = Execution.distinct.pluck(:agent_type)
        @statuses = Execution.statuses.keys
        load_paginated_executions
        load_filter_stats

        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      def show
        @execution = Execution.find(params[:id])
      end

      def search
        @agent_types = Execution.distinct.pluck(:agent_type)
        @statuses = Execution.statuses.keys
        load_paginated_executions
        load_filter_stats

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

      def load_paginated_executions
        page = (params[:page] || 1).to_i
        per_page = 25
        offset = (page - 1) * per_page

        base_scope = filtered_executions.order(created_at: :desc)
        total_count = base_scope.count
        @executions = base_scope.limit(per_page).offset(offset)

        @pagination = {
          current_page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count.to_f / per_page).ceil
        }
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

        # Support multiple agent types (comma-separated or array)
        if params[:agent_types].present?
          agent_types = params[:agent_types].is_a?(Array) ? params[:agent_types] : params[:agent_types].split(",")
          scope = scope.where(agent_type: agent_types) if agent_types.any?(&:present?)
        elsif params[:agent_type].present?
          scope = scope.by_agent(params[:agent_type])
        end

        # Support multiple statuses (comma-separated or array)
        if params[:statuses].present?
          statuses = params[:statuses].is_a?(Array) ? params[:statuses] : params[:statuses].split(",")
          scope = scope.where(status: statuses) if statuses.any?(&:present?)
        elsif params[:status].present?
          scope = scope.where(status: params[:status])
        end

        scope = scope.where("created_at >= ?", params[:days].to_i.days.ago) if params[:days].present?

        scope
      end
    end
  end
end
