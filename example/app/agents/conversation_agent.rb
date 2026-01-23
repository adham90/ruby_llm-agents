# frozen_string_literal: true

# ConversationAgent - Demonstrates multi-turn conversation handling
#
# This agent showcases the messages template method:
# - Accepts conversation history as a parameter
# - Adds previous messages before the new user message
# - Enables context-aware responses
#
# The messages method returns an array of previous messages
# that are added to the chat before the user_prompt.
#
# @example First message
#   result = Llm::ConversationAgent.call(
#     message: "My name is Alice.",
#     conversation_history: []
#   )
#
# @example Follow-up with context
#   result = Llm::ConversationAgent.call(
#     message: "What's my name?",
#     conversation_history: [
#       { role: "user", content: "My name is Alice." },
#       { role: "assistant", content: "Nice to meet you, Alice!" }
#     ]
#   )
#   # => "Your name is Alice, as you mentioned earlier."
#
# @example Building a conversation
#   history = []
#
#   result = Llm::ConversationAgent.call(message: "Hi!", conversation_history: history)
#   history << { role: "user", content: "Hi!" }
#   history << { role: "assistant", content: result.content }
#
#   result = Llm::ConversationAgent.call(message: "How are you?", conversation_history: history)
#   # Agent remembers the previous exchange
#
module Llm
  class ConversationAgent < ApplicationAgent
    description "Demonstrates multi-turn conversation with message history"
    version "1.0"

    model "gpt-4o-mini"
    temperature 0.7
    timeout 30

    param :message, required: true
    param :conversation_history, default: []

    def system_prompt
      <<~PROMPT
        You are a friendly conversational assistant. Engage naturally with the user
        and remember context from previous messages in the conversation.

        Be helpful, warm, and maintain conversation continuity.
      PROMPT
    end

    # Provide conversation history from parameter
    # These messages are added before user_prompt
    def messages
      conversation_history.map do |msg|
        {
          role: msg[:role]&.to_sym || msg["role"]&.to_sym,
          content: msg[:content] || msg["content"]
        }
      end
    end

    def user_prompt
      message
    end

    def execution_metadata
      {
        showcase: "conversation",
        features: %w[messages conversation_history multi_turn],
        message_count: conversation_history.length
      }
    end
  end
end
