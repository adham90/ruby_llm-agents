# frozen_string_literal: true

module RubyLLM
  module Agents
    # DSL and execution support for before_call/after_call hooks
    #
    # Provides callbacks that run before and after the LLM call,
    # allowing custom preprocessing (redaction, moderation, validation)
    # and postprocessing (logging, transformation) logic.
    #
    # @example Using callbacks
    #   class MyAgent < ApplicationAgent
    #     before_call :sanitize_input
    #     after_call :log_response
    #
    #     # Or with blocks
    #     before_call { |context| context.params[:timestamp] = Time.current }
    #     after_call { |context, response| notify(response) }
    #
    #     private
    #
    #     def sanitize_input(context)
    #       # Mutate context as needed
    #       # Raise to block execution
    #     end
    #
    #     def log_response(context, response)
    #       Rails.logger.info("Response: #{response}")
    #     end
    #   end
    #
    module CallbacksDSL
      # Add a callback to run before the LLM call
      #
      # Callbacks receive the pipeline context and can:
      # - Mutate the context (params, prompts, etc.)
      # - Raise an exception to block execution
      # - Return value is ignored
      #
      # @param method_name [Symbol, nil] Instance method to call
      # @yield [context] Block to execute
      # @yieldparam context [Pipeline::Context] The execution context
      # @return [void]
      #
      # @example With method name
      #   before_call :validate_input
      #
      # @example With block
      #   before_call { |context| context.params[:sanitized] = true }
      #
      def before_call(method_name = nil, &block)
        @callbacks ||= { before: [], after: [] }
        @callbacks[:before] << (block || method_name)
      end

      # Add a callback to run after the LLM call
      #
      # Callbacks receive the pipeline context and the response.
      # Return value is ignored.
      #
      # @param method_name [Symbol, nil] Instance method to call
      # @yield [context, response] Block to execute
      # @yieldparam context [Pipeline::Context] The execution context
      # @yieldparam response [Object] The LLM response
      # @return [void]
      #
      # @example With method name
      #   after_call :log_response
      #
      # @example With block
      #   after_call { |context, response| notify_completion(response) }
      #
      def after_call(method_name = nil, &block)
        @callbacks ||= { before: [], after: [] }
        @callbacks[:after] << (block || method_name)
      end

      # Get all registered callbacks
      #
      # @return [Hash] Hash with :before and :after arrays
      def callbacks
        @callbacks ||= { before: [], after: [] }
      end
    end

    # Instance methods for running callbacks
    module CallbacksExecution
      private

      # Run callbacks of the specified type
      #
      # @param type [Symbol] :before or :after
      # @param args [Array] Arguments to pass to callbacks
      # @return [void]
      def run_callbacks(type, *args)
        callbacks = self.class.callbacks[type] || []

        callbacks.each do |callback|
          case callback
          when Symbol
            send(callback, *args)
          when Proc
            instance_exec(*args, &callback)
          end
        end
      end
    end
  end
end
