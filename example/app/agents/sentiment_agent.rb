# frozen_string_literal: true

module Llm
  class SentimentAgent < ApplicationAgent
    description "Analyzes text sentiment as positive, negative, or neutral"
    model "gpt-4o-mini"
    temperature 0.0

    param :text, required: true

    def system_prompt
      "You are a sentiment analysis assistant."
    end

    def user_prompt
      "Analyze the sentiment of this text (positive, negative, or neutral):\n\n#{text}"
    end
  end
end
