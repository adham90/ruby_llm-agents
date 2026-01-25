# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Result wrapper for workflow executions with aggregate metrics
      #
      # Extends the base Result class with workflow-specific data including
      # step results, branch results, routing information, and aggregated
      # token/cost metrics across all child executions.
      #
      # @example Pipeline result
      #   result = ContentPipeline.call(text: "input")
      #   result.content              # Final output
      #   result.steps[:extract]      # Individual step result
      #   result.total_cost          # Sum of all steps
      #
      # @example Parallel result
      #   result = ReviewAnalyzer.call(text: "review")
      #   result.branches[:sentiment] # Branch result
      #   result.failed_branches      # [:toxicity] if it failed
      #
      # @example Router result
      #   result = SupportRouter.call(message: "billing issue")
      #   result.routed_to           # :billing
      #   result.classification      # Classification details
      #
      # @api public
      class Result
        extend ActiveSupport::Delegation

        # @!attribute [r] content
        #   @return [Object] The final processed content
        attr_reader :content

        # @!attribute [r] workflow_type
        #   @return [String] The workflow class name
        attr_reader :workflow_type

        # @!attribute [r] workflow_id
        #   @return [String] Unique identifier for this workflow execution
        attr_reader :workflow_id

        # @!group Step/Branch Results

        # @!attribute [r] steps
        #   @return [Hash<Symbol, Result>] Results from pipeline steps
        attr_reader :steps

        # @!attribute [r] branches
        #   @return [Hash<Symbol, Result>] Results from parallel branches
        attr_reader :branches

        # @!endgroup

        # @!group Router Results

        # @!attribute [r] routed_to
        #   @return [Symbol, nil] The route that was selected
        attr_reader :routed_to

        # @!attribute [r] classification
        #   @return [Hash, nil] Classification details from router
        attr_reader :classification

        # @!attribute [r] classifier_result
        #   @return [Result, nil] The classifier agent's result
        attr_reader :classifier_result

        # @!endgroup

        # @!group Timing

        # @!attribute [r] started_at
        #   @return [Time] When the workflow started
        attr_reader :started_at

        # @!attribute [r] completed_at
        #   @return [Time] When the workflow completed
        attr_reader :completed_at

        # @!attribute [r] duration_ms
        #   @return [Integer] Total workflow duration in milliseconds
        attr_reader :duration_ms

        # @!endgroup

        # @!group Status

        # @!attribute [r] status
        #   @return [String] Workflow status: "success", "error", "partial"
        attr_reader :status

        # @!attribute [r] error_class
        #   @return [String, nil] Error class if failed
        attr_reader :error_class

        # @!attribute [r] error_message
        #   @return [String, nil] Error message if failed
        attr_reader :error_message

        # @!attribute [r] errors
        #   @return [Hash<Symbol, Exception>] Errors by step/branch name
        attr_reader :errors

        # @!endgroup

        # Creates a new WorkflowResult
        #
        # @param content [Object] The final processed content
        # @param options [Hash] Additional result metadata
        def initialize(content:, **options)
          @content = content
          @workflow_type = options[:workflow_type]
          @workflow_id = options[:workflow_id]

          # Step/branch results
          @steps = options[:steps] || {}
          @branches = options[:branches] || {}

          # Router results
          @routed_to = options[:routed_to]
          @classification = options[:classification]
          @classifier_result = options[:classifier_result]

          # Timing
          @started_at = options[:started_at]
          @completed_at = options[:completed_at]
          @duration_ms = options[:duration_ms]

          # Status
          @status = options[:status] || "success"
          @error_class = options[:error_class]
          @error_message = options[:error_message]
          @errors = options[:errors] || {}
        end

        # Returns all child results (steps + branches + classifier)
        #
        # @return [Array<Result>] All child results
        def child_results
          results = []
          results.concat(steps.values) if steps.any?
          results.concat(branches.values) if branches.any?
          results << classifier_result if classifier_result
          results.compact
        end

        # @!group Aggregate Metrics

        # Returns total input tokens across all child executions
        #
        # @return [Integer] Total input tokens
        def input_tokens
          child_results.sum { |r| r.input_tokens || 0 }
        end

        # Returns total output tokens across all child executions
        #
        # @return [Integer] Total output tokens
        def output_tokens
          child_results.sum { |r| r.output_tokens || 0 }
        end

        # Returns total tokens across all child executions
        #
        # @return [Integer] Total tokens
        def total_tokens
          input_tokens + output_tokens
        end

        # Returns total cached tokens across all child executions
        #
        # @return [Integer] Total cached tokens
        def cached_tokens
          child_results.sum { |r| r.cached_tokens || 0 }
        end

        # Returns total input cost across all child executions
        #
        # @return [Float] Total input cost in USD
        def input_cost
          child_results.sum { |r| r.input_cost || 0.0 }
        end

        # Returns total output cost across all child executions
        #
        # @return [Float] Total output cost in USD
        def output_cost
          child_results.sum { |r| r.output_cost || 0.0 }
        end

        # Returns total cost across all child executions
        #
        # @return [Float] Total cost in USD
        def total_cost
          child_results.sum { |r| r.total_cost || 0.0 }
        end

        # Returns classification cost (router workflows only)
        #
        # @return [Float] Classification cost in USD
        def classification_cost
          classifier_result&.total_cost || 0.0
        end

        # @!endgroup

        # @!group Status Helpers

        # Returns whether the workflow succeeded
        #
        # @return [Boolean] true if status is "success"
        def success?
          status == "success"
        end

        # Returns whether the workflow failed
        #
        # @return [Boolean] true if status is "error"
        def error?
          status == "error"
        end

        # Returns whether the workflow partially succeeded
        #
        # @return [Boolean] true if status is "partial"
        def partial?
          status == "partial"
        end

        # @!endgroup

        # @!group Pipeline Helpers

        # Returns whether all pipeline steps succeeded
        #
        # @return [Boolean] true if all steps successful
        def all_steps_successful?
          return true if steps.empty?

          steps.values.all? { |r| r.respond_to?(:success?) ? r.success? : true }
        end

        # Returns the names of failed steps
        #
        # @return [Array<Symbol>] Failed step names
        def failed_steps
          steps.select { |_, r| r.respond_to?(:error?) && r.error? }.keys
        end

        # Returns the names of skipped steps
        #
        # @return [Array<Symbol>] Skipped step names
        def skipped_steps
          steps.select { |_, r| r.respond_to?(:skipped?) && r.skipped? }.keys
        end

        # @!endgroup

        # @!group Parallel Helpers

        # Returns whether all parallel branches succeeded
        #
        # @return [Boolean] true if all branches successful
        def all_branches_successful?
          return true if branches.empty?

          branches.values.all? { |r| r.nil? || (r.respond_to?(:success?) ? r.success? : true) }
        end

        # Returns the names of failed branches
        #
        # @return [Array<Symbol>] Failed branch names
        def failed_branches
          failed = branches.select { |_, r| r.respond_to?(:error?) && r.error? }.keys
          failed += errors.keys
          failed.uniq
        end

        # Returns the names of successful branches
        #
        # @return [Array<Symbol>] Successful branch names
        def successful_branches
          branches.select { |_, r| r.respond_to?(:success?) && r.success? }.keys
        end

        # @!endgroup

        # Converts the result to a hash
        #
        # @return [Hash] All result data
        def to_h
          {
            content: content,
            workflow_type: workflow_type,
            workflow_id: workflow_id,
            status: status,
            steps: steps.transform_values { |r| r.respond_to?(:to_h) ? r.to_h : r },
            branches: branches.transform_values { |r| r.respond_to?(:to_h) ? r.to_h : r },
            routed_to: routed_to,
            classification: classification,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: total_tokens,
            cached_tokens: cached_tokens,
            input_cost: input_cost,
            output_cost: output_cost,
            total_cost: total_cost,
            started_at: started_at,
            completed_at: completed_at,
            duration_ms: duration_ms,
            error_class: error_class,
            error_message: error_message,
            errors: errors.transform_values { |e| { class: e.class.name, message: e.message } }
          }
        end

        # Delegate hash methods to content for convenience
        delegate :[], :dig, :keys, :values, :each, :map, to: :content, allow_nil: true

        # Custom to_json that includes workflow metadata
        #
        # @param args [Array] Arguments passed to to_json
        # @return [String] JSON representation
        def to_json(*args)
          to_h.to_json(*args)
        end
      end

      # Represents a skipped step result
      class SkippedResult
        attr_reader :step_name, :reason

        def initialize(step_name, reason: nil)
          @step_name = step_name
          @reason = reason
        end

        def content
          nil
        end

        def success?
          true
        end

        def error?
          false
        end

        def skipped?
          true
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
          { skipped: true, step_name: step_name, reason: reason }
        end
      end

      # Result wrapper for sub-workflow execution
      #
      # Wraps a nested workflow result while providing access to
      # aggregate metrics and the underlying workflow result.
      #
      # @api public
      class SubWorkflowResult
        attr_reader :content, :sub_workflow_result, :workflow_type, :step_name

        def initialize(content:, sub_workflow_result:, workflow_type:, step_name:)
          @content = content
          @sub_workflow_result = sub_workflow_result
          @workflow_type = workflow_type
          @step_name = step_name
        end

        def success?
          sub_workflow_result.respond_to?(:success?) ? sub_workflow_result.success? : true
        end

        def error?
          sub_workflow_result.respond_to?(:error?) ? sub_workflow_result.error? : false
        end

        def skipped?
          false
        end

        # Delegate metrics to sub-workflow result
        def input_tokens
          sub_workflow_result.respond_to?(:input_tokens) ? sub_workflow_result.input_tokens : 0
        end

        def output_tokens
          sub_workflow_result.respond_to?(:output_tokens) ? sub_workflow_result.output_tokens : 0
        end

        def total_tokens
          input_tokens + output_tokens
        end

        def cached_tokens
          sub_workflow_result.respond_to?(:cached_tokens) ? sub_workflow_result.cached_tokens : 0
        end

        def input_cost
          sub_workflow_result.respond_to?(:input_cost) ? sub_workflow_result.input_cost : 0.0
        end

        def output_cost
          sub_workflow_result.respond_to?(:output_cost) ? sub_workflow_result.output_cost : 0.0
        end

        def total_cost
          sub_workflow_result.respond_to?(:total_cost) ? sub_workflow_result.total_cost : 0.0
        end

        # Access sub-workflow steps
        def steps
          sub_workflow_result.respond_to?(:steps) ? sub_workflow_result.steps : {}
        end

        def to_h
          {
            content: content,
            workflow_type: workflow_type,
            step_name: step_name,
            sub_workflow: sub_workflow_result.respond_to?(:to_h) ? sub_workflow_result.to_h : sub_workflow_result,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_cost: total_cost
          }
        end

        # Delegate hash access to content
        def [](key)
          content.is_a?(Hash) ? content[key] : nil
        end

        def dig(*keys)
          content.is_a?(Hash) ? content.dig(*keys) : nil
        end
      end

      # Result wrapper for iteration execution
      #
      # Tracks results for each item in an iteration with
      # aggregate success/failure counts and metrics.
      #
      # @api public
      class IterationResult
        attr_reader :step_name, :item_results, :errors

        def initialize(step_name:, item_results: [], errors: {})
          @step_name = step_name
          @item_results = item_results
          @errors = errors
        end

        def content
          item_results.map do |result|
            result.respond_to?(:content) ? result.content : result
          end
        end

        def success?
          errors.empty? && item_results.all? do |r|
            !r.respond_to?(:error?) || !r.error?
          end
        end

        def error?
          !success?
        end

        def partial?
          errors.any? && item_results.any? do |r|
            !r.respond_to?(:error?) || !r.error?
          end
        end

        def skipped?
          false
        end

        def successful_count
          item_results.count { |r| !r.respond_to?(:error?) || !r.error? }
        end

        def failed_count
          errors.size + item_results.count { |r| r.respond_to?(:error?) && r.error? }
        end

        def total_count
          item_results.size + errors.size
        end

        # Aggregate metrics across all items
        def input_tokens
          item_results.sum { |r| r.respond_to?(:input_tokens) ? r.input_tokens : 0 }
        end

        def output_tokens
          item_results.sum { |r| r.respond_to?(:output_tokens) ? r.output_tokens : 0 }
        end

        def total_tokens
          input_tokens + output_tokens
        end

        def cached_tokens
          item_results.sum { |r| r.respond_to?(:cached_tokens) ? r.cached_tokens : 0 }
        end

        def input_cost
          item_results.sum { |r| r.respond_to?(:input_cost) ? r.input_cost : 0.0 }
        end

        def output_cost
          item_results.sum { |r| r.respond_to?(:output_cost) ? r.output_cost : 0.0 }
        end

        def total_cost
          item_results.sum { |r| r.respond_to?(:total_cost) ? r.total_cost : 0.0 }
        end

        def to_h
          {
            step_name: step_name,
            total_count: total_count,
            successful_count: successful_count,
            failed_count: failed_count,
            success: success?,
            items: item_results.map { |r| r.respond_to?(:to_h) ? r.to_h : r },
            errors: errors.transform_values { |e| { class: e.class.name, message: e.message } },
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_cost: total_cost
          }
        end

        # Access individual item results by index
        def [](index)
          item_results[index]
        end

        def each(&block)
          item_results.each(&block)
        end

        def map(&block)
          item_results.map(&block)
        end

        include Enumerable

        # Empty iteration result factory
        def self.empty(step_name)
          new(step_name: step_name, item_results: [], errors: {})
        end
      end
    end
  end
end
