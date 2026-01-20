# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Base class for all middleware in the pipeline.
        #
        # Middleware wraps the next handler in the chain and can:
        # - Modify the context before passing it down
        # - Short-circuit the chain (e.g., return cached result)
        # - Handle errors from downstream
        # - Modify the context after the response
        #
        # Each middleware receives:
        # - @app: The next handler in the chain (another middleware or the executor)
        # - @agent_class: The agent class, for reading DSL configuration
        #
        # @example Simple pass-through middleware
        #   class Logger < Base
        #     def call(context)
        #       puts "Before: #{context.input}"
        #       result = @app.call(context)
        #       puts "After: #{context.output}"
        #       result
        #     end
        #   end
        #
        # @example Short-circuiting middleware
        #   class Cache < Base
        #     def call(context)
        #       if (cached = read_cache(context))
        #         context.output = cached
        #         context.cached = true
        #         return context
        #       end
        #       @app.call(context)
        #     end
        #   end
        #
        # @abstract Subclass and implement {#call}
        #
        class Base
          # @param app [#call] The next handler in the chain
          # @param agent_class [Class] The agent class (for reading DSL config)
          def initialize(app, agent_class)
            @app = app
            @agent_class = agent_class
          end

          # Process the context through this middleware
          #
          # Subclasses must implement this method. The typical pattern is:
          # 1. Do pre-processing on context
          # 2. Call @app.call(context) to continue the chain
          # 3. Do post-processing on context
          # 4. Return context
          #
          # @param context [Context] The execution context
          # @return [Context] The (possibly modified) context
          # @raise [NotImplementedError] If not implemented by subclass
          def call(context)
            raise NotImplementedError, "#{self.class} must implement #call"
          end

          private

          # Read configuration from agent class DSL
          #
          # Safely reads a DSL method value from the agent class,
          # returning a default if the method doesn't exist.
          #
          # @param method [Symbol] DSL method name
          # @param default [Object] Default value if not set
          # @return [Object] The configuration value
          def config(method, default = nil)
            return default unless @agent_class

            if @agent_class.respond_to?(method)
              @agent_class.send(method)
            else
              default
            end
          end

          # Check if a DSL option is enabled
          #
          # Convenience method for boolean DSL options.
          #
          # @param method [Symbol] DSL method name (e.g., :cache_enabled?)
          # @return [Boolean]
          def enabled?(method)
            config(method, false) == true
          end

          # Returns the global configuration
          #
          # @return [Configuration] The RubyLLM::Agents configuration
          def global_config
            RubyLLM::Agents.configuration
          end

          # Log a debug message if Rails logger is available
          #
          # @param message [String] The message to log
          def debug(message)
            return unless defined?(Rails) && Rails.logger

            Rails.logger.debug("[RubyLLM::Agents::Pipeline] #{message}")
          end

          # Log an error message if Rails logger is available
          #
          # @param message [String] The message to log
          def error(message)
            return unless defined?(Rails) && Rails.logger

            Rails.logger.error("[RubyLLM::Agents::Pipeline] #{message}")
          end
        end
      end
    end
  end
end
