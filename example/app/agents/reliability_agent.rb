# frozen_string_literal: true

# ReliabilityAgent - Demonstrates the `on_failure` DSL
#
# This agent showcases all reliability features using the simplified DSL:
# - Automatic retries with exponential backoff
# - Fallback models when primary fails
# - Total timeout across all attempts
# - Circuit breaker for failure isolation
#
# The `on_failure` block groups all error handling settings with
# intuitive naming (e.g., `retries times:` instead of `retries max:`).
#
# @example Basic usage
#   ReliabilityAgent.call(query: "What is 2+2?")
#
# @example Dry run to see configuration
#   result = ReliabilityAgent.call(query: "test", dry_run: true)
#   result.content[:model]  # => "gpt-4o-mini"
#
class ReliabilityAgent < ApplicationAgent
  description "Demonstrates reliability features: retries, fallbacks, timeouts, circuit breaker"
  model "gpt-4o-mini"
  temperature 0.7
  timeout 15

  # Prompts using simplified DSL
  system <<~PROMPT
    You are a helpful assistant. Answer questions concisely and accurately.
    If you don't know something, say so clearly.
  PROMPT

  prompt "{query}"

  # Error handling using the simplified `on_failure` DSL
  # More intuitive naming than the traditional `reliability` block
  on_failure do
    # Retry failed requests with exponential backoff
    # Delay sequence: 0.4s, 0.8s, 1.6s (capped at 3.0s)
    retries times: 3, backoff: :exponential, base: 0.4, max_delay: 3.0

    # Try these models in order if primary fails
    fallback to: ["gpt-4o-mini", "claude-3-haiku-20240307"]

    # Overall timeout for all attempts (retries + fallbacks)
    timeout 45

    # Circuit breaker: opens after 5 errors in 60 seconds
    # Stays open for 5 minutes before allowing test requests
    circuit_breaker after: 5, within: 60, cooldown: 5.minutes
  end
end
