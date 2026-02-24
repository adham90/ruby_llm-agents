# frozen_string_literal: true

# SupportWorkflow - Conditional routing workflow
#
# Demonstrates dispatch routing where a classification step determines
# which specialist agent handles the request. The SupportClassifier
# routes messages to billing, technical, or general support agents.
#
# This pattern is useful for customer support triage, intent-based
# routing, and any scenario where different inputs need different
# processing paths.
#
# @example Basic usage
#   result = Workflows::SupportWorkflow.call(message: "I was charged twice")
#   result.step(:classify).route      # => :billing (from RoutingResult)
#   result.step(:handler).content     # => BillingAgent's response
#   result.total_cost                 # => cost of classify + handler
#
# @example Technical issue
#   result = Workflows::SupportWorkflow.call(message: "App keeps crashing")
#   result.step(:classify).route      # => :technical
#   result.step(:handler).content     # => TechnicalAgent's response
#
# @example General inquiry (default route)
#   result = Workflows::SupportWorkflow.call(message: "Hello!")
#   result.step(:classify).route      # => :general
#   result.step(:handler).content     # => GeneralAgent's response
#
module Workflows
  class SupportWorkflow < ApplicationWorkflow
    description "Route support tickets to specialized agents based on classification"

    # Step 1: Classify the incoming message
    step :classify, Workflows::SupportClassifier

    # Step 2: Dispatch to the appropriate specialist
    dispatch :classify do |d|
      d.on :billing, agent: Workflows::BillingAgent
      d.on :technical, agent: Workflows::TechnicalAgent
      d.on_default agent: Workflows::GeneralAgent
    end
  end
end
