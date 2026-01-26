# frozen_string_literal: true

# Pipeline infrastructure for middleware-based agent execution
#
# The pipeline provides a clean separation of concerns through middleware:
# - Context: Carries data through the pipeline
# - Middleware: Wraps execution with cross-cutting concerns
# - Builder: Constructs the middleware stack
# - Executor: Adapts agent execution to the pipeline interface
#
# @example Basic pipeline usage
#   # Build a pipeline for an agent class
#   pipeline = Pipeline::Builder.for(MyEmbedder).build(
#     Pipeline::Executor.new(agent_instance)
#   )
#
#   # Create a context and execute
#   context = Pipeline::Context.new(
#     input: "Hello world",
#     agent_class: MyEmbedder
#   )
#   result_context = pipeline.call(context)
#
# @see Pipeline::Context
# @see Pipeline::Builder
# @see Pipeline::Middleware::Base
#
require_relative "pipeline/context"
require_relative "pipeline/executor"
require_relative "pipeline/builder"

# Middleware classes
require_relative "pipeline/middleware/base"
require_relative "pipeline/middleware/tenant"
require_relative "pipeline/middleware/budget"
require_relative "pipeline/middleware/cache"
require_relative "pipeline/middleware/instrumentation"
require_relative "pipeline/middleware/reliability"

module RubyLLM
  module Agents
    module Pipeline
      # Represents an error result from a failed step
      #
      # Used to track errors that occurred during step execution while
      # allowing the workflow to continue (for optional steps).
      #
      # @api public
      class ErrorResult
        attr_reader :step_name, :error_class, :error_message

        def initialize(step_name:, error_class:, error_message:)
          @step_name = step_name
          @error_class = error_class
          @error_message = error_message
        end

        def content
          nil
        end

        def success?
          false
        end

        def error?
          true
        end

        def skipped?
          false
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
          {
            error: true,
            step_name: step_name,
            error_class: error_class,
            error_message: error_message
          }
        end
      end

      class << self
        # Build a pipeline for an agent class with default middleware
        #
        # This is a convenience method that combines Builder.for with build.
        #
        # @param agent_class [Class] The agent class
        # @param executor [#call] The core executor
        # @return [#call] The complete pipeline
        def build(agent_class, executor)
          Builder.for(agent_class).build(executor)
        end

        # Build an empty pipeline (no middleware)
        #
        # Useful for testing or when you want direct execution.
        #
        # @param agent_class [Class] The agent class
        # @param executor [#call] The core executor
        # @return [#call] The executor (no middleware wrapping)
        def build_empty(agent_class, executor)
          Builder.empty(agent_class).build(executor)
        end
      end
    end
  end
end
