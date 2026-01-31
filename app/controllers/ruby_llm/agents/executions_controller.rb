# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for browsing and searching execution records
    #
    # Provides paginated listing, filtering, and detail views for all
    # agent executions. Supports both HTML and Turbo Stream responses
    # for seamless filtering without full page reloads.
    #
    # @see Paginatable For pagination implementation
    # @see Filterable For filter parsing and validation
    # @api private
    class ExecutionsController < ApplicationController
      include Paginatable
      include Filterable
      include Sortable

      CSV_COLUMNS = %w[id agent_type agent_version status model_id total_tokens total_cost
                       duration_ms created_at error_class error_message].freeze

      # Lists all executions with filtering and pagination
      #
      # @return [void]
      def index
        load_filter_options
        load_executions_with_stats

        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      # Shows a single execution's details
      #
      # @return [void]
      def show
        @execution = Execution.find(params[:id])
      end

      # Handles filter search requests via Turbo Stream
      #
      # Returns the same data as index but optimized for AJAX/Turbo
      # requests, replacing only the executions list partial.
      #
      # @return [void]
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

      # Exports filtered executions as CSV
      #
      # Streams CSV data with redacted error messages to protect
      # sensitive information. Respects all current filter parameters.
      #
      # @return [void]
      def export
        filename = "executions-#{Date.current.iso8601}.csv"

        headers["Content-Type"] = "text/csv"
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""

        response.status = 200

        self.response_body = Enumerator.new do |yielder|
          yielder << CSV.generate_line(CSV_COLUMNS)

          filtered_executions.find_each(batch_size: 1000) do |execution|
            yielder << generate_csv_row(execution)
          end
        end
      end

      private

      # Generates a CSV row for a single execution with redacted values
      #
      # @param execution [Execution] The execution record
      # @return [String] CSV row string
      def generate_csv_row(execution)
        redacted_error_message = if execution.error_message.present?
                                   Redactor.redact_string(execution.error_message)
                                 end

        CSV.generate_line([
          execution.id,
          execution.agent_type,
          execution.agent_version,
          execution.status,
          execution.model_id,
          execution.total_tokens,
          execution.total_cost&.to_f,
          execution.duration_ms,
          execution.created_at.iso8601,
          execution.error_class,
          redacted_error_message
        ])
      end

      # Loads available options for filter dropdowns
      #
      # Populates @agent_types with all agent types that have executions,
      # @model_ids with all distinct models used, @workflow_types with
      # workflow patterns used, and @statuses with all possible status values.
      #
      # @return [void]
      def load_filter_options
        @agent_types = available_agent_types
        @model_ids = available_model_ids
        @workflow_types = available_workflow_types
        @statuses = Execution.statuses.keys
      end

      # Returns distinct agent types from execution history
      #
      # Memoized to avoid duplicate queries within a request.
      # Uses tenant_scoped_executions to respect multi-tenancy filtering.
      #
      # @return [Array<String>] Agent type names
      def available_agent_types
        @available_agent_types ||= tenant_scoped_executions.distinct.pluck(:agent_type)
      end

      # Returns distinct model IDs from execution history
      #
      # Memoized to avoid duplicate queries within a request.
      # Uses tenant_scoped_executions to respect multi-tenancy filtering.
      #
      # @return [Array<String>] Model IDs
      def available_model_ids
        @available_model_ids ||= tenant_scoped_executions.where.not(model_id: nil).distinct.pluck(:model_id).sort
      end

      # Returns distinct workflow types from execution history
      #
      # Memoized to avoid duplicate queries within a request.
      # Returns empty array if workflow_type column doesn't exist yet.
      # Uses tenant_scoped_executions to respect multi-tenancy filtering.
      #
      # @return [Array<String>] Workflow types (pipeline, parallel, router)
      def available_workflow_types
        return @available_workflow_types if defined?(@available_workflow_types)

        @available_workflow_types = if Execution.column_names.include?("workflow_type")
                                      tenant_scoped_executions.where.not(workflow_type: [nil, ""])
                                                              .distinct.pluck(:workflow_type).sort
                                    else
                                      []
                                    end
      end

      # Loads paginated executions and associated statistics
      #
      # Sets @executions, @pagination, @sort_params, and @filter_stats instance variables
      # for use in views.
      #
      # @return [void]
      def load_executions_with_stats
        @sort_params = parse_sort_params
        result = paginate(filtered_executions, sort_params: @sort_params)
        @executions = result[:records]
        @pagination = result[:pagination]
        load_filter_stats
      end

      # Calculates aggregate statistics for the current filter
      #
      # @return [void]
      def load_filter_stats
        scope = filtered_executions
        @filter_stats = {
          total_count: scope.count,
          total_cost: scope.sum(:total_cost) || 0,
          total_tokens: scope.sum(:total_tokens) || 0
        }
      end

      # Builds a filtered execution scope based on request params
      #
      # Applies filters in order: search, agent type, status, then time range.
      # Each filter is optional and validated before application.
      #
      # @return [ActiveRecord::Relation] Filtered execution scope
      def filtered_executions
        scope = tenant_scoped_executions

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

        # Apply model filter
        model_ids = parse_array_param(:model_ids)
        scope = scope.where(model_id: model_ids) if model_ids.any?

        # Apply workflow type filter (only if column exists)
        if Execution.column_names.include?("workflow_type")
          workflow_types = parse_array_param(:workflow_types)
          if workflow_types.any?
            includes_single = workflow_types.include?("single")
            other_types = workflow_types - ["single"]

            if includes_single && other_types.any?
              # Include both single (null workflow_type) and specific workflow types
              scope = scope.where(workflow_type: [nil, ""] + other_types)
            elsif includes_single
              # Only single executions (non-workflow)
              scope = scope.where(workflow_type: [nil, ""])
            else
              # Only specific workflow types
              scope = scope.where(workflow_type: workflow_types)
            end
          end
        end

        # Apply execution type tab filter (agents vs workflows)
        scope = apply_execution_type_filter(scope)

        # Apply retries filter (show only executions with multiple attempts)
        scope = scope.where("attempts_count > 1") if params[:has_retries].present?

        # Only show root executions (not workflow children) - children are nested under parents
        scope = scope.where(parent_execution_id: nil)

        # Eager load children for workflow grouping
        scope = scope.includes(:child_executions)

        scope
      end

      # Applies execution type filter (all, agents, workflows, or specific workflow type)
      #
      # @param scope [ActiveRecord::Relation] The current scope
      # @return [ActiveRecord::Relation] Filtered scope
      def apply_execution_type_filter(scope)
        return scope unless Execution.column_names.include?("workflow_type")

        execution_type = params[:execution_type]
        case execution_type
        when "agents"
          # Only show executions where workflow_type is null/empty (regular agents)
          scope.where(workflow_type: [nil, ""])
        when "workflows"
          # Only show executions with a workflow_type (any workflow)
          scope.where.not(workflow_type: [nil, ""])
        when "pipeline", "parallel", "router"
          # Show specific workflow type
          scope.where(workflow_type: execution_type)
        else
          scope
        end
      end
    end
  end
end
