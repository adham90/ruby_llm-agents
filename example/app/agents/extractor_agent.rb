# frozen_string_literal: true

# ExtractorAgent - Extracts key information from text
#
# Demonstrates the simplified DSL with prompt template syntax.
#
class ExtractorAgent < ApplicationAgent
  description "Extracts key information, entities, and main points from text"
  model "gpt-4o-mini"
  temperature 0.0

  system "You are a data extraction assistant. Extract key information from the given text."
  prompt "Extract the main points and entities from this text:\n\n{text}"

  returns do
    array :main_points, of: :string, description: "Key points from the text"
    array :entities, of: :string, description: "Named entities (people, places, organizations)"
    string :summary, description: "Brief one-sentence summary"
  end
end
