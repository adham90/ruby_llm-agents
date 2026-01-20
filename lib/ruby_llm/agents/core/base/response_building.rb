# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Result object construction from LLM responses
      #
      # Handles building Result objects with full execution metadata
      # including tokens, costs, timing, and tool calls.
      module ResponseBuilding
        # Builds a Result object from processed content and response metadata
        #
        # @param content [Hash, String] The processed response content
        # @param response [RubyLLM::Message] The raw LLM response
        # @return [Result] A Result object with full execution metadata
        def build_result(content, response)
          completed_at = Time.current
          input_tokens = result_response_value(response, :input_tokens)
          output_tokens = result_response_value(response, :output_tokens)
          response_model_id = result_response_value(response, :model_id)
          thinking_data = result_thinking_data(response)

          Result.new(
            content: content,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            cached_tokens: result_response_value(response, :cached_tokens, 0),
            cache_creation_tokens: result_response_value(response, :cache_creation_tokens, 0),
            model_id: model,
            chosen_model_id: response_model_id || model,
            temperature: temperature,
            started_at: @execution_started_at,
            completed_at: completed_at,
            duration_ms: result_duration_ms(completed_at),
            time_to_first_token_ms: @time_to_first_token_ms,
            finish_reason: result_finish_reason(response),
            streaming: self.class.streaming,
            input_cost: result_input_cost(input_tokens, response_model_id),
            output_cost: result_output_cost(output_tokens, response_model_id),
            total_cost: result_total_cost(input_tokens, output_tokens, response_model_id),
            tool_calls: @accumulated_tool_calls,
            tool_calls_count: @accumulated_tool_calls.size,
            **thinking_data
          )
        end

        # Safely extracts a value from the response object
        #
        # @param response [Object] The response object
        # @param method [Symbol] The method to call
        # @param default [Object] Default value if method doesn't exist
        # @return [Object] The extracted value or default
        def result_response_value(response, method, default = nil)
          return default unless response.respond_to?(method)
          response.send(method) || default
        end

        # Calculates execution duration in milliseconds
        #
        # @param completed_at [Time] When execution completed
        # @return [Integer, nil] Duration in ms or nil
        def result_duration_ms(completed_at)
          return nil unless @execution_started_at
          ((completed_at - @execution_started_at) * 1000).to_i
        end

        # Extracts finish reason from response
        #
        # @param response [Object] The response object
        # @return [String, nil] Normalized finish reason
        def result_finish_reason(response)
          reason = result_response_value(response, :finish_reason) ||
                   result_response_value(response, :stop_reason)
          return nil unless reason

          # Normalize to standard values
          case reason.to_s.downcase
          when "stop", "end_turn" then "stop"
          when "length", "max_tokens" then "length"
          when "content_filter", "safety" then "content_filter"
          when "tool_calls", "tool_use" then "tool_calls"
          else "other"
          end
        end

        # Extracts thinking data from response
        #
        # Handles different response structures from various providers.
        # The thinking object typically has text, signature, and tokens.
        #
        # @param response [Object] The response object
        # @return [Hash] Thinking data (empty if none present)
        def result_thinking_data(response)
          thinking = result_response_value(response, :thinking)
          return {} unless thinking

          {
            thinking_text: thinking.respond_to?(:text) ? thinking.text : thinking[:text],
            thinking_signature: thinking.respond_to?(:signature) ? thinking.signature : thinking[:signature],
            thinking_tokens: thinking.respond_to?(:tokens) ? thinking.tokens : thinking[:tokens]
          }.compact
        end
      end
    end
  end
end
