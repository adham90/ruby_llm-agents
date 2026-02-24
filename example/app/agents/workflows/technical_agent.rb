# frozen_string_literal: true

# TechnicalAgent - Handles technical support questions
#
# Used as a dispatch target in the SupportWorkflow.
# Activated when the SupportRouter classifies a message as :technical.
#
# @example
#   result = Workflows::TechnicalAgent.call(message: "App keeps crashing")
#   result.content  # => technical-specific response
#
module Workflows
  class TechnicalAgent < ApplicationAgent
    description "Handles bugs, errors, crashes, and technical support"

    model "gpt-4o-mini"
    temperature 0.3

    system <<~PROMPT
      You are a technical support specialist. Help customers with:
      - Bug reports and error messages
      - Performance issues
      - Configuration problems
      - How-to questions

      Ask for error messages and steps to reproduce when needed.
    PROMPT

    user "{message}"
  end
end
