# frozen_string_literal: true

# SupportRouter - Classify and route incoming support messages
#
# Routes customer support messages to the appropriate handler agent based on
# content analysis. Uses a lightweight classification prompt with low
# temperature for deterministic results.
#
# When a route has an `agent:` mapping, the router automatically classifies
# the message and then invokes that agent, returning the agent's response.
# Routes without `agent:` just classify and return the route symbol.
#
# Use cases:
# - Customer support ticket triage with auto-dispatch
# - Helpdesk message routing
# - Chat-based support classification
#
# @example Auto-delegation (with agent mapping)
#   result = Routers::SupportRouter.call(message: "I was charged twice")
#   result.route            # => :billing
#   result.delegated?       # => true
#   result.delegated_to     # => BillingAgent (if mapped)
#   result.content          # => BillingAgent's response
#   result.routing_cost     # => cost of classification only
#   result.total_cost       # => classification + delegation
#
# @example Classification only (routes without agent:)
#   result = Routers::SupportRouter.call(message: "What plans do you offer?")
#   result.route        # => :sales
#   result.delegated?   # => false
#
# @example With tenant tracking
#   result = Routers::SupportRouter.call(
#     message: "My app keeps crashing",
#     tenant: organization
#   )
#   result.route  # => :technical
#
module Routers
  class SupportRouter < ApplicationAgent
    include RubyLLM::Agents::Routing

    description "Classifies support messages and auto-delegates to handler agents"

    model "gpt-4o-mini"
    temperature 0.0

    # Routes with agent: mapping auto-delegate after classification.
    # Routes without agent: just classify and return the route symbol.
    route :billing, "Billing, invoices, charges, refunds, payment methods"
    route :technical, "Bugs, errors, crashes, performance issues, technical support"
    route :sales, "Pricing, plans, upgrades, discounts, enterprise inquiries"
    route :account, "Password resets, profile changes, account settings"
    default_route :general
  end
end
