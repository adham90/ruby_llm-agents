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
#   result = SchemaAgent.call(text: "I love this product! It's amazing.")
#   result  # => { summary: "...", sentiment: "positive", ... }
#
# @example Access structured fields
#   result = SchemaAgent.call(text: "The weather is okay today.")
#   result[:sentiment]          # => "neutral"
#   result[:confidence]         # => 0.85
#   result[:keywords]           # => ["weather", "today"]
#   result[:metadata][:language] # => "en"
#
class SchemaAgent < ApplicationAgent
  description 'Demonstrates structured output with schema validation'
  version '1.0'

  model 'gpt-4o-mini'
  temperature 0.0 # Deterministic for consistent structured output
  timeout 30

  param :text, required: true

  schema do
    string :summary, description: 'Brief summary of the text (1-2 sentences)'
    string :sentiment, enum: %w[positive negative neutral mixed], description: 'Overall sentiment'
    number :confidence, description: 'Confidence score between 0 and 1'
    array :keywords, of: :string, description: 'Key words and phrases from the text'
    object :metadata do
      integer :word_count, description: 'Number of words in the text'
      string :language, description: "ISO 639-1 language code (e.g., 'en', 'es')"
      boolean :contains_questions, description: 'Whether the text contains questions'
    end
  end

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

  def execution_metadata
    {
      showcase: 'schema',
      features: %w[schema structured_output json_response]
    }
  end
end
