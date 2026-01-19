# frozen_string_literal: true

# ReliabilityAgent - Demonstrates the full reliability DSL
#
# This agent showcases all reliability features:
# - Automatic retries with exponential backoff
# - Fallback models when primary fails
# - Total timeout across all attempts
# - Circuit breaker for failure isolation
#
# The reliability block groups all settings for clarity.
#
# @example Basic usage
#   ReliabilityAgent.call(query: "What is 2+2?")
#
# @example Dry run to see configuration
#   result = ReliabilityAgent.call(query: "test", dry_run: true)
#   result[:model]  # => "gpt-4o-mini"
#
class ReliabilityAgent < ApplicationAgent
  description "Demonstrates reliability features: retries, fallbacks, timeouts, circuit breaker"
  version "1.0"

  model "gpt-4o-mini"
  temperature 0.7
  timeout 15

  # Full reliability configuration block
  # Groups all reliability settings in one place for clarity
  reliability do
    # Retry failed requests with exponential backoff
    # Delay sequence: 0.4s, 0.8s, 1.6s (capped at 3.0s)
    retries max: 3, backoff: :exponential, base: 0.4, max_delay: 3.0

    # Try these models in order if primary fails
    fallback_models "gpt-4o-mini", "claude-3-haiku-20240307"

    # Overall timeout for all attempts (retries + fallbacks)
    total_timeout 45

    # Circuit breaker: opens after 5 errors in 60 seconds
    # Stays open for 300 seconds before allowing test requests
    circuit_breaker errors: 5, within: 60, cooldown: 300
  end

  param :query, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful assistant. Answer questions concisely and accurately.
      If you don't know something, say so clearly.
    PROMPT
  end

  def user_prompt
    query
  end

  def execution_metadata
    {
      showcase: "reliability",
      features: %w[retries fallback_models total_timeout circuit_breaker]
    }
  end
end
