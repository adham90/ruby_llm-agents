# frozen_string_literal: true

module RubyLLM
  module Agents
    class ExecutionsController < ApplicationController
      def index
        @agent_types = Execution.distinct.pluck(:agent_type)
        @statuses = Execution.statuses.keys
        load_paginated_executions

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

        respond_to do |format|
          format.html { render :index }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "executions_list",
              partial: "ruby_llm/agents/executions/list",
              locals: { executions: @executions, pagination: @pagination }
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

      def filtered_executions
        scope = Execution.all

        scope = scope.by_agent(params[:agent_type]) if params[:agent_type].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where("created_at >= ?", params[:days].to_i.days.ago) if params[:days].present?

        scope
      end
    end
  end
end
