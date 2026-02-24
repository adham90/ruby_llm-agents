# frozen_string_literal: true

# ResearchWorkflow - Supervisor loop workflow
#
# Demonstrates the supervisor pattern where an orchestrator agent loops,
# delegating work to specialist sub-agents until it signals completion.
# The orchestrator's LLM decides which agent to call on each turn.
#
# This pattern is useful for open-ended tasks where the number of steps
# isn't known in advance — the supervisor decides when enough work has
# been done and calls complete.
#
# @example Basic usage
#   result = Workflows::ResearchWorkflow.call(topic: "Quantum computing")
#   result.success?       # => true
#   result.total_cost     # => combined cost of all delegations
#   result.content        # => final result from the supervisor
#
# @example With max turns limit
#   # The workflow stops after 5 turns even if the supervisor
#   # hasn't called complete (prevents infinite loops)
#
module Workflows
  class ResearchWorkflow < ApplicationWorkflow
    description "Supervisor-driven research with researcher and writer agents"

    # The orchestrator agent drives the loop
    supervisor Workflows::OrchestratorAgent, max_turns: 5

    # Sub-agents available for delegation
    delegate :researcher, Workflows::ResearcherAgent
    delegate :writer, Workflows::WriterAgent
  end
end
