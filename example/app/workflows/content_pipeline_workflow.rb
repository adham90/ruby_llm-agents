# frozen_string_literal: true

# Example Sequential Workflow using the new DSL
# Processes content through sequential steps: extract -> classify -> format
#
# Demonstrates:
#   - Sequential pipeline steps with input mapping
#   - Retry configuration with exponential backoff
#   - Custom block step for inline logic
#   - Conditional steps with unless:
#   - pick: for selecting specific fields from previous steps
#   - Parallel quality checks within a sequential flow
#   - on_step_error and after_workflow lifecycle hooks
#
# Usage:
#   result = ContentPipelineWorkflow.call(text: "Your content here")
#   result.steps[:extract].content   # Extracted data
#   result.steps[:classify].content  # Classification result
#   result.steps[:format].content    # Formatted output
#   result.total_cost                # Total cost of all steps
#
class ContentPipelineWorkflow < RubyLLM::Agents::Workflow
  description "Processes content through extraction, classification, and formatting"
  version "2.0"
  timeout 2.minutes
  max_cost 1.00

  input do
    required :text, String
    optional :format_style, String, default: "markdown"
    optional :skip_formatting, :boolean, default: false
  end

  step :extract, ExtractorAgent, "Extract main points and entities",
    timeout: 45.seconds,
    retry: { max: 2, backoff: :exponential, delay: 1 }

  step :classify, ClassifierAgent, "Classify content type",
    input: -> { { content: extract.content, entities: extract.entities } }

  step :enrich do
    # Custom block step example
    {
      extracted: extract.to_h,
      classification: classify.category,
      metadata: {
        word_count: input.text.split.size,
        processed_at: Time.current.iso8601
      }
    }
  end

  parallel :quality_checks, fail_fast: false do
    step :grammar, GrammarAgent, optional: true
    step :readability, ReadabilityAgent, optional: true
  end

  step :format, FormatterAgent, "Format for output",
    unless: -> { input.skip_formatting },
    pick: [:content, :classification],
    from: :enrich,
    optional: true,
    default: { formatted: false }

  on_step_error do |step_name, error|
    Rails.logger.error "Pipeline step #{step_name} failed: #{error.message}"
  end

  after_workflow do
    Rails.logger.info "Pipeline completed with status: #{result.status}"
  end
end
