# frozen_string_literal: true

# Example Sequential Workflow using the new DSL
# Processes content through sequential steps: extract -> classify -> format
#
# Demonstrates:
#   - Sequential pipeline steps with input mapping
#   - Retry configuration with exponential and linear backoff
#   - Retry with integer shorthand and error class filtering
#   - Custom block step for inline logic
#   - Conditional steps with unless:
#   - pick: for selecting specific fields from previous steps
#   - Parallel quality checks with timeout
#   - on_step_error, on_step_failure, and after_workflow lifecycle hooks
#   - on_error: step-level error handler
#   - critical: flag for non-critical steps
#   - Block flow control: skip!, halt!, fail!
#
# Usage:
#   result = ContentPipelineWorkflow.call(text: "Your content here")
#   result.steps[:extract].content   # Extracted data
#   result.steps[:classify].content  # Classification result
#   result.steps[:format].content    # Formatted output
#   result.total_cost                # Total cost of all steps
#
class ContentPipelineWorkflow < RubyLLM::Agents::Workflow
  description 'Processes content through extraction, classification, and formatting'
  version '2.0'
  timeout 2.minutes
  max_cost 1.00

  input do
    required :text, String
    optional :format_style, String, default: 'markdown'
    optional :skip_formatting, :boolean, default: false
  end

  # Retry with error class filtering and linear backoff
  step :extract, ExtractorAgent, 'Extract main points and entities',
       timeout: 45.seconds,
       retry: { max: 3, on: [Timeout::Error, Net::ReadTimeout], backoff: :linear, delay: 2 }

  # Validation step with on_error handler (non-critical)
  step :validate, ValidatorAgent, 'Validate extracted data',
       critical: false,
       on_error: ->(error) { Rails.logger.warn "Validation skipped: #{error.message}" },
       optional: true,
       input: -> { { data: extract.to_h } }

  # Retry with integer shorthand
  step :classify, ClassifierAgent, 'Classify content type',
       retry: 2,
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

  # Parallel with timeout
  parallel :quality_checks, fail_fast: false, timeout: 60.seconds do
    step :grammar, GrammarAgent, optional: true
    step :readability, ReadabilityAgent, optional: true
  end

  step :format, FormatterAgent, 'Format for output',
       unless: -> { input.skip_formatting },
       pick: %i[content classification],
       from: :enrich,
       optional: true,
       default: { formatted: false }

  # Block with flow control demonstrations
  step :finalize do
    # skip! - Skip this step with a default value
    skip!(reason: 'Spam content detected', default: { skipped: true, reason: 'spam' }) if classify.category == 'spam'

    # fail! - Abort the workflow with an error
    fail!('No content extracted - cannot finalize') if extract.content.blank?

    # halt! - Stop workflow early with a successful result
    if quality_checks.readability&.score.to_f > 90
      halt!(result: { status: 'excellent', fast_tracked: true, quality_score: 90 })
    end

    # Normal completion
    {
      processed: true,
      quality: quality_checks.to_h,
      final_format: format&.to_h
    }
  end

  on_step_error do |step_name, error|
    Rails.logger.error "Pipeline step #{step_name} failed: #{error.message}"
  end

  on_step_failure :extract do |_step_name, error, _step_results|
    Rails.logger.error "Extraction failed after retries: #{error.message}"
    # Could trigger notification or fallback logic
  end

  after_workflow do
    Rails.logger.info "Pipeline completed with status: #{result.status}"
  end
end
