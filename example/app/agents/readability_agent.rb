# frozen_string_literal: true

require_relative "concerns/loggable"
require_relative "concerns/measurable"

# ReadabilityAgent - Analyzes text readability and complexity
#
# Used by ContentPipelineWorkflow to perform quality checks
# on content before formatting.
#
# Example usage:
#
#   agent = ReadabilityAgent.new(text: "The quick brown fox...")
#   result = agent.call
#   # => { score: 72.5, grade_level: "7th grade", suggestions: [...] }
#
class ReadabilityAgent < ApplicationAgent
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description "Analyzes text readability, complexity, and accessibility"
  model "gpt-4o-mini"
  temperature 0.0

  log_level :info
  log_format :simple
  log_include :duration, :tokens

  param :text, required: true

  def system_prompt
    <<~PROMPT
      You are a readability analysis assistant. Evaluate text for:
      - Reading difficulty level (grade level)
      - Sentence complexity
      - Vocabulary accessibility
      - Overall readability score (0-100, like Flesch-Kincaid)

      Return a structured response with:
      - Readability score (0-100)
      - Estimated grade level
      - Suggestions for improvement
    PROMPT
  end

  def user_prompt
    "Analyze the readability of this text:\n\n#{text}"
  end

  def call
    measure_execution do
      log_before_execution(text)
      record_metric(:text_length, text.length)

      result = super

      log_after_execution(result, started_at: @execution_started_at)
      result
    end
  end
end
