# frozen_string_literal: true

# MercuryAgent - Demonstrates using Inception Labs' Mercury dLLM
#
# Mercury models are diffusion LLMs that generate tokens in parallel,
# delivering dramatically faster inference while matching quality of
# traditional autoregressive models.
#
# Mercury 2 supports function calling, structured output, and reasoning.
#
# Setup: config.inception_api_key = ENV['INCEPTION_API_KEY']
#
class MercuryAgent < ApplicationAgent
  model "mercury-2"
  description "Fast general-purpose agent powered by Mercury dLLM"
  temperature 0.7

  system "You are a helpful assistant powered by Mercury, a diffusion language model."
  prompt "{question}"

  # Mercury 2 supports structured output
  returns do
    string :answer, description: "The answer to the question"
    number :confidence, description: "Confidence score from 0 to 1"
  end

  on_failure do
    retries times: 2, backoff: :exponential
    timeout 30
  end
end

# Usage:
#   result = MercuryAgent.call(question: "What is a diffusion language model?")
#   result.content[:answer]      # => "A diffusion language model generates..."
#   result.content[:confidence]  # => 0.92
