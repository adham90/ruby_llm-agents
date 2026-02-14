# frozen_string_literal: true

# FullFeaturedAgent - Demonstrates ALL DSL options combined
#
# This agent showcases every DSL feature using the simplified syntax:
# - Model configuration (model, temperature, timeout)
# - Prompts (system, prompt with {placeholders})
# - Structured output (returns)
# - Caching (cache for:)
# - Streaming (streaming or .stream())
# - Tools (tools)
# - Error handling (on_failure)
# - Callbacks (before, after)
#
# Use this as a reference for the complete agent DSL.
#
# @example Basic usage
#   result = FullFeaturedAgent.call(
#     query: "What's 100 + 50?",
#     context: "math tutoring session",
#     include_analysis: true
#   )
#
# @example With conversation history
#   result = FullFeaturedAgent.call(
#     query: "Continue from before",
#     history: [
#       { role: "user", content: "Hi" },
#       { role: "assistant", content: "Hello!" }
#     ]
#   )
#
# @example Streaming
#   FullFeaturedAgent.stream(query: "Tell me a story") do |chunk|
#     print chunk.content
#   end
#
class FullFeaturedAgent < ApplicationAgent
  # ===========================================
  # Model Configuration
  # ===========================================
  model "gpt-4o"
  description "Complete showcase of all agent DSL features - the kitchen sink agent"
  temperature 0.5
  timeout 60

  # ===========================================
  # Prompts (Simplified DSL)
  # ===========================================
  # System prompt can be a string or heredoc
  system <<~PROMPT
    You are a highly capable AI assistant demonstrating all available features.
    Context: {context}

    You have access to tools for calculations and weather information.
    Use them when appropriate.

    Keep responses under {max_length} words unless necessary.
  PROMPT

  # User prompt with {placeholder} syntax - params are auto-registered
  prompt "{query}"

  # Override auto-detected params with defaults
  param :context, default: "general assistance"
  param :max_length, default: 500
  param :history, default: []
  param :include_analysis, default: false

  # ===========================================
  # Structured Output (when include_analysis: true)
  # ===========================================
  # Using traditional schema method for conditional schema
  def schema
    return nil unless include_analysis

    RubyLLM::Schema.create do
      string :answer, description: "The main response to the query"
      object :analysis do
        string :category, enum: %w[factual creative technical conversational], description: "Category of the query"
        number :complexity_score, description: "Query complexity from 0 to 1"
        boolean :used_tools, description: "Whether tools were invoked"
      end
    end
  end

  # ===========================================
  # Caching (Simplified DSL)
  # ===========================================
  cache for: 30.minutes

  # ===========================================
  # Streaming
  # ===========================================
  streaming true

  # ===========================================
  # Tools
  # ===========================================
  tools [CalculatorTool, WeatherTool]

  # ===========================================
  # Error Handling (Simplified DSL)
  # ===========================================
  on_failure do
    retries times: 2, backoff: :exponential, base: 0.5, max_delay: 4.0
    fallback to: ["gpt-4o-mini", "claude-3-haiku-20240307"]
    timeout 90
    circuit_breaker after: 3, within: 30, cooldown: 2.minutes
  end

  # ===========================================
  # Callbacks (Simplified DSL)
  # ===========================================
  before { |ctx| Rails.logger.info("Starting FullFeaturedAgent with query: #{ctx.params[:query]}") }
  after { |ctx, result| Rails.logger.info("Completed with #{result.total_tokens} tokens") }

  # ===========================================
  # Conversation History
  # ===========================================
  def messages
    history.map do |msg|
      {
        role: msg[:role]&.to_sym || msg["role"]&.to_sym,
        content: msg[:content] || msg["content"]
      }
    end
  end

  # ===========================================
  # Response Processing
  # ===========================================
  def process_response(response)
    content = response.content
    return content unless content.is_a?(Hash)

    # Add processing timestamp
    content.transform_keys(&:to_sym).merge(
      processed_at: Time.current.iso8601
    )
  end
end
