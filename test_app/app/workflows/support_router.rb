# frozen_string_literal: true

# Example Router Workflow
# Routes customer messages to specialized agents based on intent
#
# Usage:
#   result = SupportRouter.call(message: "I was charged twice")
#   result.routed_to         # :billing, :technical, or :default
#   result.classification    # Classification details
#   result.content           # Response from routed agent
#
class SupportRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"
  classifier_temperature 0.0

  route :billing,   to: BillingAgent,   description: "Billing questions, charges, refunds, invoices"
  route :technical, to: TechnicalAgent, description: "Technical issues, bugs, errors, crashes"
  route :default,   to: GeneralAgent

  # Transform input before routing to agent
  def before_route(input, chosen_route)
    input.merge(
      routed_at: Time.current,
      route_context: chosen_route
    )
  end
end
