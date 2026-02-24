# frozen_string_literal: true

# ClassifierAgent - Classifies content based on extracted data
#
# Used as the second step in the ContentPipeline workflow.
# Takes extracted entities and themes to classify the content.
#
# @example
#   result = Workflows::ClassifierAgent.call(
#     entities: ["OpenAI", "GPT-4"],
#     themes: ["AI", "technology"]
#   )
#   result.content[:category]  # => "technology"
#
module Workflows
  class ClassifierAgent < ApplicationAgent
    description "Classifies content into categories based on extracted data"

    model "gpt-4o-mini"
    temperature 0.0

    system "You are a content classifier. Categorize content based on the provided data."
    user "Classify content with entities: {entities} and themes: {themes}"

    returns do
      string :category, description: "Primary category"
      number :confidence, description: "Classification confidence (0-1)"
      array :tags, of: :string, description: "Relevant tags"
    end
  end
end
