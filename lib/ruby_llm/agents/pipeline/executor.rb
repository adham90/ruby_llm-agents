# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      # Wraps an agent's execute method to work with the pipeline.
      #
      # This is the "core" that middleware wraps around. It's the final
      # handler in the chain that actually performs the agent's work.
      #
      # The Executor adapts the agent's #execute method to the middleware
      # interface (call(context) -> context).
      #
      # @example Basic usage
      #   executor = Executor.new(agent)
      #   context = Context.new(input: "hello", agent_class: MyAgent)
      #   result_context = executor.call(context)
      #
      # @example With pipeline
      #   pipeline = Builder.for(MyAgent).build(Executor.new(agent))
      #   result = pipeline.call(context)
      #
      class Executor
        # @param agent [Object] The agent instance with an #execute method
        def initialize(agent)
          @agent = agent
        end

        # Execute the agent's core logic
        #
        # Calls the agent's #execute method with the context.
        # The agent is expected to set context.output with the result.
        #
        # @param context [Context] The execution context
        # @return [Context] The context with output set
        def call(context)
          @agent.execute(context)
          context
        end
      end

      # Lambda-based executor for simple cases
      #
      # Allows wrapping a lambda/proc as the core executor,
      # useful for testing or simple agents.
      #
      # @example
      #   executor = LambdaExecutor.new(->(ctx) {
      #     ctx.output = "Hello, #{ctx.input}!"
      #   })
      #
      class LambdaExecutor
        # @param callable [#call] A lambda/proc that takes a context
        def initialize(callable)
          @callable = callable
        end

        # Execute the lambda with the context
        #
        # @param context [Context] The execution context
        # @return [Context] The context (possibly modified by the lambda)
        def call(context)
          @callable.call(context)
          context
        end
      end
    end
  end
end
