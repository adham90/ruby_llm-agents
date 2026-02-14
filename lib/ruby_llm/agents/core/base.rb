# frozen_string_literal: true

require_relative "base/callbacks"

module RubyLLM
  module Agents
    # Base class for LLM-powered conversational agents
    #
    # Inherits from BaseAgent to use the middleware pipeline architecture
    # while adding callback hooks for custom preprocessing and postprocessing.
    #
    # @example Creating an agent
    #   class SearchAgent < ApplicationAgent
    #     model "gpt-4o"
    #     temperature 0.0
    #     timeout 30
    #     cache_for 1.hour
    #
    #     param :query, required: true
    #     param :limit, default: 10
    #
    #     def system_prompt
    #       "You are a search assistant..."
    #     end
    #
    #     def user_prompt
    #       "Search for: #{query}"
    #     end
    #   end
    #
    # @example With callbacks
    #   class SafeAgent < ApplicationAgent
    #     before_call :redact_pii
    #     after_call :log_response
    #
    #     private
    #
    #     def redact_pii(context)
    #       # Custom redaction logic
    #     end
    #
    #     def log_response(context, response)
    #       Rails.logger.info("Response received")
    #     end
    #   end
    #
    # @example Calling an agent
    #   SearchAgent.call(query: "red dress")
    #   SearchAgent.call(query: "red dress", dry_run: true)    # Debug mode
    #   SearchAgent.call(query: "red dress", skip_cache: true) # Bypass cache
    #
    # @see RubyLLM::Agents::BaseAgent
    # @api public
    class Base < BaseAgent
      extend CallbacksDSL
      include CallbacksExecution

      class << self
        # Returns the agent type for conversation agents
        #
        # @return [Symbol] :conversation
        def agent_type
          :conversation
        end
      end

      # Execute the core LLM call with callback support
      #
      # This extends BaseAgent's execute method to add before/after
      # callback hooks for custom preprocessing and postprocessing.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the result
      def execute(context)
        @execution_started_at = context.started_at || Time.current

        # Run before_call callbacks
        run_callbacks(:before, context)

        # Execute the LLM call
        client = build_client(context)
        response = execute_llm_call(client, context)
        capture_response(response, context)
        processed_content = process_response(response)

        # Run after_call callbacks
        run_callbacks(:after, context, response)

        context.output = build_result(processed_content, response, context)
      end

      # Returns the resolved tenant ID for tracking
      #
      # @return [String, nil] The tenant identifier
      def resolved_tenant_id
        tenant = resolve_tenant
        return nil unless tenant

        tenant.is_a?(Hash) ? tenant[:id]&.to_s : nil
      end
    end
  end
end
