# frozen_string_literal: true

# KeywordAgent - Extracts keywords from text
#
# Used as a parallel step in the ContentAnalyzer workflow.
# Runs concurrently with SentimentAgent and SummaryAgent.
#
# @example
#   result = Workflows::KeywordAgent.call(text: "Article about AI safety...")
#   result.content[:keywords]  # => ["AI", "safety", "alignment"]
#
module Workflows
  class KeywordAgent < ApplicationAgent
    description "Extracts keywords and key phrases from text"

    model "gpt-4o-mini"
    temperature 0.0

    system "You are a keyword extraction specialist."
    user "Extract the most important keywords from:\n\n{text}"

    returns do
      array :keywords, of: :string, description: "Top keywords"
      array :phrases, of: :string, description: "Key multi-word phrases"
    end
  end
end
