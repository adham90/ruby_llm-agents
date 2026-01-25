# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Executes individual workflow steps with retry, timeout, and error handling
        #
        # Responsible for:
        # - Evaluating step conditions
        # - Building step input
        # - Executing agents with timeout
        # - Handling retries with backoff
        # - Executing fallback agents
        # - Invoking error handlers
        #
        # @api private
        class StepExecutor
          attr_reader :workflow, :config

          # @param workflow [Workflow] The workflow instance
          # @param config [StepConfig] The step configuration
          def initialize(workflow, config)
            @workflow = workflow
            @config = config
          end

          # Executes the step
          #
          # @param previous_result [Result, nil] Previous step result
          # @yield [chunk] Streaming callback
          # @return [Result, SkippedResult] Step result
          def execute(previous_result = nil, &block)
            # Check conditions
            unless config.should_execute?(workflow)
              return create_skipped_result("condition not met")
            end

            # Execute with timeout wrapper if configured
            if config.timeout
              execute_with_timeout(previous_result, &block)
            else
              execute_step(previous_result, &block)
            end
          end

          private

          def execute_with_timeout(previous_result, &block)
            Timeout.timeout(config.timeout) do
              execute_step(previous_result, &block)
            end
          rescue Timeout::Error => e
            handle_step_error(e, previous_result, &block)
          end

          def execute_step(previous_result, &block)
            execute_with_retry(previous_result, &block)
          rescue StandardError => e
            handle_step_error(e, previous_result, &block)
          end

          def execute_with_retry(previous_result, &block)
            retry_config = config.retry_config
            max_attempts = [retry_config[:max], 0].max + 1
            attempts = 0

            begin
              attempts += 1
              execute_agent_or_block(previous_result, &block)
            rescue *retry_config[:on] => e
              if attempts < max_attempts
                sleep_with_backoff(retry_config, attempts)
                retry
              else
                raise
              end
            end
          end

          def execute_agent_or_block(previous_result, &block)
            if config.routing?
              execute_routed_step(previous_result, &block)
            elsif config.iteration?
              execute_iteration_step(previous_result, &block)
            elsif config.workflow?
              execute_workflow_step(previous_result, &block)
            elsif config.custom_block?
              execute_block_step(previous_result)
            else
              execute_agent_step(previous_result, &block)
            end
          end

          def execute_routed_step(previous_result, &block)
            route = config.resolve_route(workflow)
            agent_class = route[:agent]
            route_options = route[:options] || {}

            # Build input - use route-specific input if provided
            step_input = if route_options[:input]
                           workflow.instance_exec(&route_options[:input])
                         else
                           config.resolve_input(workflow, previous_result)
                         end

            # Execute the routed agent
            workflow.send(:execute_agent, agent_class, step_input, step_name: config.name, &block)
          end

          def execute_block_step(previous_result)
            # Create a block context that provides helper methods
            context = BlockContext.new(workflow, config, previous_result)
            result = context.instance_exec(&config.block)

            # If block returns a Result, use it; otherwise wrap it
            if result.is_a?(Result) || result.is_a?(Workflow::Result)
              result
            else
              SimpleResult.new(content: result, success: true)
            end
          end

          def execute_agent_step(previous_result, &block)
            step_input = config.resolve_input(workflow, previous_result)
            workflow.send(:execute_agent, config.agent, step_input, step_name: config.name, &block)
          end

          def execute_workflow_step(previous_result, &block)
            step_input = config.resolve_input(workflow, previous_result)

            # Build execution metadata for the sub-workflow
            parent_metadata = {
              parent_execution_id: workflow.execution_id,
              root_execution_id: workflow.send(:root_execution_id),
              workflow_id: workflow.workflow_id,
              workflow_type: workflow.class.name,
              workflow_step: config.name.to_s,
              remaining_timeout: calculate_remaining_timeout,
              remaining_cost_budget: calculate_remaining_cost_budget,
              recursion_depth: (workflow.instance_variable_get(:@recursion_depth) || 0) + (self_referential_workflow? ? 1 : 0)
            }.compact

            # Merge execution metadata into input
            merged_input = step_input.merge(
              execution_metadata: parent_metadata.merge(step_input[:execution_metadata] || {})
            )

            # Execute the sub-workflow
            result = config.agent.call(**merged_input, &block)

            # Track accumulated cost
            if result.respond_to?(:total_cost) && result.total_cost
              workflow.instance_variable_set(
                :@accumulated_cost,
                (workflow.instance_variable_get(:@accumulated_cost) || 0.0) + result.total_cost
              )
              workflow.send(:check_cost_threshold!)
            end

            # Wrap in SubWorkflowResult for proper tracking
            SubWorkflowResult.new(
              content: result.content,
              sub_workflow_result: result,
              workflow_type: config.agent.name,
              step_name: config.name
            )
          end

          def execute_iteration_step(previous_result, &block)
            executor = IterationExecutor.new(workflow, config, previous_result)
            executor.execute(&block)
          end

          def calculate_remaining_timeout
            workflow_timeout = workflow.class.timeout
            return nil unless workflow_timeout

            started_at = workflow.instance_variable_get(:@workflow_started_at)
            return workflow_timeout unless started_at

            elapsed = Time.current - started_at
            remaining = workflow_timeout - elapsed
            remaining > 0 ? remaining.to_i : 1
          end

          def calculate_remaining_cost_budget
            max_cost = workflow.class.max_cost
            return nil unless max_cost

            accumulated = workflow.instance_variable_get(:@accumulated_cost) || 0.0
            remaining = max_cost - accumulated
            remaining > 0 ? remaining : 0.0
          end

          def self_referential_workflow?
            config.agent == workflow.class
          end

          def handle_step_error(error, previous_result, &block)
            # Try fallbacks first
            if config.fallbacks.any?
              fallback_result = try_fallbacks(previous_result, &block)
              return fallback_result if fallback_result
            end

            # Try error handler
            if config.error_handler
              handler_result = invoke_error_handler(error)
              return handler_result if handler_result.is_a?(Result) || handler_result.is_a?(Workflow::Result)
            end

            # If optional, return default or error result
            if config.optional?
              if config.default_value
                return SimpleResult.new(content: config.default_value, success: true)
              else
                # Return an error result so status is set to "partial"
                return Pipeline::ErrorResult.new(
                  step_name: config.name,
                  error_class: error.class.name,
                  error_message: error.message
                )
              end
            end

            # Re-raise for critical steps
            raise
          end

          def try_fallbacks(previous_result, &block)
            step_input = config.resolve_input(workflow, previous_result)

            config.fallbacks.each do |fallback_agent|
              begin
                return workflow.send(:execute_agent, fallback_agent, step_input, step_name: config.name, &block)
              rescue StandardError
                # Continue to next fallback
                next
              end
            end

            nil
          end

          def invoke_error_handler(error)
            handler = config.error_handler

            case handler
            when Symbol
              workflow.send(handler, error)
            when Proc
              workflow.instance_exec(error, &handler)
            end
          end

          def sleep_with_backoff(retry_config, attempt)
            base_delay = retry_config[:delay] || 1

            delay = case retry_config[:backoff]
                    when :exponential
                      base_delay * (2**(attempt - 1))
                    when :linear
                      base_delay * attempt
                    else
                      base_delay
                    end

            sleep(delay)
          end

          def create_skipped_result(reason)
            SkippedResult.new(config.name, reason: reason)
          end
        end

        # Context for executing custom block steps
        #
        # Provides helper methods available inside step blocks.
        #
        # @api private
        class BlockContext
          def initialize(workflow, config, previous_result)
            @workflow = workflow
            @config = config
            @previous_result = previous_result
          end

          # Executes an agent within the block
          #
          # @param agent_class [Class] Agent to execute
          # @param input [Hash] Input for the agent
          # @return [Result] Agent result
          def agent(agent_class, **input)
            @workflow.send(:execute_agent, agent_class, input, step_name: @config.name)
          end

          # Skips the current step
          #
          # @param reason [String] Skip reason
          # @param default [Object] Default value to use
          # @raise [StepSkipped]
          def skip!(reason = nil, default: nil)
            throw :skip_step, { skipped: true, reason: reason, default: default }
          end

          # Halts the workflow successfully
          #
          # @param result [Hash] Final result
          # @raise [WorkflowHalted]
          def halt!(result = {})
            throw :halt_workflow, { halted: true, result: result }
          end

          # Fails the current step
          #
          # @param message [String] Error message
          # @raise [StepFailedError]
          def fail!(message)
            raise StepFailedError, message
          end

          # Triggers a retry of the current step
          #
          # @param reason [String] Retry reason
          # @raise [RetryStep]
          def retry!(reason = nil)
            raise RetryStep, reason
          end

          # Access workflow input
          def input
            @workflow.input
          end

          # Access previous step result
          def previous
            @previous_result
          end

          # Delegate missing methods to workflow (for accessing step results)
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

        # Simple result wrapper for block steps
        #
        # @api private
        class SimpleResult
          attr_reader :content

          def initialize(content:, success: true)
            @content = content
            @success = success
          end

          def success?
            @success
          end

          def error?
            !@success
          end

          def input_tokens
            0
          end

          def output_tokens
            0
          end

          def total_tokens
            0
          end

          def cached_tokens
            0
          end

          def input_cost
            0.0
          end

          def output_cost
            0.0
          end

          def total_cost
            0.0
          end

          def to_h
            { content: content, success: success? }
          end
        end

        # Error raised when a step explicitly fails
        class StepFailedError < StandardError; end

        # Error to trigger step retry
        class RetryStep < StandardError; end
      end
    end
  end
end
