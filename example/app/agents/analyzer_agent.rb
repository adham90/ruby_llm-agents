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
#   agent = AnalyzerAgent.new(message: "I was charged twice for my subscription")
#   result = agent.call
#   # => { category: "billing", confidence: 0.95, intent: "refund_request" }
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

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a support request analyzer. Categorize incoming messages into one of:
      - billing: Payment issues, charges, refunds, invoices, subscription changes
      - technical: Bugs, errors, crashes, performance issues, how-to questions
      - account: Login issues, profile changes, password resets, account settings
      - general: Everything else

      Return a structured response with:
      - category: One of the categories above
      - confidence: Your confidence level (0.0 to 1.0)
      - intent: A brief description of what the user wants
    PROMPT
  end

  def user_prompt
    "Analyze this support request and determine its category:\n\n#{message}"
  end

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
