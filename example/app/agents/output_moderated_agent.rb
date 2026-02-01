# frozen_string_literal: true

# OutputModeratedAgent - Demonstrates output-only moderation
#
# This agent moderates only the LLM's response, not the user input.
# Useful when you trust the input source but want to ensure the
# LLM doesn't generate inappropriate content.
#
# Use cases:
# - Internal tools where input is trusted
# - Content generation systems
# - Ensuring LLM outputs meet content policies
# - Protecting against prompt injection that triggers harmful output
#
# Related examples:
# - moderated_agent.rb          - Input-only moderation
# - fully_moderated_agent.rb    - Both input and output moderation
# - block_based_moderation_agent.rb - Block DSL with different thresholds
#
# @example Basic usage
#   result = OutputModeratedAgent.call(topic: "write a story about friendship")
#   puts result.content
#
# @example Handling flagged output
#   result = OutputModeratedAgent.call(topic: "controversial topic")
#   if result.moderation_flagged?
#     puts "Output was blocked: #{result.moderation_categories.join(', ')}"
#     puts "Phase: #{result.moderation_phase}"  # => :output
#   else
#     puts result.content
#   end
#
# @example Checking moderation scores
#   result = OutputModeratedAgent.call(topic: "some topic")
#   result.moderation_scores.each do |category, score|
#     puts "#{category}: #{score.round(4)}"
#   end
#
class OutputModeratedAgent < ApplicationAgent
  description 'Demonstrates output-only content moderation'
  version '1.0'

  model 'gpt-4o'
  temperature 0.7

  # Moderate only the output (LLM response)
  # Input is passed through without moderation
  moderation :output,
             threshold: 0.6,
             categories: %i[hate violence harassment sexual]

  param :topic, required: true

  def system_prompt
    <<~PROMPT
      You are a creative content writer. Generate engaging content
      based on the topic provided. Be creative but appropriate.
    PROMPT
  end

  def user_prompt
    "Write a short story or article about: #{topic}"
  end

  def execution_metadata
    {
      showcase: 'moderation',
      features: %w[output_moderation content_generation safety_checks]
    }
  end
end
