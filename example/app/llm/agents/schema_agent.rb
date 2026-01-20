# frozen_string_literal: true

# SchemaAgent - Demonstrates structured output with schema DSL
#
# This agent showcases structured output:
# - Schema defines expected JSON structure
# - Supports string, number, integer, boolean
# - Arrays and nested objects supported
# - Enum constraints for limited values
#
# The schema ensures consistent, parseable output regardless
# of how the question is phrased.
#
# @example Basic usage
#   result = Llm::SchemaAgent.call(text: "I love this product! It's amazing.")
#   result  # => { summary: "...", sentiment: "positive", ... }
#
# @example Access structured fields
#   result = Llm::SchemaAgent.call(text: "The weather is okay today.")
#   result[:sentiment]          # => "neutral"
#   result[:confidence]         # => 0.85
#   result[:keywords]           # => ["weather", "today"]
#   result[:metadata][:language] # => "en"
#
module Llm
  class SchemaAgent < ApplicationAgent
    description "Demonstrates structured output with schema validation"
    version "1.0"

    model "gpt-4o-mini"
    temperature 0.0  # Deterministic for consistent structured output
    timeout 30

    param :text, required: true

    def system_prompt
      <<~PROMPT
        You are a text analysis assistant. Analyze the provided text and return:
        - A brief summary
        - Sentiment classification
        - Confidence score
        - Key words/phrases
        - Metadata about the text

        Be accurate and consistent in your analysis.
      PROMPT
    end

    def user_prompt
      "Analyze this text:\n\n#{text}"
    end

    # Structured output schema as JSON Schema
    # The LLM will return JSON matching this structure
    #
    # Note: You can also use RubyLLM::Schema.create (if available) or
    # any object that responds to to_json_schema for more readable syntax.
    def schema
      {
        type: "object",
        properties: {
          summary: {
            type: "string",
            description: "Brief summary of the text (1-2 sentences)"
          },
          sentiment: {
            type: "string",
            enum: %w[positive negative neutral mixed],
            description: "Overall sentiment"
          },
          confidence: {
            type: "number",
            description: "Confidence score between 0 and 1"
          },
          keywords: {
            type: "array",
            items: { type: "string" },
            description: "Key words and phrases from the text"
          },
          metadata: {
            type: "object",
            properties: {
              word_count: {
                type: "integer",
                description: "Number of words in the text"
              },
              language: {
                type: "string",
                description: "ISO 639-1 language code (e.g., 'en', 'es')"
              },
              contains_questions: {
                type: "boolean",
                description: "Whether the text contains questions"
              }
            },
            required: %w[word_count language contains_questions]
          }
        },
        required: %w[summary sentiment confidence keywords metadata]
      }
    end

    def execution_metadata
      {
        showcase: "schema",
        features: %w[schema structured_output json_response]
      }
    end
  end
end
