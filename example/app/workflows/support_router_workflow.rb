# frozen_string_literal: true

# Example Routing Workflow using the new DSL
# Routes customer messages to specialized agents based on intent
#
# Demonstrates:
#   - Routing patterns with on: condition
#   - Per-route configuration (input mapping, timeout, fallback)
#   - Multiple fallback chain for resilience
#   - Conditional routes with if:
#   - Default route for unmatched categories
#   - on_step_start lifecycle hook
#   - Sequential steps before and after routing
#   - description: option (alternative to positional)
#
# Usage:
#   result = SupportRouterWorkflow.call(message: "I was charged twice")
#   result.steps[:analyze].content  # Analysis details (e.g., { category: "billing" })
#   result.steps[:handle].content   # Response from routed agent
#   result.content                  # Final workflow output
#
class SupportRouterWorkflow < RubyLLM::Agents::Workflow
  description 'Routes support requests to specialized agents'
  version '2.0'
  timeout 3.minutes
  max_cost 2.00

  input do
    required :message, String
    optional :customer_tier, String, default: 'standard'
    optional :previous_context, String
  end

  on_step_start do |step_name|
    Rails.logger.debug "[SupportRouter] Starting step: #{step_name}"
  end

  step :analyze, AnalyzerAgent,
       description: 'Analyze request intent and categorize',
       timeout: 30.seconds

  step :handle, on: -> { analyze.category } do |route|
    route.billing BillingAgent,
                  input: -> { { issue: input.message, tier: input.customer_tier } },
                  timeout: 2.minutes

    # Multiple fallback chain for resilience
    route.technical TechnicalAgent,
                    input: -> { { problem: input.message, context: input.previous_context } },
                    fallback: [SpecialistAgent, GeneralAgent]

    route.account AccountAgent,
                  if: -> { input.customer_tier != 'free' }

    # Default route for unmatched categories
    route.default GeneralAgent,
                  input: -> { { query: input.message } }
  end

  # Using description: option instead of positional argument
  step :followup, FollowupAgent,
       description: 'Generate follow-up suggestions based on response',
       optional: true,
       input: -> { { response: handle.to_h, original: input.message } }
end
