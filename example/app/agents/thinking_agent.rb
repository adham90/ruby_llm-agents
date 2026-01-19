# frozen_string_literal: true

# ThinkingAgent - Demonstrates extended thinking/reasoning support
#
# This agent showcases the thinking DSL for models that support
# extended reasoning (Claude, Gemini 2.5+, OpenAI o1/o3, etc.).
#
# Extended thinking allows the model to show its reasoning process
# before providing a final answer. This is useful for:
# - Complex problem solving
# - Math and logic puzzles
# - Multi-step reasoning tasks
# - Debugging and analysis
#
# Supported providers:
# - Claude (Anthropic/Bedrock): Visible thinking with effort + budget
# - Gemini 2.5/3: Visible thinking with budget or effort
# - OpenAI (o1/o3): Hidden thinking with effort only
# - Perplexity: Streams <think> blocks
# - Mistral Magistral: Always on
# - Ollama Qwen3: Default on, :none to disable
#
# @example Basic usage
#   result = ThinkingAgent.call(query: "What is 127 * 43?")
#   puts result.thinking_text  # Shows reasoning process
#   puts result.content        # Final answer
#
# @example Check if thinking was used
#   result = ThinkingAgent.call(query: "Solve this puzzle...")
#   if result.has_thinking?
#     puts "Thinking tokens: #{result.thinking_tokens}"
#   end
#
# @example Runtime override
#   # Use higher effort for complex problems
#   result = ThinkingAgent.call(
#     query: "Complex problem...",
#     thinking: { effort: :high, budget: 15000 }
#   )
#
#   # Disable thinking for simple questions
#   result = ThinkingAgent.call(
#     query: "What is 2+2?",
#     thinking: false
#   )
#
# @example Streaming with thinking
#   ThinkingAgent.stream(query: "Analyze this...") do |chunk|
#     if chunk.thinking&.text
#       print "[Thinking] #{chunk.thinking.text}"
#     elsif chunk.content
#       print chunk.content
#     end
#   end
#
class ThinkingAgent < ApplicationAgent
  description "Demonstrates extended thinking/reasoning support"
  version "1.0"

  # Use a model that supports thinking
  # Claude Opus 4.5 is recommended for best thinking support
  model "claude-opus-4-5-20250514"
  temperature 0.0

  # Configure thinking with effort level and token budget
  # effort: :none, :low, :medium, :high
  # budget: max tokens for thinking computation
  thinking effort: :high, budget: 10000

  param :query, required: true

  def system_prompt
    <<~PROMPT
      You are a reasoning assistant that excels at step-by-step problem solving.

      When given a problem:
      1. Break it down into smaller steps
      2. Work through each step carefully
      3. Verify your work
      4. Provide a clear final answer

      Show your reasoning process clearly.
    PROMPT
  end

  def user_prompt
    query
  end

  def execution_metadata
    {
      showcase: "thinking",
      features: %w[extended_thinking reasoning effort_levels token_budget]
    }
  end
end
