# frozen_string_literal: true

# CachingAgent - Demonstrates the cache_for DSL
#
# This agent showcases response caching:
# - Enables caching with a 1-hour TTL
# - Uses temperature 0.0 for deterministic (cacheable) results
# - Version affects cache key for invalidation
#
# Cache keys are generated from:
# - Agent class name
# - Version string
# - All parameters
# - Prompts content
#
# @example First call (cache miss)
#   Llm::CachingAgent.call(query: "Explain caching")
#   # => Makes API call, caches result
#
# @example Second call (cache hit)
#   Llm::CachingAgent.call(query: "Explain caching")
#   # => Returns cached result instantly
#
# @example Bypass cache
#   Llm::CachingAgent.call(query: "Explain caching", skip_cache: true)
#   # => Forces new API call
#
module Llm
  class CachingAgent < ApplicationAgent
    description "Demonstrates response caching for repeated queries"
    version "1.0"

    model "gpt-4o-mini"
    temperature 0.0  # Deterministic output is essential for caching
    timeout 30

    # Enable response caching with 1-hour TTL
    # Responses are stored in Rails.cache
    cache_for 1.hour

    param :query, required: true

    def system_prompt
      <<~PROMPT
        You are a knowledgeable assistant. Provide clear, consistent answers.
        Be concise but thorough.
      PROMPT
    end

    def user_prompt
      "Please answer this question: #{query}"
    end

    def execution_metadata
      {
        showcase: "caching",
        features: %w[cache_for temperature_zero version]
      }
    end
  end
end
