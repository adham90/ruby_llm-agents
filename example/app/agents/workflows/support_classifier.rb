# frozen_string_literal: true

# SupportClassifier - Classifies support messages for workflow dispatch
#
# Used as the routing step in the SupportWorkflow.
# Classifies incoming messages so the dispatch DSL can route
# to the appropriate specialist agent.
#
# @example
#   result = Workflows::SupportClassifier.call(message: "I was charged twice")
#   result.route  # => :billing
#
module Workflows
  class SupportClassifier < ApplicationAgent
    include RubyLLM::Agents::Routing

    description "Classifies support messages for workflow dispatch"

    model "gpt-4o-mini"
    temperature 0.0

    route :billing, "Billing, invoices, charges, refunds"
    route :technical, "Bugs, errors, crashes, technical issues"
    default_route :general
  end
end
