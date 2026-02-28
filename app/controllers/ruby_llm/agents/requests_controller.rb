# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for browsing tracked request groups
    #
    # Provides listing and detail views for executions grouped by
    # request_id, as set by RubyLLM::Agents.track blocks.
    #
    # @api private
    class RequestsController < ApplicationController
      include Paginatable

      # Lists all tracked requests with aggregated stats
      #
      # @return [void]
      def index
        @sort_column = sanitize_sort_column(params[:sort])
        @sort_direction = (params[:direction] == "asc") ? "asc" : "desc"

        scope = Execution
          .where.not(request_id: [nil, ""])
          .select(
            "request_id",
            "COUNT(*) AS call_count",
            "SUM(total_cost) AS total_cost",
            "SUM(total_tokens) AS total_tokens",
            "MIN(started_at) AS started_at",
            "MAX(completed_at) AS completed_at",
            "SUM(duration_ms) AS total_duration_ms",
            "GROUP_CONCAT(DISTINCT agent_type) AS agent_types_list",
            "GROUP_CONCAT(DISTINCT status) AS statuses_list",
            "MAX(created_at) AS latest_created_at"
          )
          .group(:request_id)

        # Apply time filter
        days = params[:days].to_i
        scope = scope.where("created_at >= ?", days.days.ago) if days > 0

        result = paginate_requests(scope)
        @requests = result[:records]
        @pagination = result[:pagination]

        # Stats
        total_scope = Execution.where.not(request_id: [nil, ""])
        @stats = {
          total_requests: total_scope.distinct.count(:request_id),
          total_cost: total_scope.sum(:total_cost) || 0
        }
      end

      # Shows a single tracked request with all its executions
      #
      # @return [void]
      def show
        @request_id = params[:id]
        @executions = Execution
          .where(request_id: @request_id)
          .order(started_at: :asc)

        if @executions.empty?
          redirect_to ruby_llm_agents.requests_path,
            alert: "Request not found: #{@request_id}"
          return
        end

        @summary = {
          call_count: @executions.count,
          total_cost: @executions.sum(:total_cost) || 0,
          total_tokens: @executions.sum(:total_tokens) || 0,
          started_at: @executions.minimum(:started_at),
          completed_at: @executions.maximum(:completed_at),
          agent_types: @executions.distinct.pluck(:agent_type),
          models_used: @executions.distinct.pluck(:model_id),
          all_successful: @executions.where.not(status: "success").count.zero?,
          error_count: @executions.where(status: "error").count
        }

        if @summary[:started_at] && @summary[:completed_at]
          @summary[:duration_ms] = ((@summary[:completed_at] - @summary[:started_at]) * 1000).to_i
        end
      end

      private

      ALLOWED_SORT_COLUMNS = %w[latest_created_at call_count total_cost total_tokens total_duration_ms].freeze

      def sanitize_sort_column(column)
        ALLOWED_SORT_COLUMNS.include?(column) ? column : "latest_created_at"
      end

      def paginate_requests(scope)
        page = [(params[:page] || 1).to_i, 1].max
        per_page = RubyLLM::Agents.configuration.per_page

        total_count = Execution
          .where.not(request_id: [nil, ""])
          .distinct
          .count(:request_id)

        sorted = scope.order("#{@sort_column} #{@sort_direction.upcase}")
        offset = (page - 1) * per_page

        {
          records: sorted.offset(offset).limit(per_page),
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }
      end
    end
  end
end
