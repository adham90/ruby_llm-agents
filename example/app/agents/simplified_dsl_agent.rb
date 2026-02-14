# frozen_string_literal: true

# SimplifiedDSLAgent - Demonstrates the simplified DSL syntax
#
# This agent showcases the new simplified DSL that puts prompts
# front and center, with cleaner syntax for common configurations.
#
# Compare this to full_featured_agent.rb which uses the traditional DSL.
#
class SimplifiedDSLAgent < ApplicationAgent
  # Model and basic config
  model "gpt-4o"
  description "Demonstrates the simplified DSL syntax"
  temperature 0.5

  # Prompts are first-class - the heart of any agent
  system "You are a helpful data analyst. Be concise and accurate."
  prompt "Analyze this {data_type} data and provide insights: {data}"

  # Override auto-detected param with default (data_type is now optional)
  param :data_type, default: "general"

  # Structured output with clean syntax
  returns do
    string :summary, description: "Brief analysis summary"
    array :insights, of: :string, description: "Key insights discovered"
    number :confidence, description: "Confidence score from 0 to 1"
    boolean :needs_review, description: "Whether human review is recommended"
  end

  # Error handling with intuitive syntax
  on_failure do
    retries times: 3, backoff: :exponential
    fallback to: "gpt-4o-mini"
    timeout 60
    circuit_breaker after: 5, cooldown: 5.minutes
  end

  # Caching with cleaner keyword syntax
  cache for: 1.hour

  # Simple block-only callbacks
  before { |ctx| Rails.logger.info("Analyzing #{ctx.params[:data_type]} data...") }
  after { |ctx, result| notify_if_low_confidence(result) }

  private

  def notify_if_low_confidence(result)
    return unless result.respond_to?(:content) && result.content.is_a?(Hash)
    return unless result.content[:confidence]&.< 0.5

    Rails.logger.warn("Low confidence analysis detected")
  end
end

# Usage:
#   result = SimplifiedDSLAgent.call(data: "Sales: Q1=100k, Q2=120k, Q3=95k")
#   result.content[:summary]     # => "Quarterly sales show growth..."
#   result.content[:insights]    # => ["Q2 showed 20% growth", "Q3 declined"]
#   result.content[:confidence]  # => 0.85
