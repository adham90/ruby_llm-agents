# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Tool call tracking for agent executions
      #
      # Handles accumulating and serializing tool calls made during
      # an agent's execution cycle.
      module ToolTracking
        # Resets accumulated tool calls for a new execution
        #
        # @return [void]
        def reset_accumulated_tool_calls!
          @accumulated_tool_calls = []
        end

        # Extracts tool calls from all assistant messages in the conversation
        #
        # RubyLLM handles tool call loops internally. After ask() completes,
        # the conversation history contains all intermediate assistant messages
        # that had tool_calls. This method extracts those tool calls.
        #
        # @param client [RubyLLM::Chat] The chat client with conversation history
        # @return [void]
        def extract_tool_calls_from_client(client)
          return unless client.respond_to?(:messages)

          client.messages.each do |message|
            next unless message.role == :assistant
            next unless message.respond_to?(:tool_calls) && message.tool_calls.present?

            message.tool_calls.each_value do |tool_call|
              @accumulated_tool_calls << serialize_tool_call(tool_call)
            end
          end
        end

        # Serializes a single tool call to a hash
        #
        # @param tool_call [Object] The tool call object
        # @return [Hash] Serialized tool call
        def serialize_tool_call(tool_call)
          if tool_call.respond_to?(:to_h)
            tool_call.to_h.transform_keys(&:to_s)
          else
            {
              "id" => tool_call.id,
              "name" => tool_call.name,
              "arguments" => tool_call.arguments
            }
          end
        end
      end
    end
  end
end
