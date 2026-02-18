# frozen_string_literal: true

# PriorityRouter - Classify message urgency
#
# Determines the priority level of incoming messages so they can be
# queued appropriately. Cached for 1 hour since identical messages
# should always get the same priority.
#
# Use cases:
# - Support queue prioritization
# - SLA-based ticket routing
# - Alert severity classification
#
# @example Basic usage
#   result = Routers::PriorityRouter.call(message: "Production is down!")
#   result.route  # => :urgent
#
# @example Cached classification
#   result = Routers::PriorityRouter.call(message: "How do I reset my password?")
#   result.route    # => :low
#   result.cached?  # => true (on subsequent calls)
#
module Routers
  class PriorityRouter < ApplicationAgent
    include RubyLLM::Agents::Routing

    description "Classifies message urgency into priority levels"

    model "gpt-4o-mini"
    temperature 0.0
    cache_for 1.hour

    route :urgent, "System outages, data loss, security incidents, production down"
    route :high, "Service degradation, blocking bugs, payment failures"
    route :medium, "Non-blocking bugs, feature requests, general questions"
    route :low, "Documentation requests, feedback, nice-to-haves"
    default_route :medium
  end
end
