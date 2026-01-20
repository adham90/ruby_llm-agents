# frozen_string_literal: true

require_relative "base/moderation_dsl"
require_relative "base/moderation_execution"

module RubyLLM
  module Agents
    # Base class for LLM-powered conversational agents
    #
    # Inherits from BaseAgent to use the middleware pipeline architecture
    # while adding moderation capabilities for input/output content filtering.
    #
    # @example Creating an agent
    #   class SearchAgent < ApplicationAgent
    #     model "gpt-4o"
    #     temperature 0.0
    #     version "1.0"
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
    # @example With moderation
    #   class SafeAgent < ApplicationAgent
    #     moderation :input, :output
    #     # or
    #     moderation :both
    #
    #     def user_prompt
    #       query
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
      extend ModerationDSL
      include ModerationExecution

      class << self
        # Returns the agent type for conversation agents
        #
        # @return [Symbol] :conversation
        def agent_type
          :conversation
        end
      end

      # Execute the core LLM call with moderation support
      #
      # This extends BaseAgent's execute method to add input and output
      # moderation checks when configured via the moderation DSL.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the result
      def execute(context)
        @execution_started_at = context.started_at || Time.current

        # Input moderation check (before LLM call)
        if self.class.moderation_enabled? && should_moderate?(:input)
          input_text = build_moderation_input
          moderate_input(input_text)

          if moderation_blocked?
            context.output = build_moderation_blocked_result(:input)
            return
          end
        end

        # Execute the LLM call via parent
        client = build_client
        response = execute_llm_call(client, context)
        capture_response(response, context)
        processed_content = process_response(response)

        # Output moderation check (after LLM call)
        if self.class.moderation_enabled? && should_moderate?(:output)
          output_text = processed_content.is_a?(String) ? processed_content : processed_content.to_s
          moderate_output(output_text)

          if moderation_blocked?
            context.output = build_moderation_blocked_result(:output)
            return
          end
        end

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

      private

      # Check if execution model is available for moderation tracking
      #
      # @return [Boolean] true if Execution model can be used
      def execution_model_available?
        return @execution_model_available if defined?(@execution_model_available)

        @execution_model_available = begin
          RubyLLM::Agents::Execution.table_exists?
        rescue StandardError
          false
        end
      end
    end
  end
end

# Load moderation modules after class is defined (they reopen the class)
require_relative "base/moderation_dsl"
require_relative "base/moderation_execution"
