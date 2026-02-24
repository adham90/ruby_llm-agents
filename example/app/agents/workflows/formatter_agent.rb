# frozen_string_literal: true

# FormatterAgent - Formats classified content into a final report
#
# Used as the final step in the ContentPipeline workflow.
# Takes classification results and produces a formatted summary.
#
# @example
#   result = Workflows::FormatterAgent.call(
#     category: "technology",
#     tags: ["AI", "innovation"]
#   )
#   result.content  # => formatted report string
#
module Workflows
  class FormatterAgent < ApplicationAgent
    description "Formats classified content into a structured report"

    model "gpt-4o-mini"
    temperature 0.3

    system "You are a content formatter. Create clear, structured summaries."
    user "Format a report for category: {category} with tags: {tags}"
  end
end
