# frozen_string_literal: true

# ResearcherAgent - Researches topics for the supervisor workflow
#
# A delegate agent used by the ResearchWorkflow's supervisor.
# Called via DelegateTool when the orchestrator needs research done.
#
# @example
#   result = Workflows::ResearcherAgent.call(input: "quantum computing")
#   result.content  # => research notes and key findings
#
module Workflows
  class ResearcherAgent < ApplicationAgent
    description "Researches topics and returns key findings"

    model "gpt-4o-mini"
    temperature 0.3

    system "You are a research specialist. Provide thorough, well-organized research notes with key facts, statistics, and insights."
    user "Research the following topic thoroughly:\n\n{input}"
  end
end
