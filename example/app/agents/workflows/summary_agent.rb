# frozen_string_literal: true

# SummaryAgent - Summarizes text content
#
# Used as a parallel step in the ContentAnalyzer workflow.
# Runs concurrently with SentimentAgent and KeywordAgent.
#
# @example
#   result = Workflows::SummaryAgent.call(text: "Long article content...")
#   result.content  # => "Brief summary of the article..."
#
module Workflows
  class SummaryAgent < ApplicationAgent
    description "Creates concise summaries of text content"

    model "gpt-4o-mini"
    temperature 0.3

    system "You are a summarization specialist. Create clear, concise summaries."
    user "Summarize the following text in 2-3 sentences:\n\n{text}"
  end
end
