# frozen_string_literal: true

# FullFeaturedAgent - Demonstrates ALL DSL options combined
#
# This agent showcases every DSL feature available:
# - Model configuration (model, temperature, timeout)
# - Metadata (version, description)
# - Caching (cache_for)
# - Streaming (streaming)
# - Tools (tools)
# - Reliability (full block)
# - Parameters (param with required, default, type)
# - Template methods (schema, messages, process_response, execution_metadata)
#
# Use this as a reference for the complete agent DSL.
#
# @example Basic usage
#   result = FullFeaturedAgent.call(
#     query: "What's 100 + 50?",
#     context: "math tutoring session",
#     include_metadata: true
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
#   FullFeaturedAgent.call(query: "Tell me a story") do |chunk|
#     print chunk.content
#   end
#
class FullFeaturedAgent < ApplicationAgent
  # ===========================================
  # Model Configuration
  # ===========================================
  model 'gpt-4o'
  temperature 0.5
  timeout 60

  # ===========================================
  # Metadata
  # ===========================================
  version '2.0'
  description 'Complete showcase of all agent DSL features - the kitchen sink agent'

  # ===========================================
  # Caching
  # ===========================================
  cache_for 30.minutes

  # ===========================================
  # Streaming
  # ===========================================
  streaming true

  # ===========================================
  # Tools
  # ===========================================
  tools [CalculatorTool, WeatherTool]

  # ===========================================
  # Reliability Configuration
  # ===========================================
  reliability do
    retries max: 2, backoff: :exponential, base: 0.5, max_delay: 4.0
    fallback_models 'gpt-4o-mini', 'claude-3-haiku-20240307'
    total_timeout 90
    circuit_breaker errors: 3, within: 30, cooldown: 120
  end

  # ===========================================
  # Parameters
  # ===========================================
  param :query, required: true
  param :context, default: 'general assistance'
  param :history, default: []
  param :max_length, default: 500, type: Integer
  param :include_metadata, default: false, type: :boolean

  # ===========================================
  # Template Methods
  # ===========================================

  def system_prompt
    <<~PROMPT
      You are a highly capable AI assistant demonstrating all available features.
      Context: #{context}

      You have access to tools for calculations and weather information.
      Use them when appropriate.

      Keep responses under #{max_length} words unless necessary.
    PROMPT
  end

  def user_prompt
    query
  end

  # Provide conversation history
  def messages
    history.map do |msg|
      {
        role: msg[:role]&.to_sym || msg['role']&.to_sym,
        content: msg[:content] || msg['content']
      }
    end
  end

  # Structured output schema (optional)
  # Returns JSON Schema format when include_metadata is true
  def schema
    return nil unless include_metadata

    {
      type: 'object',
      properties: {
        answer: {
          type: 'string',
          description: 'The main response to the query'
        },
        analysis: {
          type: 'object',
          properties: {
            category: {
              type: 'string',
              enum: %w[factual creative technical conversational],
              description: 'Category of the query'
            },
            complexity_score: {
              type: 'number',
              description: 'Query complexity from 0 to 1'
            },
            used_tools: {
              type: 'boolean',
              description: 'Whether tools were invoked'
            }
          },
          required: %w[category complexity_score used_tools]
        }
      },
      required: %w[answer analysis]
    }
  end

  # Transform the response before returning
  def process_response(response)
    content = response.content
    return content unless content.is_a?(Hash)

    # Add processing timestamp for demonstration
    content.transform_keys(&:to_sym).merge(
      processed_at: Time.current.iso8601
    )
  end

  # Additional metadata for execution tracking
  def execution_metadata
    {
      showcase: 'full_featured',
      features: %w[
        model temperature timeout version description
        cache_for streaming tools reliability
        param schema messages process_response execution_metadata
      ],
      context: context,
      history_length: history.length,
      include_metadata: include_metadata
    }
  end
end
