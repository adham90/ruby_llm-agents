# frozen_string_literal: true

module RubyLLM
  module Agents
    class ExecutionsController < ApplicationController
      def index
        @executions = filtered_executions.recent(50)
        @agent_types = Execution.distinct.pluck(:agent_type)
        @statuses = Execution.statuses.keys

        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      def show
        @execution = Execution.find(params[:id])
      end

      def search
        @executions = filtered_executions.recent(50)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "executions_list",
              partial: "ruby_llm/agents/executions/list",
              locals: { executions: @executions }
            )
          end
        end
      end

      private

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
