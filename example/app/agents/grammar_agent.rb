# frozen_string_literal: true

require_relative "concerns/loggable"
require_relative "concerns/measurable"

# GrammarAgent - Checks text for grammar and spelling issues
#
# Used by ContentPipelineWorkflow to perform quality checks
# on content before formatting.
#
# Example usage:
#
#   agent = GrammarAgent.new(text: "Their going to the store.")
#   result = agent.call
#   # => { issues: [{ type: "grammar", text: "Their", suggestion: "They're" }], score: 0.8 }
#
class GrammarAgent < ApplicationAgent
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description "Checks text for grammar, spelling, and punctuation issues"
  model "gpt-4o-mini"
  temperature 0.0

  log_level :info
  log_format :simple
  log_include :duration, :tokens

  param :text, required: true

  def system_prompt
    <<~PROMPT
      You are a grammar and spelling checker. Analyze text for:
      - Grammar errors
      - Spelling mistakes
      - Punctuation issues
      - Word choice problems

      Return a structured response with:
      - A list of issues found (type, text, suggestion)
      - An overall grammar score from 0.0 to 1.0
    PROMPT
  end

  def user_prompt
    "Check this text for grammar and spelling issues:\n\n#{text}"
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
