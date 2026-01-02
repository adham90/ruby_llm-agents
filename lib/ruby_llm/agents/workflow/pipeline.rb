# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Sequential workflow execution pattern
      #
      # Executes agents in order, passing each step's output as input to the next.
      # Supports conditional step skipping, error handling, and input transformation.
      #
      # @example Basic pipeline
      #   class ContentPipeline < RubyLLM::Agents::Workflow::Pipeline
      #     version "1.0"
      #
      #     step :extract,  agent: ExtractorAgent
      #     step :validate, agent: ValidatorAgent
      #     step :format,   agent: FormatterAgent
      #   end
      #
      #   result = ContentPipeline.call(text: "raw input")
      #   result.steps[:extract].content  # First step output
      #   result.content                  # Final output
      #
      # @example With conditional skipping
      #   class ConditionalPipeline < RubyLLM::Agents::Workflow::Pipeline
      #     step :check,    agent: CheckerAgent
      #     step :process,  agent: ProcessorAgent, skip_on: ->(ctx) { ctx[:check].content[:skip] }
      #     step :finalize, agent: FinalizerAgent
      #   end
      #
      # @example With input transformation
      #   class TransformPipeline < RubyLLM::Agents::Workflow::Pipeline
      #     step :analyze, agent: AnalyzerAgent
      #     step :enrich,  agent: EnricherAgent
      #
      #     def before_enrich(context)
      #       { data: context[:analyze].content, extra_field: "value" }
      #     end
      #   end
      #
      # @api public
      class Pipeline < Workflow
        class << self
          # Returns the defined steps
          #
          # @return [Hash<Symbol, Hash>] Step configurations
          def steps
            @steps ||= {}
          end

          # Inherits steps from parent class
          def inherited(subclass)
            super
            subclass.instance_variable_set(:@steps, steps.dup)
          end

          # Defines a pipeline step
          #
          # @param name [Symbol] Step identifier
          # @param agent [Class] The agent class to execute
          # @param skip_on [Proc, nil] Lambda to determine if step should be skipped
          # @param continue_on_error [Boolean] Whether to continue if step fails
          # @param optional [Boolean] Mark step as optional (alias for continue_on_error)
          # @return [void]
          #
          # @example Basic step
          #   step :process, agent: ProcessorAgent
          #
          # @example With skip condition
          #   step :validate, agent: ValidatorAgent, skip_on: ->(ctx) { ctx[:input][:skip_validation] }
          #
          # @example Optional step (won't fail pipeline)
          #   step :enrich, agent: EnricherAgent, optional: true
          def step(name, agent:, skip_on: nil, continue_on_error: false, optional: false)
            steps[name] = {
              agent: agent,
              skip_on: skip_on,
              continue_on_error: continue_on_error || optional,
              index: steps.size
            }
          end
        end

        # Executes the pipeline
        #
        # Runs each step sequentially, passing output to the next step.
        # Tracks all step results and builds aggregate metrics.
        #
        # @yield [chunk] Yields chunks when streaming (passed to individual agents)
        # @return [WorkflowResult] The pipeline result
        def call(&block)
          instrument_workflow do
            execute_pipeline(&block)
          end
        end

        private

        # Executes the pipeline steps
        #
        # @return [WorkflowResult] The pipeline result
        def execute_pipeline(&block)
          context = { input: options }
          step_results = {}
          errors = {}
          last_successful_result = nil
          status = "success"

          self.class.steps.each do |name, config|
            # Check skip condition
            if should_skip_step?(config, context)
              step_results[name] = SkippedResult.new(name, reason: "skip_on condition met")
              next
            end

            begin
              # Build input for this step
              step_input = before_step(name, context)

              # Execute the step
              result = execute_agent(
                config[:agent],
                step_input,
                step_name: name,
                &block
              )

              step_results[name] = result
              context[name] = result
              last_successful_result = result

              # Check if step failed
              if result.respond_to?(:error?) && result.error?
                errors[name] = StandardError.new(result.error_message || "Step failed")

                unless config[:continue_on_error]
                  status = "error"
                  break
                end

                status = "partial" if status == "success"
              end
            rescue StandardError => e
              # Handle step execution errors
              errors[name] = e
              step_results[name] = build_error_result(name, e)
              context[name] = step_results[name]

              # Call error handler hook
              action = on_step_failure(name, e, context)

              case action
              when :skip
                status = "partial" if status == "success"
                next
              when :abort
                status = "error"
                break
              when Result, Workflow::Result
                # Use the returned result as the step result
                step_results[name] = action
                context[name] = action
                last_successful_result = action
                status = "partial" if status == "success"
              else
                unless config[:continue_on_error]
                  status = "error"
                  break
                end
                status = "partial" if status == "success"
              end
            end
          end

          # Build final content from last successful step
          final_content = extract_final_content(last_successful_result, context)

          build_pipeline_result(
            content: final_content,
            steps: step_results,
            errors: errors,
            status: status
          )
        end

        # Checks if a step should be skipped
        #
        # @param config [Hash] Step configuration
        # @param context [Hash] Current workflow context
        # @return [Boolean] true if step should be skipped
        def should_skip_step?(config, context)
          return false unless config[:skip_on]

          config[:skip_on].call(context)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::Pipeline] skip_on evaluation failed: #{e.message}")
          false
        end

        # Hook for handling step failures
        #
        # Override in subclass to customize error handling.
        #
        # @param step_name [Symbol] The failed step
        # @param error [Exception] The error
        # @param context [Hash] Current workflow context
        # @return [Symbol, Result] :skip to continue, :abort to stop, or a fallback Result
        def on_step_failure(step_name, error, context)
          # Default: check if method exists for specific step
          method_name = :"on_#{step_name}_failure"
          if respond_to?(method_name, true)
            send(method_name, error, context)
          else
            :abort
          end
        end

        # Extracts the final content from the pipeline
        #
        # @param last_result [Result, nil] The last successful result
        # @param context [Hash] The workflow context
        # @return [Object] The final content
        def extract_final_content(last_result, context)
          if last_result.respond_to?(:content)
            last_result.content
          elsif context.keys.size > 1
            # Return the last non-input context entry
            last_key = context.keys.reject { |k| k == :input }.last
            context[last_key]&.content
          else
            nil
          end
        end

        # Builds an error result for a failed step
        #
        # @param step_name [Symbol] The step name
        # @param error [Exception] The error
        # @return [Hash] Error result
        def build_error_result(step_name, error)
          # Return a simple hash that looks like a result
          OpenStruct.new(
            content: nil,
            success?: false,
            error?: true,
            error_class: error.class.name,
            error_message: error.message,
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            cached_tokens: 0,
            input_cost: 0.0,
            output_cost: 0.0,
            total_cost: 0.0,
            to_h: {
              error: true,
              step_name: step_name,
              error_class: error.class.name,
              error_message: error.message
            }
          )
        end

        # Builds the final pipeline result
        #
        # @param content [Object] Final content
        # @param steps [Hash] Step results
        # @param errors [Hash] Step errors
        # @param status [String] Final status
        # @return [WorkflowResult] The pipeline result
        def build_pipeline_result(content:, steps:, errors:, status:)
          Workflow::Result.new(
            content: content,
            workflow_type: self.class.name,
            workflow_id: workflow_id,
            steps: steps,
            errors: errors,
            status: status,
            started_at: @workflow_started_at,
            completed_at: Time.current,
            duration_ms: (((Time.current - @workflow_started_at) * 1000).round if @workflow_started_at)
          )
        end
      end
    end
  end
end
