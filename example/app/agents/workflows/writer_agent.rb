# frozen_string_literal: true

# WriterAgent - Writes polished content for the supervisor workflow
#
# A delegate agent used by the ResearchWorkflow's supervisor.
# Called via DelegateTool when the orchestrator needs content written.
#
# @example
#   result = Workflows::WriterAgent.call(input: "Write an article from these notes...")
#   result.content  # => polished article
#
module Workflows
  class WriterAgent < ApplicationAgent
    description "Writes polished articles from research notes"

    model "gpt-4o-mini"
    temperature 0.7

    system "You are a skilled writer. Create engaging, well-structured content from the provided research notes."
    user "Write a polished article based on:\n\n{input}"
  end
end
