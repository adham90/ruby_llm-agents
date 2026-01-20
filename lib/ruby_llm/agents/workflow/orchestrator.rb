# frozen_string_literal: true

require_relative "result"
require_relative "instrumentation"
require_relative "thread_pool"
require_relative "pipeline"
require_relative "parallel"
require_relative "router"

module RubyLLM
  module Agents
    # Base class for workflow orchestration
    #
    # Provides shared functionality for composing multiple agents into
    # coordinated workflows. Subclasses implement specific patterns:
    # - Pipeline: Sequential execution with data flowing between steps
    # - Parallel: Concurrent execution with result aggregation
    # - Router: Conditional dispatch based on classification
    #
    # @example Creating a custom workflow
    #   class MyWorkflow < RubyLLM::Agents::Workflow
    #     version "1.0"
    #     # ... workflow-specific DSL
    #   end
    #
    # @see RubyLLM::Agents::Workflow::Pipeline
    # @see RubyLLM::Agents::Workflow::Parallel
    # @see RubyLLM::Agents::Workflow::Router
    # @api public
    class Workflow
      include Workflow::Instrumentation

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
        # @param kwargs [Hash] Parameters to pass to the workflow
        # @yield [chunk] Optional block for streaming support
        # @return [WorkflowResult] The workflow result with aggregate metrics
        def call(**kwargs, &block)
          new(**kwargs).call(&block)
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

      # Creates a new workflow instance
      #
      # @param kwargs [Hash] Parameters for the workflow
      def initialize(**kwargs)
        @options = kwargs
        @workflow_id = SecureRandom.uuid
        @execution_id = nil
        @accumulated_cost = 0.0
        @step_results = {}
      end

      # Executes the workflow
      #
      # @abstract Subclasses must implement this method
      # @yield [chunk] Optional block for streaming support
      # @return [WorkflowResult] The workflow result
      def call(&block)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

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
