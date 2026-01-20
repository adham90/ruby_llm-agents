# frozen_string_literal: true

# Example Router Workflow
# Routes customer messages to specialized agents based on intent
#
# Usage:
#   result = Llm::SupportRouter.call(message: "I was charged twice")
#   result.routed_to         # :billing, :technical, or :default
#   result.classification    # Classification details
#   result.content           # Response from routed agent
#
module Llm
  class SupportRouter < RubyLLM::Agents::Workflow::Router
    description "Routes customer messages to specialized support agents based on intent"
    version "1.0"
    classifier_model "gpt-4o-mini"
    classifier_temperature 0.0

    route :billing,   to: Llm::BillingAgent,   description: "Billing questions, charges, refunds, invoices"
    route :technical, to: Llm::TechnicalAgent, description: "Technical issues, bugs, errors, crashes"
    route :default,   to: Llm::GeneralAgent

    # Transform input before routing to agent
    def before_route(input, chosen_route)
      input.merge(
        routed_at: Time.current,
        route_context: chosen_route
      )
    end
  end
end
