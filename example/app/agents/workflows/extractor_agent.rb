# frozen_string_literal: true

# ExtractorAgent - Extracts structured data from raw text
#
# Used as the first step in the ContentPipeline workflow.
# Takes raw text and extracts key entities, facts, and themes.
#
# @example
#   result = Workflows::ExtractorAgent.call(text: "Article content...")
#   result.content[:entities]  # => ["AI", "machine learning"]
#   result.content[:themes]    # => ["technology", "innovation"]
#
module Workflows
  class ExtractorAgent < ApplicationAgent
    description "Extracts entities, facts, and themes from text"

    model "gpt-4o-mini"
    temperature 0.0

    system "You are a data extraction specialist. Extract structured information from the provided text."
    user "Extract key entities, facts, and themes from:\n\n{text}"

    returns do
      array :entities, of: :string, description: "Named entities (people, places, organizations)"
      array :facts, of: :string, description: "Key factual statements"
      array :themes, of: :string, description: "Main themes or topics"
    end
  end
end
