# frozen_string_literal: true

require_relative "concerns/loggable"
require_relative "concerns/measurable"

# FollowupAgent - Generates follow-up suggestions after support responses
#
# Used by SupportRouterWorkflow to suggest additional resources
# or actions after the main support response.
#
# Example usage:
#
#   agent = FollowupAgent.new(
#     response: { content: "Here's how to reset your password..." },
#     original: "I can't log in"
#   )
#   result = agent.call
#   # => { suggestions: ["Check spam folder", "Enable 2FA"], resources: [...] }
#
class FollowupAgent < ApplicationAgent
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description "Generates follow-up suggestions and related resources"
  model "gpt-4o-mini"
  temperature 0.5

  log_level :info
  log_format :simple
  log_include :duration, :tokens

  param :response, required: true
  param :original, required: true

  def system_prompt
    <<~PROMPT
      You are a support follow-up assistant. Based on the support response and original query,
      suggest helpful follow-up actions and resources.

      Return a structured response with:
      - suggestions: A list of 2-3 actionable follow-up items
      - resources: Related help articles or documentation links
      - satisfaction_check: A friendly message to check if the issue was resolved
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Original customer question: #{original}

      Support response provided: #{response.is_a?(Hash) ? response.to_json : response}

      Generate helpful follow-up suggestions for this customer.
    PROMPT
  end

  def call
    measure_execution do
      log_before_execution(original)
      record_metric(:original_length, original.length)

      result = super

      log_after_execution(result, started_at: @execution_started_at)
      result
    end
  end
end
