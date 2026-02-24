# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Aggregated result from a workflow execution
      #
      # Collects step results, total cost/tokens, timing, and status.
      # Follows the same pattern as ImagePipelineResult.
      #
      # @example
      #   result = ContentWorkflow.call(topic: "AI")
      #   result.success?     # => true
      #   result.total_cost   # => 0.0045
      #   result.step(:draft) # => the draft agent's Result
      #
      class WorkflowResult
        attr_reader :step_results, :step_timings, :errors, :started_at, :completed_at,
          :workflow_class, :context_snapshot, :error_class, :error_message
        attr_accessor :execution_id

        # @param step_results [Hash{Symbol => Object}] Step name to result mapping
        # @param step_timings [Hash{Symbol => Hash}] Step name to timing data
        # @param errors [Hash{Symbol => Exception}] Step name to error mapping
        # @param started_at [Time] Workflow start time
        # @param completed_at [Time] Workflow completion time
        # @param workflow_class [String] Name of the workflow class
        # @param context_snapshot [Hash] Final context state
        # @param error_class [String, nil] Top-level error class name
        # @param error_message [String, nil] Top-level error message
        def initialize(step_results:, started_at:, completed_at:, workflow_class:,
          step_timings: {}, errors: {}, context_snapshot: {},
          error_class: nil, error_message: nil)
          @step_results = step_results
          @step_timings = step_timings
          @errors = errors
          @started_at = started_at
          @completed_at = completed_at
          @workflow_class = workflow_class
          @context_snapshot = context_snapshot
          @error_class = error_class
          @error_message = error_message
          @execution_id = nil
        end

        # Status helpers

        # All steps succeeded and no top-level error
        def success?
          return false if @error_class
          return false if @errors.any?

          @step_results.values.all? { |r| result_success?(r) }
        end

        # Any step failed or top-level error
        def error?
          !success?
        end

        # Some steps succeeded but not all
        def partial?
          return false if @step_results.empty?

          has_success = @step_results.values.any? { |r| result_success?(r) }
          has_error = @errors.any? || @step_results.values.any? { |r| !result_success?(r) }
          has_success && has_error
        end

        # Step access

        # Get a specific step's result
        #
        # @param name [Symbol] Step name
        # @return [Object, nil] The step result
        def step(name)
          @step_results[name.to_sym]
        end

        alias_method :[], :step

        # Get all step names
        def step_names
          @step_results.keys
        end

        # Get the result of the last step
        def final_result
          @step_results.values.last
        end

        # Get the content of the final step's result
        def content
          last = final_result
          last.respond_to?(:content) ? last.content : last
        end

        # Count helpers

        def step_count
          @step_results.size + @errors.count { |k, _| !@step_results.key?(k) }
        end

        def successful_step_count
          @step_results.count { |_, r| result_success?(r) }
        end

        def failed_step_count
          @errors.size
        end

        # Cost aggregation

        def total_cost
          @step_results.values.sum { |r| r.respond_to?(:total_cost) ? (r.total_cost || 0) : 0 }
        end

        def input_cost
          @step_results.values.sum { |r| r.respond_to?(:input_cost) ? (r.input_cost || 0) : 0 }
        end

        def output_cost
          @step_results.values.sum { |r| r.respond_to?(:output_cost) ? (r.output_cost || 0) : 0 }
        end

        # Token aggregation

        def total_tokens
          input_tokens + output_tokens
        end

        def input_tokens
          @step_results.values.sum { |r| r.respond_to?(:input_tokens) ? (r.input_tokens || 0) : 0 }
        end

        def output_tokens
          @step_results.values.sum { |r| r.respond_to?(:output_tokens) ? (r.output_tokens || 0) : 0 }
        end

        # Timing

        def duration_ms
          return 0 unless @started_at && @completed_at
          ((@completed_at - @started_at) * 1000).round
        end

        # The primary model (from first step)
        def primary_model_id
          first = @step_results.values.first
          first.respond_to?(:model_id) ? first.model_id : nil
        end

        # Serialization

        def to_h
          {
            success: success?,
            partial: partial?,
            step_count: step_count,
            successful_steps: successful_step_count,
            failed_steps: failed_step_count,
            steps: @step_results.map { |name, result|
              {
                name: name,
                success: result_success?(result),
                cost: result.respond_to?(:total_cost) ? result.total_cost : nil,
                duration_ms: @step_timings.dig(name, :duration_ms)
              }
            },
            errors: @errors.transform_values { |e| {class: e.class.name, message: e.message} },
            total_cost: total_cost,
            total_tokens: total_tokens,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            duration_ms: duration_ms,
            started_at: @started_at&.iso8601,
            completed_at: @completed_at&.iso8601,
            workflow_class: @workflow_class,
            error_class: @error_class,
            error_message: @error_message,
            execution_id: @execution_id
          }
        end

        # Load associated execution record
        def execution
          @execution ||= RubyLLM::Agents::Execution.find_by(id: @execution_id) if @execution_id
        end

        private

        def result_success?(result)
          if result.respond_to?(:success?)
            result.success?
          else
            !result.nil?
          end
        end
      end
    end
  end
end
