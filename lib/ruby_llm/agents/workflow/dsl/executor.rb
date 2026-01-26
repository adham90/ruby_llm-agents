# frozen_string_literal: true

require_relative "../wait_result"
require_relative "../throttle_manager"
require_relative "../approval"
require_relative "../approval_store"
require_relative "../notifiers"

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Main executor for workflows using the refined DSL
        #
        # Handles the execution of steps in order, including sequential
        # steps and parallel groups, with full support for routing,
        # conditions, retries, and error handling.
        #
        # @api private
        class Executor
          attr_reader :workflow, :results, :errors, :status

          # @param workflow [Workflow] The workflow instance
          def initialize(workflow)
            @workflow = workflow
            @results = {}
            @errors = {}
            @status = "success"
            @halted = false
            @skip_next_step = false
            @throttle_manager = ThrottleManager.new
            @wait_results = {}
          end

          # Executes all workflow steps
          #
          # @yield [chunk] Streaming callback
          # @return [Workflow::Result] The workflow result
          def execute(&block)
            @workflow_started_at = Time.current

            # Validate input schema before execution
            validate_input!

            run_hooks(:before_workflow)

            catch(:halt_workflow) do
              execute_steps(&block)
            end

            run_hooks(:after_workflow)

            build_result
          rescue InputSchema::ValidationError
            # Re-raise validation errors - these should not be caught
            raise
          rescue StandardError => e
            @status = "error"
            @errors[:workflow] = e
            build_result(error: e)
          end

          private

          # Validates input against the schema if defined
          #
          # This is called at the start of execution to fail fast on invalid input.
          # Also populates the validated_input for later access.
          #
          # @raise [InputSchema::ValidationError] If input validation fails
          def validate_input!
            schema = workflow.class.input_schema
            return unless schema

            # This will raise ValidationError if input is invalid
            validated = schema.validate!(workflow.options)
            workflow.instance_variable_set(:@validated_input, OpenStruct.new(validated))
          end

          def execute_steps(&block)
            previous_result = nil

            workflow.class.step_order.each do |item|
              break if @halted

              # Handle skip_next from wait timeout
              if @skip_next_step
                @skip_next_step = false
                next if item.is_a?(Symbol)
              end

              case item
              when Symbol
                previous_result = execute_single_step(item, previous_result, &block)
              when ParallelGroup
                previous_result = execute_parallel_group(item, &block)
              when WaitConfig
                wait_result = execute_wait_step(item)
                @wait_results[item.object_id] = wait_result
                handle_wait_result(wait_result)
              end
            end
          end

          def execute_single_step(step_name, previous_result, &block)
            config = workflow.class.step_configs[step_name]
            return previous_result unless config

            # Apply throttling if configured
            apply_throttle(step_name, config)

            run_hooks(:before_step, step_name, workflow.step_results)
            run_hooks(:on_step_start, step_name, config.resolve_input(workflow, previous_result))

            started_at = Time.current

            result = catch(:skip_step) do
              executor = StepExecutor.new(workflow, config)
              executor.execute(previous_result, &block)
            end

            # Handle skip_step catch
            if result.is_a?(Hash) && result[:skipped]
              result = if result[:default]
                         SimpleResult.new(content: result[:default], success: true)
                       else
                         SkippedResult.new(step_name, reason: result[:reason])
                       end
            end

            duration_ms = ((Time.current - started_at) * 1000).round

            @results[step_name] = result
            workflow.instance_variable_get(:@step_results)[step_name] = result

            # Update status based on result
            update_status_from_result(step_name, result, config)

            run_hooks(:after_step, step_name, result, duration_ms)
            run_hooks(:on_step_complete, step_name, result, duration_ms)

            # Return nil on error for critical steps to prevent passing bad data
            if result.respond_to?(:error?) && result.error? && config.critical?
              @halted = true
              return nil
            end

            result
          rescue StandardError => e
            handle_step_error(step_name, e, config)
          end

          def execute_parallel_group(group, &block)
            results_mutex = Mutex.new
            group_results = {}
            group_errors = {}

            # Determine pool size
            pool_size = group.concurrency || group.step_names.size
            pool = create_executor_pool(pool_size)

            # Get the last result before this parallel group for input
            last_sequential_step = workflow.class.step_order
                                           .take_while { |item| item != group }
                                           .select { |item| item.is_a?(Symbol) }
                                           .last
            previous_result = last_sequential_step ? @results[last_sequential_step] : nil

            group.step_names.each do |step_name|
              pool.post do
                Thread.current.name = "parallel-#{step_name}"

                begin
                  config = workflow.class.step_configs[step_name]
                  next unless config

                  executor = StepExecutor.new(workflow, config)
                  result = executor.execute(previous_result, &block)

                  results_mutex.synchronize do
                    group_results[step_name] = result
                    @results[step_name] = result
                    workflow.instance_variable_get(:@step_results)[step_name] = result

                    # Fail-fast handling
                    if group.fail_fast? && result.respond_to?(:error?) && result.error? && config.critical?
                      pool.abort! if pool.respond_to?(:abort!)
                    end
                  end
                rescue StandardError => e
                  results_mutex.synchronize do
                    group_errors[step_name] = e
                    @errors[step_name] = e

                    if group.fail_fast?
                      pool.abort! if pool.respond_to?(:abort!)
                    end
                  end
                end
              end
            end

            pool.wait_for_completion
            pool.shutdown

            # Update overall status
            update_parallel_status(group, group_results, group_errors)

            # Return combined results as a hash-like object
            ParallelGroupResult.new(group.name, group_results)
          end

          def create_executor_pool(size)
            config = RubyLLM::Agents.configuration

            if config.respond_to?(:async_context?) && config.async_context?
              AsyncExecutor.new(max_concurrent: size)
            else
              ThreadPool.new(size: size)
            end
          end

          # Executes a wait step
          #
          # @param wait_config [WaitConfig] The wait configuration
          # @return [WaitResult] The wait result
          def execute_wait_step(wait_config)
            executor = WaitExecutor.new(wait_config, workflow)
            executor.execute
          rescue StandardError => e
            # Return a failed result instead of crashing
            Workflow::WaitResult.timeout(
              wait_config.type,
              0,
              :fail,
              error: "#{e.class}: #{e.message}"
            )
          end

          # Handles the result of a wait step
          #
          # @param wait_result [WaitResult] The wait result
          # @return [void]
          def handle_wait_result(wait_result)
            if wait_result.timeout? && wait_result.timeout_action == :fail
              @status = "error"
              @halted = true
              @errors[:wait] = "Wait timed out: #{wait_result.type}"
            elsif wait_result.rejected?
              @status = "error"
              @halted = true
              @errors[:wait] = "Approval rejected: #{wait_result.rejection_reason}"
            elsif wait_result.should_skip_next?
              @skip_next_step = true
            end
          end

          # Applies throttling for a step if configured
          #
          # @param step_name [Symbol] The step name
          # @param config [StepConfig] The step configuration
          # @return [void]
          def apply_throttle(step_name, config)
            return unless config.throttled?

            if config.throttle
              @throttle_manager.throttle("step:#{step_name}", config.throttle)
            elsif config.rate_limit
              @throttle_manager.rate_limit(
                "step:#{step_name}",
                calls: config.rate_limit[:calls],
                per: config.rate_limit[:per]
              )
            end
          end

          def handle_step_error(step_name, error, config)
            @errors[step_name] = error

            run_hooks(:on_step_error, step_name, error)
            run_hooks(:on_step_failure, step_name, error, workflow.step_results)

            # Build error result
            error_result = Pipeline::ErrorResult.new(
              step_name: step_name,
              error_class: error.class.name,
              error_message: error.message
            )

            @results[step_name] = error_result
            workflow.instance_variable_get(:@step_results)[step_name] = error_result

            if config.optional?
              @status = "partial" if @status == "success"
              config.default_value ? SimpleResult.new(content: config.default_value, success: true) : nil
            else
              @status = "error"
              @halted = true
              nil
            end
          end

          def update_status_from_result(step_name, result, config)
            return unless result.respond_to?(:error?) && result.error?

            if config.optional?
              @status = "partial" if @status == "success"
            else
              @status = "error"
            end
          end

          def update_parallel_status(group, group_results, group_errors)
            # Check for errors
            group.step_names.each do |step_name|
              config = workflow.class.step_configs[step_name]

              if group_errors[step_name]
                if config&.optional?
                  @status = "partial" if @status == "success"
                else
                  @status = "error"
                end
              elsif group_results[step_name]&.respond_to?(:error?) && group_results[step_name].error?
                if config&.optional?
                  @status = "partial" if @status == "success"
                else
                  @status = "error"
                end
              end
            end
          end

          def run_hooks(hook_name, *args)
            workflow.send(:run_hooks, hook_name, *args)
          end

          def build_result(error: nil)
            # Get final content from last successful step
            final_content = extract_final_content

            # Validate output if schema defined
            if workflow.class.output_schema && final_content
              begin
                workflow.class.output_schema.validate!(final_content)
              rescue InputSchema::ValidationError => e
                @errors[:output_validation] = e
                @status = "error" if @status == "success"
              end
            end

            Workflow::Result.new(
              content: final_content,
              workflow_type: workflow.class.name,
              workflow_id: workflow.workflow_id,
              steps: @results,
              errors: @errors,
              status: @status,
              error_class: error&.class&.name,
              error_message: error&.message,
              started_at: @workflow_started_at,
              completed_at: Time.current,
              duration_ms: (((Time.current - @workflow_started_at) * 1000).round if @workflow_started_at)
            )
          end

          def extract_final_content
            # Find the last successful result
            workflow.class.step_order.reverse.each do |item|
              case item
              when Symbol
                result = @results[item]
                next if result.nil?
                next if result.respond_to?(:skipped?) && result.skipped?
                next if result.respond_to?(:error?) && result.error?
                return result.content if result.respond_to?(:content)
              when ParallelGroup
                # For parallel groups, return the combined content
                group_content = {}
                item.step_names.each do |step_name|
                  result = @results[step_name]
                  next if result.nil? || (result.respond_to?(:error?) && result.error?)
                  group_content[step_name] = result.respond_to?(:content) ? result.content : result
                end
                return group_content if group_content.any?
              when WaitConfig
                # Wait steps don't contribute content, skip them
                next
              end
            end

            nil
          end
        end

        # Result wrapper for parallel group execution
        #
        # Provides access to individual step results within a parallel group.
        #
        # @api private
        class ParallelGroupResult
          attr_reader :name, :results

          def initialize(name, results)
            @name = name
            @results = results
          end

          def content
            @results.transform_values { |r| r&.content }
          end

          def [](key)
            @results[key]
          end

          def success?
            @results.values.all? { |r| r.nil? || !r.respond_to?(:error?) || !r.error? }
          end

          def error?
            !success?
          end

          def to_h
            content
          end

          def method_missing(name, *args, &block)
            if @results.key?(name)
              @results[name]
            elsif content.key?(name)
              content[name]
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            @results.key?(name) || content.key?(name) || super
          end

          # Token/cost aggregation
          def input_tokens
            @results.values.compact.sum { |r| r.respond_to?(:input_tokens) ? r.input_tokens : 0 }
          end

          def output_tokens
            @results.values.compact.sum { |r| r.respond_to?(:output_tokens) ? r.output_tokens : 0 }
          end

          def total_tokens
            input_tokens + output_tokens
          end

          def cached_tokens
            @results.values.compact.sum { |r| r.respond_to?(:cached_tokens) ? r.cached_tokens : 0 }
          end

          def total_cost
            @results.values.compact.sum { |r| r.respond_to?(:total_cost) ? r.total_cost : 0.0 }
          end
        end
      end
    end
  end
end
