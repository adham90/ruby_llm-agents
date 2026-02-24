# frozen_string_literal: true

# SentimentAgent - Analyzes sentiment of text
#
# Used as a parallel step in the ContentAnalyzer workflow.
# Runs concurrently with KeywordAgent and SummaryAgent.
#
# @example
#   result = Workflows::SentimentAgent.call(text: "I love this product!")
#   result.content[:sentiment]  # => "positive"
#
module Workflows
  class SentimentAgent < ApplicationAgent
    description "Analyzes text sentiment"

    model "gpt-4o-mini"
    temperature 0.0

    system "You are a sentiment analysis specialist."
    user "Analyze the sentiment of:\n\n{text}"

    returns do
      string :sentiment, enum: %w[positive negative neutral mixed], description: "Overall sentiment"
      number :score, description: "Sentiment score (-1.0 to 1.0)"
      string :explanation, description: "Brief explanation of the sentiment"
    end
  end
end
