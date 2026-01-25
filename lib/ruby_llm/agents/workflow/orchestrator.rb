# frozen_string_literal: true

require_relative "result"
require_relative "instrumentation"
require_relative "thread_pool"
require_relative "dsl"
require_relative "dsl/executor"

module RubyLLM
  module Agents
    # Base class for workflow orchestration
    #
    # Provides shared functionality for composing multiple agents into
    # coordinated workflows using the DSL:
    # - Sequential steps with data flowing between them
    # - Parallel execution with result aggregation
    # - Conditional routing based on step results
    #
    # @example Minimal workflow
    #   class SimpleWorkflow < RubyLLM::Agents::Workflow
    #     step :fetch, FetcherAgent
    #     step :process, ProcessorAgent
    #     step :save, SaverAgent
    #   end
    #
    # @example Full-featured workflow
    #   class OrderWorkflow < RubyLLM::Agents::Workflow
    #     description "Process customer orders end-to-end"
    #
    #     input do
    #       required :order_id, String
    #       optional :priority, String, default: "normal"
    #     end
    #
    #     step :fetch, FetcherAgent, timeout: 1.minute
    #     step :validate, ValidatorAgent
    #
    #     step :process, on: -> { validate.tier } do |route|
    #       route.premium  PremiumAgent
    #       route.standard StandardAgent
    #       route.default  DefaultAgent
    #     end
    #
    #     parallel do
    #       step :analyze, AnalyzerAgent
    #       step :summarize, SummarizerAgent
    #     end
    #
    #     step :notify, NotifierAgent, if: :should_notify?
    #
    #     private
    #
    #     def should_notify?
    #       input.callback_url.present?
    #     end
    #   end
    #
    # @api public
    class Workflow
      include Workflow::Instrumentation
      include Workflow::DSL

      class << self
        # @!attribute [rw] version
        #   @return [String] Version identifier for the workflow
        attr_accessor :_version

        # @!attribute [rw] timeout
        #   @return [Integer, nil] Total timeout for the entire workflow in seconds
        attr_accessor :_timeout

        # @!attribute [rw] max_cost
        #   @return [Float, nil] Maximum cost threshold for the workflow
        attr_accessor :_max_cost

        # @!attribute [rw] description
        #   @return [String, nil] Description of the workflow
        attr_accessor :_description

        # Sets or returns the workflow version
        #
        # @param value [String, nil] Version string to set
        # @return [String] The current version
        def version(value = nil)
          if value
            self._version = value
          else
            _version || "1.0"
          end
        end

        # Sets or returns the workflow timeout
        #
        # @param value [Integer, ActiveSupport::Duration, nil] Timeout to set
        # @return [Integer, nil] The current timeout in seconds
        def timeout(value = nil)
          if value
            self._timeout = value.is_a?(ActiveSupport::Duration) ? value.to_i : value
          else
            _timeout
          end
        end

        # Sets or returns the maximum cost threshold
        #
        # @param value [Float, nil] Max cost in USD
        # @return [Float, nil] The current max cost
        def max_cost(value = nil)
          if value
            self._max_cost = value.to_f
          else
            _max_cost
          end
        end

        # Sets or returns the workflow description
        #
        # @param value [String, nil] Description text to set
        # @return [String, nil] The current description
        def description(value = nil)
          if value
            self._description = value
          else
            _description
          end
        end

        # Factory method to instantiate and execute a workflow
        #
        # Supports both hash and keyword argument styles:
        #   MyWorkflow.call(order_id: "123")
        #   MyWorkflow.call({ order_id: "123" })
        #
        # @param input [Hash] Input hash (optional)
        # @param kwargs [Hash] Parameters to pass to the workflow
        # @yield [chunk] Optional block for streaming support
        # @return [WorkflowResult] The workflow result with aggregate metrics
        def call(input = nil, **kwargs, &block)
          # Support both call(hash) and call(**kwargs) patterns
          merged_input = input.is_a?(Hash) ? input.merge(kwargs) : kwargs
          # Pass input to constructor to maintain backward compatibility with
          # legacy subclasses that override call without arguments
          new(**merged_input).call(&block)
        end
      end

      # @!attribute [r] options
      #   @return [Hash] The options passed to the workflow
      attr_reader :options

      # @!attribute [r] workflow_id
      #   @return [String] Unique identifier for this workflow execution
      attr_reader :workflow_id

      # @!attribute [r] execution_id
      #   @return [Integer, nil] The ID of the root execution record
      attr_reader :execution_id

      # @!attribute [r] step_results
      #   @return [Hash<Symbol, Result>] Results from executed steps
      attr_reader :step_results

      # Creates a new workflow instance
      #
      # @param kwargs [Hash] Parameters for the workflow
      def initialize(**kwargs)
        @options = kwargs
        @workflow_id = SecureRandom.uuid
        @execution_id = nil
        @accumulated_cost = 0.0
        @step_results = {}
        @validated_input = nil
      end

      # Executes the workflow
      #
      # When using the new DSL with `step` declarations, this method
      # automatically executes the workflow using the DSL executor.
      # For legacy subclasses (Pipeline, Parallel, Router), this raises
      # NotImplementedError to be overridden.
      #
      # Supports both hash and keyword argument styles:
      #   workflow.call(order_id: "123")
      #   workflow.call({ order_id: "123" })
      #
      # @param input [Hash] Input hash (optional)
      # @param kwargs [Hash] Keyword arguments for input
      # @yield [chunk] Optional block for streaming support
      # @return [WorkflowResult] The workflow result
      def call(input = nil, **kwargs, &block)
        # Merge input sources: constructor options, hash arg, keyword args
        merged_input = @options.merge(input.is_a?(Hash) ? input : {}).merge(kwargs)
        @options = merged_input

        # Use DSL executor if steps are defined with the new DSL
        if self.class.step_configs.any?
          instrument_workflow do
            execute_with_dsl(&block)
          end
        else
          raise NotImplementedError, "#{self.class} must implement #call or define steps"
        end
      end

      # Validates workflow input and executes a dry run
      #
      # Returns information about the workflow without executing agents.
      # Supports both positional hash and keyword arguments.
      #
      # @param input_hash [Hash] Input hash (optional)
      # @param input [Hash] Keyword arguments for input
      # @return [Hash] Validation results and workflow structure
      def self.dry_run(input_hash = nil, **input)
        input = input_hash.merge(input) if input_hash.is_a?(Hash)
        errors = []

        # Validate input if schema defined
        if input_schema
          begin
            input_schema.validate!(input)
          rescue DSL::InputSchema::ValidationError => e
            errors.concat(e.errors)
          end
        end

        # Validate configuration
        errors.concat(validate_configuration)

        {
          valid: errors.empty?,
          input_errors: errors,
          steps: step_metadata.map { |s| s[:name] },
          agents: step_metadata.map { |s| s[:agent] }.compact,
          parallel_groups: parallel_groups.map(&:to_h),
          warnings: validate_configuration
        }
      end

      private

      # Executes the workflow using the DSL executor
      #
      # @return [WorkflowResult] The workflow result
      def execute_with_dsl(&block)
        executor = DSL::Executor.new(self)
        executor.execute(&block)
      end

      public

      protected

      # Executes a single agent within the workflow context
      #
      # Passes execution metadata for proper tracking and hierarchy.
      #
      # @param agent_class [Class] The agent class to execute
      # @param input [Hash] Parameters to pass to the agent
      # @param step_name [String, Symbol] Name of the workflow step
      # @yield [chunk] Optional block for streaming
      # @return [Result] The agent result
      def execute_agent(agent_class, input, step_name: nil, &block)
        metadata = {
          parent_execution_id: execution_id,
          root_execution_id: root_execution_id,
          workflow_id: workflow_id,
          workflow_type: self.class.name,
          workflow_step: step_name&.to_s
        }.compact

        # Merge workflow metadata with any existing metadata
        merged_input = input.merge(
          execution_metadata: metadata.merge(input[:execution_metadata] || {})
        )

        result = agent_class.call(**merged_input, &block)

        # Track accumulated cost for max_cost enforcement
        @accumulated_cost += result.total_cost if result.respond_to?(:total_cost) && result.total_cost

        # Check cost threshold
        check_cost_threshold!

        result
      end

      # Returns the root execution ID for the workflow
      #
      # @return [Integer, nil] The root execution ID
      def root_execution_id
        @root_execution_id || execution_id
      end

      # Sets the root execution ID
      #
      # @param id [Integer] The root execution ID
      def root_execution_id=(id)
        @root_execution_id = id
      end

      # Checks if accumulated cost exceeds the threshold
      #
      # @raise [WorkflowCostExceededError] If cost exceeds max_cost
      def check_cost_threshold!
        return unless self.class.max_cost
        return if @accumulated_cost <= self.class.max_cost

        raise WorkflowCostExceededError.new(
          "Workflow cost ($#{@accumulated_cost.round(4)}) exceeded maximum ($#{self.class.max_cost})",
          accumulated_cost: @accumulated_cost,
          max_cost: self.class.max_cost
        )
      end

      # Hook for subclasses to transform input before a step
      #
      # @param step_name [Symbol] The step name
      # @param context [Hash] Current workflow context
      # @return [Hash] Transformed input for the step
      def before_step(step_name, context)
        method_name = :"before_#{step_name}"
        if respond_to?(method_name, true)
          send(method_name, context)
        else
          extract_step_input(context)
        end
      end

      # Extracts input for the next step from context
      #
      # Default behavior: use the last step's content or original input
      #
      # @param context [Hash] Current workflow context
      # @return [Hash] Input for the next step
      def extract_step_input(context)
        # Get the last non-input result
        last_result = context.except(:input).values.last

        if last_result.is_a?(Result) || last_result.is_a?(Workflow::Result)
          # If content is a hash, use it; otherwise wrap it
          content = last_result.content
          content.is_a?(Hash) ? content : { input: content }
        else
          context[:input] || {}
        end
      end
    end

    # Error raised when workflow cost exceeds the configured maximum
    class WorkflowCostExceededError < StandardError
      attr_reader :accumulated_cost, :max_cost

      def initialize(message, accumulated_cost:, max_cost:)
        super(message)
        @accumulated_cost = accumulated_cost
        @max_cost = max_cost
      end
    end
  end
end
