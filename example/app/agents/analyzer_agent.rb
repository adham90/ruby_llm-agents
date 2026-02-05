# frozen_string_literal: true

require_relative "concerns/loggable"
require_relative "concerns/measurable"

# AnalyzerAgent - Analyzes support request intent and category
#
# Used by SupportRouterWorkflow to determine the category
# of incoming support requests for routing.
#
# Example usage:
#
#   result = AnalyzerAgent.call(message: "I was charged twice for my subscription")
#   result.content  # => { category: "billing", confidence: 0.95, intent: "refund_request" }
#
class AnalyzerAgent < ApplicationAgent
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description "Analyzes support request intent and determines routing category"
  model "gpt-4o-mini"
  temperature 0.0

  log_level :info
  log_format :simple
  log_include :duration, :tokens

  # Prompts using simplified DSL
  system <<~PROMPT
    You are a support request analyzer. Categorize incoming messages into one of:
    - billing: Payment issues, charges, refunds, invoices, subscription changes
    - technical: Bugs, errors, crashes, performance issues, how-to questions
    - account: Login issues, profile changes, password resets, account settings
    - general: Everything else
  PROMPT

  prompt "Analyze this support request and determine its category:\n\n{message}"

  # Structured output
  returns do
    string :category, enum: %w[billing technical account general], description: "The request category"
    number :confidence, description: "Confidence level from 0.0 to 1.0"
    string :intent, description: "Brief description of what the user wants"
  end

  # Override call to integrate concerns
  def call
    measure_execution do
      log_before_execution(message)
      record_metric(:message_length, message.length)

      result = super

      log_after_execution(result, started_at: @execution_started_at)
      result
    end
  end
end
