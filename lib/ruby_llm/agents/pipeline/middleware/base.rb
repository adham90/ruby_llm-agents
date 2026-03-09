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
          LOG_TAG = "[RubyLLM::Agents::Pipeline]"

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

          # Builds a log prefix with context from the execution
          #
          # Includes agent type, execution ID, and tenant when available
          # so log messages can be traced through the full pipeline.
          #
          # @param context [Context, nil] The execution context
          # @return [String] Formatted log prefix
          def log_prefix(context = nil)
            return LOG_TAG unless context

            parts = [LOG_TAG]
            parts << context.agent_class.name if context.agent_class
            parts << "exec=#{context.execution_id}" if context.execution_id
            parts << "tenant=#{context.tenant_id}" if context.tenant_id
            parts.join(" ")
          end

          # Log a debug message if Rails logger is available
          #
          # @param message [String] The message to log
          # @param context [Context, nil] Optional execution context for structured prefix
          def debug(message, context = nil)
            return unless defined?(Rails) && Rails.logger

            Rails.logger.debug("#{log_prefix(context)} #{message}")
          end

          # Log an error message if Rails logger is available
          #
          # @param message [String] The message to log
          # @param context [Context, nil] Optional execution context for structured prefix
          def error(message, context = nil)
            return unless defined?(Rails) && Rails.logger

            Rails.logger.error("#{log_prefix(context)} #{message}")
          end

          # Traces middleware execution when debug mode is enabled.
          #
          # Wraps a block with timing instrumentation. When tracing is not
          # enabled, yields directly with zero overhead.
          #
          # @param context [Context] The execution context
          # @param action [String, nil] Optional action description
          # @yield The block to trace
          # @return [Object] The block's return value
          def trace(context, action: nil)
            unless context.trace_enabled?
              return yield
            end

            middleware_name = self.class.name&.split("::")&.last || self.class.to_s
            started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = yield
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
            context.add_trace(middleware_name, started_at: Time.current, duration_ms: duration_ms, action: action)
            debug("#{middleware_name} completed in #{duration_ms}ms#{" (#{action})" if action}", context)
            result
          end

          # Log a warning message if Rails logger is available
          #
          # @param message [String] The message to log
          # @param context [Context, nil] Optional execution context for structured prefix
          def warn(message, context = nil)
            return unless defined?(Rails) && Rails.logger

            Rails.logger.warn("#{log_prefix(context)} #{message}")
          end
        end
      end
    end
  end
end
