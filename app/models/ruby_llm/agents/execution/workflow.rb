# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Workflow concern for workflow-related methods and aggregate calculations
      #
      # Provides instance methods for determining workflow type, calculating
      # aggregate statistics across child executions, and retrieving workflow
      # step/branch information.
      #
      # @see RubyLLM::Agents::Execution
      # @api public
      module Workflow
        extend ActiveSupport::Concern

        # Returns whether this is a workflow execution (has workflow_type)
        #
        # @return [Boolean] true if this is a workflow execution
        def workflow?
          workflow_type.present?
        end

        # Returns whether this is a pipeline workflow
        #
        # @return [Boolean] true if workflow_type is "pipeline"
        def pipeline_workflow?
          workflow_type == "pipeline"
        end

        # Returns whether this is a parallel workflow
        #
        # @return [Boolean] true if workflow_type is "parallel"
        def parallel_workflow?
          workflow_type == "parallel"
        end

        # Returns whether this is a router workflow
        #
        # @return [Boolean] true if workflow_type is "router"
        def router_workflow?
          workflow_type == "router"
        end

        # Returns whether this is a root workflow execution (top-level)
        #
        # @return [Boolean] true if this is a workflow with no parent
        def root_workflow?
          workflow? && root?
        end

        # Returns all workflow steps/branches ordered by creation time
        #
        # @return [ActiveRecord::Relation] Child executions for this workflow
        def workflow_steps
          child_executions.order(:created_at)
        end

        # Returns the count of child workflow steps
        #
        # @return [Integer] Number of child executions
        def workflow_steps_count
          child_executions.count
        end

        # @!group Aggregate Statistics

        # Returns aggregate stats for all child executions
        #
        # @return [Hash] Aggregated metrics including cost, tokens, duration
        def workflow_aggregate_stats
          return @workflow_aggregate_stats if defined?(@workflow_aggregate_stats)

          children = child_executions.to_a
          return empty_aggregate_stats if children.empty?

          @workflow_aggregate_stats = {
            total_cost: children.sum { |c| c.total_cost || 0 },
            total_tokens: children.sum { |c| c.total_tokens || 0 },
            input_tokens: children.sum { |c| c.input_tokens || 0 },
            output_tokens: children.sum { |c| c.output_tokens || 0 },
            total_duration_ms: children.sum { |c| c.duration_ms || 0 },
            wall_clock_ms: calculate_wall_clock_duration(children),
            steps_count: children.size,
            successful_count: children.count(&:status_success?),
            failed_count: children.count(&:status_error?),
            timeout_count: children.count(&:status_timeout?),
            running_count: children.count(&:status_running?),
            success_rate: calculate_success_rate(children),
            models_used: children.map(&:model_id).uniq.compact
          }
        end

        # Returns aggregate total cost across all child executions
        #
        # @return [Float] Total cost in USD
        def workflow_total_cost
          workflow_aggregate_stats[:total_cost]
        end

        # Returns aggregate total tokens across all child executions
        #
        # @return [Integer] Total tokens used
        def workflow_total_tokens
          workflow_aggregate_stats[:total_tokens]
        end

        # Returns the wall-clock duration (from first start to last completion)
        #
        # @return [Integer, nil] Duration in milliseconds
        def workflow_wall_clock_ms
          workflow_aggregate_stats[:wall_clock_ms]
        end

        # Returns the sum of all step durations (may exceed wall-clock for parallel)
        #
        # @return [Integer] Sum of all durations in milliseconds
        def workflow_sum_duration_ms
          workflow_aggregate_stats[:total_duration_ms]
        end

        # Returns the overall workflow status based on child executions
        #
        # @return [Symbol] :success, :error, :timeout, :running, or :pending
        def workflow_overall_status
          stats = workflow_aggregate_stats
          return :pending if stats[:steps_count].zero?
          return :running if stats[:running_count] > 0
          return :error if stats[:failed_count] > 0
          return :timeout if stats[:timeout_count] > 0

          :success
        end

        # @!endgroup

        # @!group Pipeline-specific Methods

        # Returns pipeline steps in order with their status
        #
        # @return [Array<Hash>] Array of step hashes with name, status, duration, cost
        def pipeline_steps_detail
          return [] unless pipeline_workflow?

          workflow_steps.map do |step|
            {
              id: step.id,
              name: step.workflow_step || step.agent_type.gsub(/Agent$/, ""),
              agent_type: step.agent_type,
              status: step.status,
              duration_ms: step.duration_ms,
              total_cost: step.total_cost,
              total_tokens: step.total_tokens,
              model_id: step.model_id
            }
          end
        end

        # @!endgroup

        # @!group Parallel-specific Methods

        # Returns parallel branches with their status and timing
        #
        # @return [Array<Hash>] Array of branch hashes
        def parallel_branches_detail
          return [] unless parallel_workflow?

          branches = workflow_steps.to_a
          return [] if branches.empty?

          # Find min/max for timing comparison
          min_duration = branches.map { |b| b.duration_ms || 0 }.min
          max_duration = branches.map { |b| b.duration_ms || 0 }.max

          branches.map do |branch|
            duration = branch.duration_ms || 0
            {
              id: branch.id,
              name: branch.workflow_step || branch.agent_type.gsub(/Agent$/, ""),
              agent_type: branch.agent_type,
              status: branch.status,
              duration_ms: duration,
              total_cost: branch.total_cost,
              total_tokens: branch.total_tokens,
              model_id: branch.model_id,
              is_fastest: duration == min_duration && branches.size > 1,
              is_slowest: duration == max_duration && branches.size > 1 && min_duration != max_duration
            }
          end
        end

        # @!endgroup

        # @!group Router-specific Methods

        # Returns router classification details
        #
        # @return [Hash] Classification info including method, model, timing
        def router_classification_detail
          return {} unless router_workflow?

          result = if classification_result.is_a?(String)
                     begin
                       JSON.parse(classification_result)
                     rescue JSON::ParserError
                       {}
                     end
                   else
                     classification_result || {}
                   end

          {
            method: result["method"],
            classifier_model: result["classifier_model"],
            classification_time_ms: result["classification_time_ms"],
            routed_to: routed_to,
            confidence: result["confidence"]
          }
        end

        # Returns available routes and which one was chosen
        #
        # @return [Hash] Routes info with chosen route highlighted
        def router_routes_detail
          return {} unless router_workflow?

          # Get the routed execution (child)
          routed_child = child_executions.first

          {
            chosen_route: routed_to,
            routed_execution: routed_child ? {
              id: routed_child.id,
              agent_type: routed_child.agent_type,
              status: routed_child.status,
              duration_ms: routed_child.duration_ms,
              total_cost: routed_child.total_cost
            } : nil
          }
        end

        # @!endgroup

        private

        # Returns empty aggregate stats hash
        #
        # @return [Hash] Empty stats with zero values
        def empty_aggregate_stats
          {
            total_cost: 0,
            total_tokens: 0,
            input_tokens: 0,
            output_tokens: 0,
            total_duration_ms: 0,
            wall_clock_ms: nil,
            steps_count: 0,
            successful_count: 0,
            failed_count: 0,
            timeout_count: 0,
            running_count: 0,
            success_rate: 0.0,
            models_used: []
          }
        end

        # Calculates wall-clock duration from child executions
        #
        # @param children [Array<Execution>] Child executions
        # @return [Integer, nil] Duration in milliseconds
        def calculate_wall_clock_duration(children)
          started_times = children.map(&:started_at).compact
          completed_times = children.map(&:completed_at).compact

          return nil if started_times.empty? || completed_times.empty?

          first_start = started_times.min
          last_complete = completed_times.max

          ((last_complete - first_start) * 1000).round
        end

        # Calculates success rate from children
        #
        # @param children [Array<Execution>] Child executions
        # @return [Float] Success rate as percentage
        def calculate_success_rate(children)
          return 0.0 if children.empty?

          completed = children.reject(&:status_running?)
          return 0.0 if completed.empty?

          (completed.count(&:status_success?).to_f / completed.size * 100).round(1)
        end
      end
    end
  end
end
