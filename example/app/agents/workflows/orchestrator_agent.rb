# frozen_string_literal: true

# OrchestratorAgent - Supervisor agent for research workflows
#
# This agent acts as the supervisor in a supervisor-loop workflow.
# It receives DelegateTool and CompleteTool automatically, and uses
# them to delegate work to sub-agents (researcher, writer) and signal
# completion when the task is done.
#
# The supervisor's LLM decides on each turn whether to delegate to
# a sub-agent or call complete with the final result.
#
# @example Used by ResearchWorkflow
#   # The supervisor decides: research first, then write, then complete
#   # Turn 1: delegate(agent: "researcher", input: "quantum computing basics")
#   # Turn 2: delegate(agent: "writer", input: "write article from research")
#   # Turn 3: complete(result: "final article content")
#
module Workflows
  class OrchestratorAgent < ApplicationAgent
    description "Orchestrates research tasks by delegating to specialist agents"

    model "gpt-4o"
    temperature 0.3

    system <<~PROMPT
      You are a research project manager. Your job is to coordinate
      specialist agents to produce high-quality research content.

      You have access to these agents via the delegate tool:
      - researcher: Researches topics and gathers information
      - writer: Writes polished content from research notes

      Workflow:
      1. First, delegate to the researcher to gather information
      2. Then, delegate to the writer to produce the final content
      3. Finally, call complete with the finished result

      Always delegate to researcher first before the writer.
    PROMPT
  end
end
