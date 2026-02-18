# frozen_string_literal: true

# SupportRouter - Classify incoming support messages
#
# Routes customer support messages to the appropriate handler based on
# content analysis. Uses a lightweight classification prompt with low
# temperature for deterministic results.
#
# Use cases:
# - Customer support ticket triage
# - Helpdesk message routing
# - Chat-based support classification
#
# @example Basic usage
#   result = Routers::SupportRouter.call(message: "I was charged twice")
#   result.route        # => :billing
#   result.agent_class  # => nil
#   result.total_cost   # => 0.00008
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

    description "Classifies support messages into billing, technical, sales, or general"

    model "gpt-4o-mini"
    temperature 0.0

    route :billing, "Billing, invoices, charges, refunds, payment methods"
    route :technical, "Bugs, errors, crashes, performance issues, technical support"
    route :sales, "Pricing, plans, upgrades, discounts, enterprise inquiries"
    route :account, "Password resets, profile changes, account settings"
    default_route :general
  end
end
