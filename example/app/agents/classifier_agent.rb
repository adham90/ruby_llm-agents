# frozen_string_literal: true

class ClassifierAgent < ApplicationAgent
  description 'Classifies content into categories: article, news, review, tutorial, or other'
  model 'gpt-4o-mini'
  temperature 0.0

  param :text, required: true

  def system_prompt
    'You are a content classifier. Classify content into categories.'
  end

  def user_prompt
    "Classify this content into one of: article, news, review, tutorial, other.\n\n#{text}"
  end
end
