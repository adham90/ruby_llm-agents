# frozen_string_literal: true

# SchemaAgent::Eval - Quality checks for the text analysis agent
#
# Verifies that the schema agent produces sensible sentiment analysis
# and extracts relevant keywords. Uses multiple scoring strategies:
# exact match for sentiment, contains for keywords, and a custom
# lambda for confidence ranges.
#
# Run with:
#
#   RUN_EVAL=1 bundle exec rspec spec/evals/schema_agent_eval_spec.rb
#
# Or programmatically:
#
#   run = Evals::SchemaAgentEval.run!
#   puts run.summary
#
module Evals
  class SchemaAgentEval < RubyLLM::Agents::Eval::EvalSuite
    agent SchemaAgent

    # --- Sentiment accuracy (exact match on structured output) ---
    test_case "positive sentiment",
      input: {text: "I absolutely love this product! Best purchase I've ever made."},
      score: ->(result, _expected) {
        content = result.respond_to?(:content) ? result.content : result
        content.is_a?(Hash) && content[:sentiment] == "positive"
      }

    test_case "negative sentiment",
      input: {text: "This is terrible. Completely broken and waste of money."},
      score: ->(result, _expected) {
        content = result.respond_to?(:content) ? result.content : result
        content.is_a?(Hash) && content[:sentiment] == "negative"
      }

    test_case "neutral sentiment",
      input: {text: "The package arrived on Tuesday. It weighs about 2 pounds."},
      score: ->(result, _expected) {
        content = result.respond_to?(:content) ? result.content : result
        content.is_a?(Hash) && content[:sentiment] == "neutral"
      }

    # --- Keyword extraction (contains scorer) ---
    test_case "extracts relevant keywords",
      input: {text: "Ruby on Rails is a web framework written in the Ruby programming language."},
      score: ->(result, _expected) {
        content = result.respond_to?(:content) ? result.content : result
        return false unless content.is_a?(Hash) && content[:keywords].is_a?(Array)

        keywords = content[:keywords].map(&:downcase)
        keywords.any? { |k| k.include?("ruby") }
      }

    # --- Confidence is reasonable ---
    test_case "confidence in valid range",
      input: {text: "I love sunny days at the beach."},
      score: ->(result, _expected) {
        content = result.respond_to?(:content) ? result.content : result
        return false unless content.is_a?(Hash)

        confidence = content[:confidence]
        confidence.is_a?(Numeric) && confidence >= 0.0 && confidence <= 1.0
      }
  end
end
