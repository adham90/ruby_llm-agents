# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Concurrent workflow execution pattern
      #
      # Executes multiple agents simultaneously and aggregates their results.
      # Supports fail-fast behavior, optional branches, and custom aggregation.
      #
      # @example Basic parallel execution
      #   class ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
      #     version "1.0"
      #
      #     branch :sentiment,  agent: SentimentAgent
      #     branch :summary,    agent: SummaryAgent
      #     branch :categories, agent: CategoryAgent
      #   end
      #
      #   result = ReviewAnalyzer.call(text: "Great product!")
      #   result.branches[:sentiment].content  # "positive"
      #   result.branches[:summary].content    # "User liked the product"
      #
      # @example With optional branches and custom aggregation
      #   class FullAnalyzer < RubyLLM::Agents::Workflow::Parallel
      #     branch :sentiment, agent: SentimentAgent
      #     branch :toxicity,  agent: ToxicityAgent, optional: true
      #
      #     def aggregate(results)
      #       {
      #         sentiment: results[:sentiment]&.content,
      #         toxicity: results[:toxicity]&.content,
      #         safe: results[:toxicity]&.content != "toxic"
      #       }
      #     end
      #   end
      #
      # @example With fail-fast enabled
      #   class CriticalAnalyzer < RubyLLM::Agents::Workflow::Parallel
      #     fail_fast true  # Stop all branches on first failure
      #
      #     branch :auth,     agent: AuthValidator
      #     branch :sanity,   agent: SanityChecker
      #   end
      #
      # @api public
      class Parallel < Workflow
        class << self
          # Returns the defined branches
          #
          # @return [Hash<Symbol, Hash>] Branch configurations
          def branches
            @branches ||= {}
          end

          # Inherits branches from parent class
          def inherited(subclass)
            super
            subclass.instance_variable_set(:@branches, branches.dup)
            subclass.instance_variable_set(:@fail_fast, @fail_fast)
            subclass.instance_variable_set(:@concurrency, @concurrency)
          end

          # Defines a parallel branch
          #
          # @param name [Symbol] Branch identifier
          # @param agent [Class] The agent class to execute
          # @param optional [Boolean] If true, branch failure won't fail the workflow
          # @param input [Proc, nil] Lambda to transform input for this branch
          # @return [void]
          #
          # @example Basic branch
          #   branch :analyze, agent: AnalyzerAgent
          #
          # @example Optional branch
          #   branch :enrich, agent: EnricherAgent, optional: true
          #
          # @example With custom input
          #   branch :summarize, agent: SummaryAgent, input: ->(opts) { { text: opts[:content] } }
          def branch(name, agent:, optional: false, input: nil)
            branches[name] = {
              agent: agent,
              optional: optional,
              input: input
            }
          end

          # Sets or returns fail-fast behavior
          #
          # When true, cancels remaining branches when any required branch fails.
          #
          # @param value [Boolean, nil] Whether to fail fast
          # @return [Boolean] Current fail-fast setting
          def fail_fast(value = nil)
            if value.nil?
              @fail_fast || false
            else
              @fail_fast = value
            end
          end

          # Alias for checking fail_fast setting
          def fail_fast?
            fail_fast
          end

          # Sets or returns concurrency limit
          #
          # @param value [Integer, nil] Max concurrent branches (nil = unlimited)
          # @return [Integer, nil] Current concurrency limit
          def concurrency(value = nil)
            if value.nil?
              @concurrency
            else
              @concurrency = value
            end
          end
        end

        # Executes the parallel workflow
        #
        # Runs all branches concurrently and aggregates results.
        #
        # @yield [chunk] Yields chunks when streaming (not typically used in parallel)
        # @return [WorkflowResult] The parallel result
        def call(&block)
          instrument_workflow do
            execute_parallel(&block)
          end
        end

        # Aggregates branch results into final content
        #
        # Override this method to customize how results are combined.
        #
        # @param results [Hash<Symbol, Result>] Branch results
        # @return [Object] Aggregated content
        def aggregate(results)
          # Default: return hash of branch contents
          results.transform_values { |r| r&.content }
        end

        private

        # Executes all branches in parallel
        #
        # @return [WorkflowResult] The parallel result
        def execute_parallel(&block)
          results = {}
          errors = {}
          mutex = Mutex.new
          should_abort = false

          # Create thread pool based on concurrency setting
          threads = self.class.branches.map do |name, config|
            Thread.new do
              Thread.current.name = "parallel-#{name}"
              Thread.current[:branch_name] = name

              begin
                # Check if we should abort early
                if self.class.fail_fast? && should_abort
                  mutex.synchronize { results[name] = nil }
                  next
                end

                # Build input for this branch
                branch_input = build_branch_input(name, config)

                # Execute the branch
                result = execute_agent(
                  config[:agent],
                  branch_input,
                  step_name: name,
                  &block
                )

                mutex.synchronize do
                  results[name] = result

                  # Check for failure
                  if result.respond_to?(:error?) && result.error? && !config[:optional]
                    should_abort = true if self.class.fail_fast?
                  end
                end
              rescue StandardError => e
                mutex.synchronize do
                  errors[name] = e
                  results[name] = nil
                  should_abort = true if self.class.fail_fast? && !config[:optional]
                end
              end
            end
          end

          # Apply concurrency limit if set
          if self.class.concurrency
            threads.each_slice(self.class.concurrency) do |thread_batch|
              thread_batch.each(&:join)
            end
          else
            threads.each(&:join)
          end

          # Determine overall status
          status = determine_parallel_status(results, errors)

          # Aggregate results
          final_content = begin
            aggregate(results)
          rescue StandardError => e
            errors[:aggregate] = e
            results.transform_values { |r| r&.content }
          end

          build_parallel_result(
            content: final_content,
            branches: results,
            errors: errors,
            status: status
          )
        end

        # Builds input for a specific branch
        #
        # @param name [Symbol] Branch name
        # @param config [Hash] Branch configuration
        # @return [Hash] Input for the branch
        def build_branch_input(name, config)
          if config[:input]
            config[:input].call(options)
          elsif respond_to?(:"before_#{name}", true)
            send(:"before_#{name}", options)
          else
            options.dup
          end
        end

        # Determines the overall parallel status
        #
        # @param results [Hash] Branch results
        # @param errors [Hash] Branch errors
        # @return [String] Status: "success", "partial", or "error"
        def determine_parallel_status(results, errors)
          required_branches = self.class.branches.reject { |_, c| c[:optional] }.keys
          failed_required = required_branches.select do |name|
            errors[name] || (results[name].respond_to?(:error?) && results[name].error?)
          end

          if failed_required.any?
            "error"
          elsif errors.any?
            "partial"
          else
            "success"
          end
        end

        # Builds the final parallel result
        #
        # @param content [Object] Aggregated content
        # @param branches [Hash] Branch results
        # @param errors [Hash] Branch errors
        # @param status [String] Final status
        # @return [WorkflowResult] The parallel result
        def build_parallel_result(content:, branches:, errors:, status:)
          Workflow::Result.new(
            content: content,
            workflow_type: self.class.name,
            workflow_id: workflow_id,
            branches: branches,
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
