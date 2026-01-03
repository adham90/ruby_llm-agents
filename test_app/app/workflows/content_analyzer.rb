# frozen_string_literal: true

# Example Parallel Workflow
# Analyzes content from multiple perspectives concurrently
#
# Usage:
#   result = ContentAnalyzer.call(text: "Your content here")
#   result.branches[:sentiment].content  # Sentiment analysis
#   result.branches[:keywords].content   # Keyword extraction
#   result.branches[:summary].content    # Summary
#   result.total_cost                    # Combined cost
#
class ContentAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  fail_fast false  # Continue even if a branch fails

  branch :sentiment, agent: SentimentAgent
  branch :keywords,  agent: KeywordAgent
  branch :summary,   agent: SummaryAgent

  # Custom aggregation of results
  def aggregate(results)
    {
      sentiment: results[:sentiment]&.content,
      keywords: results[:keywords]&.content,
      summary: results[:summary]&.content,
      analyzed_at: Time.current
    }
  end
end
