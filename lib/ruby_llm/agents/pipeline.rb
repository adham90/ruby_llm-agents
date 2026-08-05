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
require_relative "pipeline/middleware/attachment_persistence"

module RubyLLM
  module Agents
    module Pipeline
    end
  end
end
