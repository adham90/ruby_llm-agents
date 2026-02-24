# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Thread-safe shared context for passing data between workflow steps
      #
      # Stores initial parameters, step results, and arbitrary data.
      # Uses a Mutex for safe concurrent writes (Phase 2 parallel execution).
      #
      # @example
      #   ctx = WorkflowContext.new(topic: "AI")
      #   ctx[:topic]          # => "AI"
      #   ctx[:draft] = result # stores step result
      #   ctx.step_result(:draft) # => the result object
      #
      class WorkflowContext
        attr_reader :params, :step_results, :errors

        # @param params [Hash] Initial parameters from .call()
        def initialize(**params)
          @params = params.dup
          @data = params.dup
          @step_results = {}
          @errors = {}
          @mutex = Mutex.new
        end

        # Read a value (thread-safe)
        #
        # @param key [Symbol, String] The key to look up
        # @return [Object, nil]
        def [](key)
          @mutex.synchronize { @data[key.to_sym] }
        end

        # Write a value (thread-safe)
        #
        # @param key [Symbol, String] The key to set
        # @param value [Object] The value to store
        def []=(key, value)
          @mutex.synchronize { @data[key.to_sym] = value }
        end

        # Fetch with default (thread-safe)
        def fetch(key, default = nil)
          @mutex.synchronize { @data.fetch(key.to_sym, default) }
        end

        # Store the result of a step execution
        #
        # @param step_name [Symbol] The step that produced this result
        # @param result [Object] The agent result
        def store_step_result(step_name, result)
          @mutex.synchronize do
            @step_results[step_name.to_sym] = result
            @data[step_name.to_sym] = result
          end
        end

        # Record an error for a step
        #
        # @param step_name [Symbol] The step that errored
        # @param error [Exception] The error
        def store_error(step_name, error)
          @mutex.synchronize do
            @errors[step_name.to_sym] = error
          end
        end

        # Get the result object for a specific step
        #
        # @param step_name [Symbol] The step name
        # @return [Object, nil]
        def step_result(step_name)
          @mutex.synchronize { @step_results[step_name.to_sym] }
        end

        # Check if a step completed successfully
        #
        # @param step_name [Symbol]
        # @return [Boolean]
        def step_completed?(step_name)
          @mutex.synchronize { @step_results.key?(step_name.to_sym) }
        end

        # Return a snapshot of all data (thread-safe copy)
        #
        # @return [Hash]
        def to_h
          @mutex.synchronize { @data.dup }
        end

        # Number of completed steps
        def completed_step_count
          @mutex.synchronize { @step_results.size }
        end
      end
    end
  end
end
