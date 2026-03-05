# frozen_string_literal: true

# MercuryCoderAgent - Fast code generation with Mercury Coder Small
#
# Mercury Coder Small runs 5-10x faster than speed-optimized frontier
# models like GPT-4o Mini and Claude 3.5 Haiku while matching quality.
# Ideal for code generation, explanation, and review tasks.
#
# Setup: config.inception_api_key = ENV['INCEPTION_API_KEY']
#
class MercuryCoderAgent < ApplicationAgent
  model "mercury-coder-small"
  description "Ultra-fast code generation agent"
  temperature 0.0

  system "You are an expert programmer. Write clean, efficient, well-documented code. " \
    "Follow language-specific conventions and best practices."
  prompt "Language: {language}\n\nTask: {task}"

  param :language, default: "ruby"

  on_failure do
    retries times: 2, backoff: :exponential
    timeout 30
  end
end

# Usage:
#   result = MercuryCoderAgent.call(task: "Write a binary search function")
#   result.content  # => "def binary_search(arr, target)..."
#
#   result = MercuryCoderAgent.call(
#     language: "python",
#     task: "Implement a LRU cache class"
#   )
