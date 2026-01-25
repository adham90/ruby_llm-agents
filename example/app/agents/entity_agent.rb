# frozen_string_literal: true

require_relative "concerns/loggable"
require_relative "concerns/measurable"

# EntityAgent - Extracts named entities from text
#
# Used by ContentAnalyzerWorkflow to extract entities like
# people, places, organizations, dates, etc. from content.
#
# Example usage:
#
#   agent = EntityAgent.new(text: "Apple CEO Tim Cook announced...")
#   result = agent.call
#   # => { entities: [{ type: "ORGANIZATION", name: "Apple" }, ...] }
#
class EntityAgent < ApplicationAgent
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description "Extracts named entities (people, places, organizations, dates) from text"
  model "gpt-4o-mini"
  temperature 0.0

  log_level :info
  log_format :simple
  log_include :duration, :tokens

  param :text, required: true

  def system_prompt
    <<~PROMPT
      You are a named entity recognition assistant. Extract entities from text and categorize them.
      Return entities as a structured list with type and name for each entity.
      Entity types include: PERSON, ORGANIZATION, LOCATION, DATE, MONEY, PRODUCT, EVENT.
    PROMPT
  end

  def user_prompt
    "Extract all named entities from this text:\n\n#{text}"
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
