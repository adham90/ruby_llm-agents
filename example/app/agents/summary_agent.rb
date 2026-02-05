# frozen_string_literal: true

# SummaryAgent - Generates concise summaries
#
# Demonstrates the simplified DSL with configurable sentence count.
#
class SummaryAgent < ApplicationAgent
  description "Generates concise summaries of text"
  model "gpt-4o-mini"
  temperature 0.3

  system "You are a summarization assistant. Be concise and capture the key points."
  prompt "Summarize this text in {sentence_count} sentences:\n\n{text}"

  param :sentence_count, default: 3

  returns do
    string :summary, description: "The summarized text"
    array :key_points, of: :string, description: "Main points covered"
  end
end
