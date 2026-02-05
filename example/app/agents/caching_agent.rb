# frozen_string_literal: true

# CachingAgent - Demonstrates the simplified cache DSL
#
# This agent showcases response caching:
# - Enables caching with a 1-hour TTL using `cache for:`
# - Uses temperature 0.0 for deterministic (cacheable) results
#
# Cache keys are generated from:
# - Agent class name
# - All parameters
# - Prompts content
#
# @example First call (cache miss)
#   CachingAgent.call(query: "Explain caching")
#   # => Makes API call, caches result
#
# @example Second call (cache hit)
#   CachingAgent.call(query: "Explain caching")
#   # => Returns cached result instantly
#
# @example Bypass cache
#   CachingAgent.call(query: "Explain caching", skip_cache: true)
#   # => Forces new API call
#
class CachingAgent < ApplicationAgent
  description "Demonstrates response caching for repeated queries"
  model "gpt-4o-mini"
  temperature 0.0 # Deterministic output is essential for caching
  timeout 30

  # Prompts using simplified DSL
  system "You are a knowledgeable assistant. Provide clear, consistent answers. Be concise but thorough."
  prompt "Please answer this question: {query}"

  # Enable response caching with simplified syntax
  # Responses are stored in Rails.cache
  cache for: 1.hour

  returns do
    string :answer, description: "The response to the query"
    array :key_points, of: :string, description: "Main points in the answer"
  end
end
