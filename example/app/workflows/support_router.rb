# frozen_string_literal: true

# Example Routing Workflow using the new DSL
# Routes customer messages to specialized agents based on intent
#
# Usage:
#   result = SupportRouter.call(message: "I was charged twice")
#   result.steps[:classify].content  # Classification details (e.g., { category: "billing" })
#   result.steps[:handle].content    # Response from routed agent
#   result.content                   # Final workflow output
#
class SupportRouter < RubyLLM::Agents::Workflow
  description "Routes customer messages to specialized support agents based on intent"
  version "1.0"

  input do
    required :message, String
  end

  step :classify, ClassifierAgent

  step :handle, on: -> { classify.category } do |route|
    route.billing BillingAgent
    route.technical TechnicalAgent
    route.default GeneralAgent
  end
end
