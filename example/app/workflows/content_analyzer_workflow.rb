# frozen_string_literal: true

# Example Parallel Workflow using the new DSL
# Analyzes content from multiple perspectives concurrently
#
# Demonstrates:
#   - Parallel execution with fail_fast and timeout options
#   - Optional steps with default values
#   - Input mapping for customizing step inputs
#   - before_workflow lifecycle hook
#   - Conditional steps with if:
#
# Usage:
#   result = ContentAnalyzerWorkflow.call(text: "Your content here")
#   result.steps[:sentiment].content  # Sentiment analysis
#   result.steps[:keywords].content   # Keyword extraction
#   result.steps[:summary].content    # Summary
#   result.total_cost                 # Combined cost
#
class ContentAnalyzerWorkflow < RubyLLM::Agents::Workflow
  description "Analyzes content in parallel for sentiment, keywords, and summary"
  version "2.0"
  timeout 2.minutes
  max_cost 0.50

  input do
    required :text, String
    optional :include_entities, :boolean, default: false
    optional :max_keywords, Integer, default: 5
  end

  before_workflow do
    Rails.logger.info "Starting content analysis for #{input.text.length} chars"
  end

  parallel :analysis, fail_fast: false, timeout: 90.seconds do
    step :sentiment, SentimentAgent,
      optional: true,
      default: { sentiment: "neutral", confidence: 0.0 }

    step :keywords, KeywordAgent,
      input: -> { { text: input.text, max_count: input.max_keywords } }

    step :summary, SummaryAgent,
      timeout: 30.seconds
  end

  step :entities, EntityAgent,
    if: -> { input.include_entities },
    optional: true,
    default: { entities: [] }
end
