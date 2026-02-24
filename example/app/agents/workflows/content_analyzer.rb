# frozen_string_literal: true

# ContentAnalyzer - Parallel execution workflow
#
# Demonstrates parallel execution where multiple agents analyze the
# same content concurrently. The sentiment, keyword, and summary steps
# have no dependencies, so they run in parallel using threads.
#
# This pattern is useful when you need multiple independent analyses
# of the same input — the wall-clock time is roughly the duration
# of the slowest step, not the sum of all steps.
#
# @example Basic usage
#   result = Workflows::ContentAnalyzer.call(text: "Article content...")
#   result.success?                      # => true
#   result.step(:sentiment).content      # => { sentiment: "positive", ... }
#   result.step(:keywords).content       # => { keywords: ["AI", ...] }
#   result.step(:summary).content        # => summary text
#   result.total_cost                    # => combined cost
#   result.duration_ms                   # => wall-clock time (not sum)
#
# @example Check individual step results
#   result = Workflows::ContentAnalyzer.call(text: "...")
#   result.step_names                    # => [:sentiment, :keywords, :summary]
#   result.step_count                    # => 3
#   result.successful_step_count         # => 3
#
module Workflows
  class ContentAnalyzer < ApplicationWorkflow
    description "Analyze content from multiple perspectives concurrently"

    # These three steps have no dependencies — they run in parallel
    step :sentiment, Workflows::SentimentAgent
    step :keywords, Workflows::KeywordAgent
    step :summary, Workflows::SummaryAgent

    # Optional: continue even if one analysis fails
    on_failure :continue
  end
end
