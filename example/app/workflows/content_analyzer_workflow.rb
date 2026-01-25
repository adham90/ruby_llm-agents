# frozen_string_literal: true

# Example Parallel Workflow using the new DSL
# Analyzes content from multiple perspectives concurrently
#
# Demonstrates:
#   - Parallel execution with fail_fast, timeout, and concurrency options
#   - Optional steps with default values
#   - Input mapping for customizing step inputs
#   - Input validation with in: and validate:
#   - Output schema validation
#   - before_workflow, before_step, after_step lifecycle hooks
#   - on_step_complete hook for metrics tracking
#   - ui_label: and tags: for step metadata
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
    required :text, String, validate: ->(v) { v.length >= 10 }
    optional :analysis_depth, String, default: "standard", in: %w[basic standard deep]
    optional :include_entities, :boolean, default: false
    optional :max_keywords, Integer, default: 5
  end

  output do
    required :sentiment, Hash
    required :keywords, Array
    required :summary, String
    optional :entities, Array
  end

  before_workflow do
    Rails.logger.info "Starting content analysis for #{input.text.length} chars"
  end

  before_step :sentiment do |step_name|
    Rails.logger.info "[#{step_name}] Starting sentiment analysis"
  end

  after_step do |step_name, result, duration_ms|
    Rails.logger.info "[#{step_name}] Completed in #{duration_ms}ms"
  end

  on_step_complete do |step_name, result, duration_ms|
    # Track metrics - could send to StatsD, Datadog, etc.
    Rails.logger.debug "[Metrics] #{step_name}: #{duration_ms}ms"
  end

  parallel :analysis, fail_fast: false, timeout: 90.seconds, concurrency: 2 do
    step :sentiment, SentimentAgent,
      ui_label: "Analyze Sentiment",
      tags: [:nlp, :analysis],
      optional: true,
      default: { sentiment: "neutral", confidence: 0.0 }

    step :keywords, KeywordAgent,
      ui_label: "Extract Keywords",
      tags: [:nlp, :extraction],
      input: -> { { text: input.text, max_count: input.max_keywords } }

    step :summary, SummaryAgent,
      ui_label: "Generate Summary",
      tags: [:nlp, :summarization],
      timeout: 30.seconds
  end

  step :entities, EntityAgent,
    ui_label: "Extract Entities",
    tags: [:nlp, :ner],
    if: -> { input.include_entities },
    optional: true,
    default: { entities: [] }
end
