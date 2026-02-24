# frozen_string_literal: true

# GeneralAgent - Handles general support questions
#
# Used as the default dispatch target in the SupportWorkflow.
# Activated when the SupportRouter cannot classify into a specific category.
#
# @example
#   result = Workflows::GeneralAgent.call(message: "Hello!")
#   result.content  # => general response
#
module Workflows
  class GeneralAgent < ApplicationAgent
    description "Handles general inquiries and greetings"

    model "gpt-4o-mini"
    temperature 0.5

    system "You are a friendly support agent. Help with general inquiries and direct specific questions to the right team."
    user "{message}"
  end
end
