# frozen_string_literal: true

# StreamingAgent - Demonstrates streaming mode
#
# This agent showcases streaming responses:
# - Tokens are yielded as they arrive
# - Great for long responses or real-time UIs
# - Time to first token tracked
#
# @example Basic streaming with block
#   StreamingAgent.call(query: "Tell me a story") do |chunk|
#     print chunk.content
#   end
#
# @example Explicit stream method
#   result = StreamingAgent.stream(query: "Tell me a story") do |chunk|
#     print chunk.content
#   end
#   puts "\nTotal tokens: #{result.total_tokens}"
#
# @example Non-streaming (collects all tokens)
#   result = StreamingAgent.call(query: "Tell me a story")
#   puts result.content
#
class StreamingAgent < ApplicationAgent
  description "Demonstrates streaming responses for real-time output"
  version "1.0"

  model "gpt-4o-mini"
  temperature 0.8  # Higher temperature for creative responses
  timeout 60

  # Enable streaming mode
  # When a block is passed to call, chunks are yielded as they arrive
  streaming true

  param :query, required: true

  def system_prompt
    <<~PROMPT
      You are a creative storyteller and writer. When asked questions,
      provide detailed, engaging responses. Feel free to be creative
      and elaborate when appropriate.
    PROMPT
  end

  def user_prompt
    query
  end

  def execution_metadata
    {
      showcase: "streaming",
      features: %w[streaming time_to_first_token]
    }
  end
end
