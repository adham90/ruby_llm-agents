# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Executes workflow steps layer-by-layer
      #
      # Processes the execution layers from FlowGraph sequentially.
      # Each layer's steps run sequentially in Phase 1 (parallel in Phase 2).
      # Applies pass mappings to feed outputs between steps.
      #
      class Runner
        attr_reader :context, :graph, :workflow_class

        # @param workflow_class [Class] The workflow class being executed
        # @param graph [FlowGraph] The dependency graph
        # @param context [WorkflowContext] Shared context
        # @param on_failure [Symbol] :stop or :continue
        # @param parent_execution_id [Integer, nil] Parent execution for linking
        # @param root_execution_id [Integer, nil] Root execution for linking
        def initialize(workflow_class:, graph:, context:, on_failure: :stop,
          parent_execution_id: nil, root_execution_id: nil)
          @workflow_class = workflow_class
          @graph = graph
          @context = context
          @on_failure = on_failure
          @parent_execution_id = parent_execution_id
          @root_execution_id = root_execution_id
          @step_timings = {}
        end

        # Execute all layers
        #
        # @return [Hash] Step timings { step_name => { started_at:, completed_at:, duration_ms: } }
        def run
          layers = @graph.execution_layers

          layers.each do |layer|
            run_layer(layer)

            # Check for errors if stop_on_failure
            if @on_failure == :stop
              layer.each do |step_name|
                if @context.errors.key?(step_name)
                  return @step_timings
                end
              end
            end
          end

          @step_timings
        end

        # Get timing data for all steps
        #
        # @return [Hash]
        attr_reader :step_timings

        private

        def run_layer(layer)
          if layer.size == 1 || !parallel_enabled?
            # Sequential execution
            layer.each { |step_name| execute_step(step_name) }
          else
            # Parallel execution (Phase 2)
            execute_parallel(layer)
          end
        end

        def execute_step(step_name)
          step = @graph.step(step_name)
          return unless step

          # Check conditions
          unless step.should_run?(@context)
            return
          end

          started_at = Time.current
          begin
            params = resolve_params(step)
            result = step.agent_class.call(**params)

            @context.store_step_result(step_name, result)
            record_timing(step_name, started_at)
          rescue => e
            @context.store_error(step_name, e)
            record_timing(step_name, started_at)
          end
        end

        def resolve_params(step)
          params = step.params.dup

          # Merge initial workflow params (those not consumed by step names)
          @context.params.each do |key, value|
            params[key] = value unless params.key?(key)
          end

          # Apply pass mappings
          @workflow_class.pass_definitions.each do |pass_def|
            next unless pass_def[:to] == step.name

            source_result = @context.step_result(pass_def[:from])
            next unless source_result

            pass_def[:mapping].each do |target_param, source_key|
              value = extract_value(source_result, source_key)
              params[target_param] = value unless value.nil?
            end
          end

          # Add execution linking params
          params[:parent_execution_id] = @parent_execution_id if @parent_execution_id
          params[:root_execution_id] = @root_execution_id if @root_execution_id

          params
        end

        def extract_value(result, key)
          if result.respond_to?(key)
            result.public_send(key)
          elsif result.respond_to?(:content) && result.content.is_a?(Hash)
            result.content[key] || result.content[key.to_s]
          elsif result.respond_to?(:[])
            result[key]
          end
        end

        def record_timing(step_name, started_at)
          completed_at = Time.current
          @step_timings[step_name] = {
            started_at: started_at,
            completed_at: completed_at,
            duration_ms: ((completed_at - started_at) * 1000).round
          }
        end

        # Override point for Phase 2
        def parallel_enabled?
          false
        end

        # Override point for Phase 2
        def execute_parallel(layer)
          layer.each { |step_name| execute_step(step_name) }
        end
      end
    end
  end
end
