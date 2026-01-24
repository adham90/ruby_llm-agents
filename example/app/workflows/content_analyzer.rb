# frozen_string_literal: true

# Example Parallel Workflow using the new DSL
# Analyzes content from multiple perspectives concurrently
#
# Usage:
#   result = ContentAnalyzer.call(text: "Your content here")
#   result.steps[:sentiment].content  # Sentiment analysis
#   result.steps[:keywords].content   # Keyword extraction
#   result.steps[:summary].content    # Summary
#   result.total_cost                 # Combined cost
#
class ContentAnalyzer < RubyLLM::Agents::Workflow
  description "Analyzes content concurrently for sentiment, keywords, and summary"
  version "1.0"

  input do
    required :text, String
  end

  parallel do
    step :sentiment, SentimentAgent
    step :keywords, KeywordAgent
    step :summary, SummaryAgent
  end
end
