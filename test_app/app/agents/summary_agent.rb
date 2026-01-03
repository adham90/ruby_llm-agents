# frozen_string_literal: true

class SummaryAgent < ApplicationAgent
  model "gpt-4o-mini"
  temperature 0.3

  param :text, required: true

  def system_prompt
    "You are a summarization assistant."
  end

  def user_prompt
    "Summarize this text in 2-3 sentences:\n\n#{text}"
  end
end
