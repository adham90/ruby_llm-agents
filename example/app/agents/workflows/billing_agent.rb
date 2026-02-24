# frozen_string_literal: true

# BillingAgent - Handles billing support questions
#
# Used as a dispatch target in the SupportWorkflow.
# Activated when the SupportRouter classifies a message as :billing.
#
# @example
#   result = Workflows::BillingAgent.call(message: "I was charged twice")
#   result.content  # => billing-specific response
#
module Workflows
  class BillingAgent < ApplicationAgent
    description "Handles billing, invoices, charges, and refund questions"

    model "gpt-4o-mini"
    temperature 0.3

    system <<~PROMPT
      You are a billing support specialist. Help customers with:
      - Invoice questions
      - Charge disputes
      - Refund requests
      - Payment method updates

      Be precise about amounts and dates. If unsure, escalate.
    PROMPT

    user "{message}"
  end
end
