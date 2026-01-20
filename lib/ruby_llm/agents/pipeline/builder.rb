# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      # Builds the middleware pipeline from agent DSL configuration.
      #
      # The builder allows both manual pipeline construction and automatic
      # construction based on agent DSL settings.
      #
      # @example Manual pipeline construction
      #   builder = Builder.new(MyEmbedder)
      #   builder.use(Middleware::Tenant)
      #   builder.use(Middleware::Cache)
      #   builder.use(Middleware::Instrumentation)
      #   pipeline = builder.build(core_executor)
      #
      # @example Automatic construction from DSL
      #   pipeline = Builder.for(MyEmbedder).build(core_executor)
      #
      # @example With custom middleware insertion
      #   builder = Builder.for(MyEmbedder)
      #   builder.insert_before(Middleware::Instrumentation, MyLoggingMiddleware)
      #   pipeline = builder.build(core_executor)
      #
      class Builder
        # @return [Class] The agent class this builder is for
        attr_reader :agent_class

        # @return [Array<Class>] The middleware stack (in execution order)
        attr_reader :stack

        # Creates a new builder for an agent class
        #
        # @param agent_class [Class] The agent class
        def initialize(agent_class)
          @agent_class = agent_class
          @stack = []
        end

        # Add middleware to the end of the stack
        #
        # @param middleware_class [Class] Middleware class to add
        # @return [self] For method chaining
        def use(middleware_class)
          @stack << middleware_class
          self
        end

        # Insert middleware before another middleware
        #
        # @param existing [Class] The middleware to insert before
        # @param new_middleware [Class] The middleware to insert
        # @return [self] For method chaining
        # @raise [ArgumentError] If existing middleware not found
        def insert_before(existing, new_middleware)
          index = @stack.index(existing)
          raise ArgumentError, "#{existing} not found in stack" unless index

          @stack.insert(index, new_middleware)
          self
        end

        # Insert middleware after another middleware
        #
        # @param existing [Class] The middleware to insert after
        # @param new_middleware [Class] The middleware to insert
        # @return [self] For method chaining
        # @raise [ArgumentError] If existing middleware not found
        def insert_after(existing, new_middleware)
          index = @stack.index(existing)
          raise ArgumentError, "#{existing} not found in stack" unless index

          @stack.insert(index + 1, new_middleware)
          self
        end

        # Remove a middleware from the stack
        #
        # @param middleware_class [Class] The middleware to remove
        # @return [self] For method chaining
        def delete(middleware_class)
          @stack.delete(middleware_class)
          self
        end

        # Build the pipeline, wrapping the core executor
        #
        # Middleware is wrapped in reverse order so that the first
        # middleware in the stack is the outermost wrapper.
        #
        # @param core [#call] The core execution logic (usually an Executor)
        # @return [#call] The complete pipeline
        def build(core)
          @stack.reverse.reduce(core) do |app, middleware_class|
            middleware_class.new(app, @agent_class)
          end
        end

        # Returns whether the stack includes a middleware
        #
        # @param middleware_class [Class] The middleware class to check
        # @return [Boolean]
        def include?(middleware_class)
          @stack.include?(middleware_class)
        end

        # Returns the stack as an array (copy)
        #
        # @return [Array<Class>]
        def to_a
          @stack.dup
        end

        class << self
          # Build default pipeline for an agent class
          #
          # Reads DSL configuration to determine which middleware to include.
          # The order is:
          # 1. Tenant (always - resolves tenant context)
          # 2. Budget (if enabled - checks budget before execution)
          # 3. Instrumentation (always - tracks execution, including cache hits)
          # 4. Cache (if enabled - returns cached results)
          # 5. Reliability (if enabled - retries and fallbacks)
          #
          # Note: Instrumentation must come BEFORE Cache so it can track cache hits.
          # When Cache returns early on a hit, Instrumentation still sees it.
          #
          # @param agent_class [Class] The agent class
          # @return [Builder] A configured builder
          def for(agent_class)
            new(agent_class).tap do |builder|
              # Always included - tenant resolution
              builder.use(Middleware::Tenant)

              # Budget checking (if enabled globally)
              builder.use(Middleware::Budget) if budgets_enabled?

              # Instrumentation (always - for tracking, must be before Cache)
              builder.use(Middleware::Instrumentation)

              # Caching (if enabled on the agent)
              builder.use(Middleware::Cache) if cache_enabled?(agent_class)

              # Reliability (if agent has retries or fallbacks configured)
              builder.use(Middleware::Reliability) if reliability_enabled?(agent_class)
            end
          end

          # Returns an empty builder (no middleware)
          #
          # Useful for testing or when you want full control.
          #
          # @param agent_class [Class] The agent class
          # @return [Builder] An empty builder
          def empty(agent_class)
            new(agent_class)
          end

          private

          # Check if budgets are enabled globally
          #
          # @return [Boolean]
          def budgets_enabled?
            RubyLLM::Agents.configuration.budgets_enabled?
          rescue StandardError
            false
          end

          # Check if caching is enabled for an agent
          #
          # @param agent_class [Class] The agent class
          # @return [Boolean]
          def cache_enabled?(agent_class)
            return false unless agent_class

            agent_class.respond_to?(:cache_enabled?) && agent_class.cache_enabled?
          rescue StandardError
            false
          end

          # Check if reliability features are enabled for an agent
          #
          # An agent has reliability enabled if it has:
          # - retries > 0, OR
          # - fallback_models configured
          #
          # @param agent_class [Class] The agent class
          # @return [Boolean]
          def reliability_enabled?(agent_class)
            return false unless agent_class

            retries = if agent_class.respond_to?(:retries)
                        agent_class.retries
                      else
                        0
                      end

            fallbacks = if agent_class.respond_to?(:fallback_models)
                          agent_class.fallback_models
                        else
                          []
                        end

            (retries.is_a?(Integer) && retries.positive?) ||
              (fallbacks.is_a?(Array) && fallbacks.any?)
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
