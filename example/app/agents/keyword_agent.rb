# frozen_string_literal: true

class KeywordAgent < ApplicationAgent
  description 'Extracts the top 5 keywords from text content'
  model 'gpt-4o-mini'
  temperature 0.0

  param :text, required: true

  def system_prompt
    'You are a keyword extraction assistant.'
  end

  def user_prompt
    "Extract the top 5 keywords from this text:\n\n#{text}"
  end
end
