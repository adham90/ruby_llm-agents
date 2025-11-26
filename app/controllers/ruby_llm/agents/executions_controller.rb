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

      private

      # Loads available options for filter dropdowns
      #
      # Populates @agent_types with all agent types that have executions,
      # and @statuses with all possible status values.
      #
      # @return [void]
      def load_filter_options
        @agent_types = available_agent_types
        @statuses = Execution.statuses.keys
      end

      # Returns distinct agent types from execution history
      #
      # Memoized to avoid duplicate queries within a request.
      #
      # @return [Array<String>] Agent type names
      def available_agent_types
        @available_agent_types ||= Execution.distinct.pluck(:agent_type)
      end

      # Loads paginated executions and associated statistics
      #
      # Sets @executions, @pagination, and @filter_stats instance variables
      # for use in views.
      #
      # @return [void]
      def load_executions_with_stats
        result = paginate(filtered_executions)
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
      # Applies filters in order: agent type, status, then time range.
      # Each filter is optional and validated before application.
      #
      # @return [ActiveRecord::Relation] Filtered execution scope
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
