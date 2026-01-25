# frozen_string_literal: true

# Example Routing Workflow using the new DSL
# Routes customer messages to specialized agents based on intent
#
# Demonstrates:
#   - Routing patterns with on: condition
#   - Per-route configuration (input mapping, timeout, fallback)
#   - Conditional routes with if:
#   - Fallback agents for error handling
#   - Sequential steps before and after routing
#
# Usage:
#   result = SupportRouterWorkflow.call(message: "I was charged twice")
#   result.steps[:analyze].content  # Analysis details (e.g., { category: "billing" })
#   result.steps[:handle].content   # Response from routed agent
#   result.content                  # Final workflow output
#
class SupportRouterWorkflow < RubyLLM::Agents::Workflow
  description "Routes support requests to specialized agents"
  version "2.0"
  timeout 3.minutes
  max_cost 2.00

  input do
    required :message, String
    optional :customer_tier, String, default: "standard"
    optional :previous_context, String
  end

  step :analyze, AnalyzerAgent, "Analyze request intent",
    timeout: 30.seconds

  step :handle, on: -> { analyze.category } do |route|
    route.billing BillingAgent,
      input: -> { { issue: input.message, tier: input.customer_tier } },
      timeout: 2.minutes

    route.technical TechnicalAgent,
      input: -> { { problem: input.message, context: input.previous_context } },
      fallback: GeneralAgent

    route.account AccountAgent,
      if: -> { input.customer_tier != "free" }

    route.default GeneralAgent,
      input: -> { { query: input.message } }
  end

  step :followup, FollowupAgent, "Generate follow-up suggestions",
    optional: true,
    input: -> { { response: handle.to_h, original: input.message } }
end
