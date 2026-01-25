# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Executes iteration steps with sequential or parallel processing
        #
        # Handles `each:` option on steps to process collections with support for:
        # - Sequential iteration
        # - Parallel iteration with configurable concurrency
        # - Fail-fast behavior
        # - Continue-on-error behavior
        #
        # @api private
        class IterationExecutor
          attr_reader :workflow, :config, :previous_result

          # @param workflow [Workflow] The workflow instance
          # @param config [StepConfig] The step configuration
          # @param previous_result [Result, nil] Previous step result
          def initialize(workflow, config, previous_result)
            @workflow = workflow
            @config = config
            @previous_result = previous_result
          end

          # Executes the iteration
          #
          # @yield [chunk] Streaming callback
          # @return [IterationResult] Aggregated results for all items
          def execute(&block)
            items = resolve_items
            return Workflow::IterationResult.empty(config.name) if items.empty?

            if config.iteration_concurrency && config.iteration_concurrency > 1
              execute_parallel(items, &block)
            else
              execute_sequential(items, &block)
            end
          end

          private

          def resolve_items
            source = config.each_source
            items = workflow.instance_exec(&source)
            Array(items)
          rescue StandardError => e
            raise IterationSourceError, "Failed to resolve iteration source: #{e.message}"
          end

          def execute_sequential(items, &block)
            item_results = []
            errors = {}

            items.each_with_index do |item, index|
              begin
                result = execute_for_item(item, index, &block)
                item_results << result

                # Check for fail-fast on error
                if config.iteration_fail_fast? && result.respond_to?(:error?) && result.error?
                  break
                end
              rescue StandardError => e
                if config.iteration_fail_fast?
                  errors[index] = e
                  break
                elsif config.continue_on_error?
                  errors[index] = e
                  # Continue to next item
                else
                  raise
                end
              end
            end

            Workflow::IterationResult.new(
              step_name: config.name,
              item_results: item_results,
              errors: errors
            )
          end

          def execute_parallel(items, &block)
            results_mutex = Mutex.new
            item_results = Array.new(items.size)
            errors = {}
            aborted = false

            pool = create_executor_pool(config.iteration_concurrency)

            items.each_with_index do |item, index|
              pool.post do
                next if aborted

                begin
                  result = execute_for_item(item, index, &block)

                  results_mutex.synchronize do
                    item_results[index] = result

                    # Check for fail-fast
                    if config.iteration_fail_fast? && result.respond_to?(:error?) && result.error?
                      aborted = true
                      pool.abort! if pool.respond_to?(:abort!)
                    end
                  end
                rescue StandardError => e
                  results_mutex.synchronize do
                    errors[index] = e

                    if config.iteration_fail_fast?
                      aborted = true
                      pool.abort! if pool.respond_to?(:abort!)
                    end
                  end

                  raise unless config.continue_on_error? || config.iteration_fail_fast?
                end
              end
            end

            pool.wait_for_completion
            pool.shutdown

            # Remove nil entries from results (unfilled due to abort)
            item_results.compact!

            Workflow::IterationResult.new(
              step_name: config.name,
              item_results: item_results,
              errors: errors
            )
          end

          def execute_for_item(item, index, &block)
            if config.custom_block?
              execute_block_for_item(item, index, &block)
            elsif config.workflow?
              execute_workflow_for_item(item, index, &block)
            else
              execute_agent_for_item(item, index, &block)
            end
          end

          def execute_block_for_item(item, index, &block)
            context = IterationContext.new(workflow, config, previous_result, item, index)
            result = context.instance_exec(item, &config.block)

            # If block returns a Result, use it; otherwise wrap it
            if result.is_a?(Workflow::Result) || result.is_a?(RubyLLM::Agents::Result)
              result
            else
              SimpleResult.new(content: result, success: true)
            end
          end

          def execute_agent_for_item(item, index, &block)
            # Build input for this item
            step_input = build_item_input(item, index)
            workflow.send(:execute_agent, config.agent, step_input, step_name: config.name, &block)
          end

          def execute_workflow_for_item(item, index, &block)
            step_input = build_item_input(item, index)

            # Build execution metadata
            parent_metadata = {
              parent_execution_id: workflow.execution_id,
              root_execution_id: workflow.send(:root_execution_id),
              workflow_id: workflow.workflow_id,
              workflow_type: workflow.class.name,
              workflow_step: config.name.to_s,
              iteration_index: index,
              recursion_depth: (workflow.instance_variable_get(:@recursion_depth) || 0) + (config.agent == workflow.class ? 1 : 0)
            }.compact

            merged_input = step_input.merge(
              execution_metadata: parent_metadata.merge(step_input[:execution_metadata] || {})
            )

            result = config.agent.call(**merged_input, &block)

            # Track accumulated cost
            if result.respond_to?(:total_cost) && result.total_cost
              workflow.instance_variable_set(
                :@accumulated_cost,
                (workflow.instance_variable_get(:@accumulated_cost) || 0.0) + result.total_cost
              )
              workflow.send(:check_cost_threshold!)
            end

            Workflow::SubWorkflowResult.new(
              content: result.content,
              sub_workflow_result: result,
              workflow_type: config.agent.name,
              step_name: config.name
            )
          end

          def build_item_input(item, index)
            # If there's an input mapper, use it with item context
            if config.input_mapper
              # Create a temporary context that has access to item and index
              context = IterationInputContext.new(workflow, item, index)
              context.instance_exec(&config.input_mapper)
            else
              # Default: wrap item in a hash
              item.is_a?(Hash) ? item : { item: item, index: index }
            end
          end

          def create_executor_pool(size)
            config_obj = RubyLLM::Agents.configuration

            if config_obj.respond_to?(:async_context?) && config_obj.async_context?
              AsyncExecutor.new(max_concurrent: size)
            else
              ThreadPool.new(size: size)
            end
          end
        end

        # Context for executing iteration block steps
        #
        # Extends BlockContext with item and index access.
        #
        # @api private
        class IterationContext < BlockContext
          attr_reader :item, :index

          def initialize(workflow, config, previous_result, item, index)
            super(workflow, config, previous_result)
            @item = item
            @index = index
          end

          # Access the current item being processed
          def current_item
            @item
          end

          # Access the current iteration index
          def current_index
            @index
          end
        end

        # Context for building iteration input
        #
        # Provides access to item and index for input mappers.
        #
        # @api private
        class IterationInputContext
          def initialize(workflow, item, index)
            @workflow = workflow
            @item = item
            @index = index
          end

          attr_reader :item, :index

          # Access workflow input
          def input
            @workflow.input
          end

          # Delegate to workflow for step results access
          def method_missing(name, *args, &block)
            if @workflow.respond_to?(name, true)
              @workflow.send(name, *args, &block)
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            @workflow.respond_to?(name, include_private) || super
          end
        end

        # Error raised when iteration source resolution fails
        class IterationSourceError < StandardError; end
      end
    end
  end
end
