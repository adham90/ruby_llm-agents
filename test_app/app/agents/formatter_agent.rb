# frozen_string_literal: true

class FormatterAgent < ApplicationAgent
  model "gpt-4o-mini"
  temperature 0.3

  param :text, required: true
  param :category

  def system_prompt
    "You are a content formatter. Format content in a clean, readable way."
  end

  def user_prompt
    "Format this #{category || 'content'} for display:\n\n#{text}"
  end
end
