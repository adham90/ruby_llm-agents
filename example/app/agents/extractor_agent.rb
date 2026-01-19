# frozen_string_literal: true

class ExtractorAgent < ApplicationAgent
  description "Extracts key information, entities, and main points from text"
  model "gpt-4o-mini"
  temperature 0.0

  param :text, required: true

  def system_prompt
    "You are a data extraction assistant. Extract key information from the given text."
  end

  def user_prompt
    "Extract the main points and entities from this text:\n\n#{text}"
  end
end
