# frozen_string_literal: true

# FullyModeratedAgent - Demonstrates both input AND output moderation
#
# This agent moderates both user input before the LLM call and the
# LLM's response before returning. Provides maximum safety for
# user-facing applications.
#
# Use cases:
# - Public-facing chatbots
# - Customer support systems
# - Any application with untrusted user input
# - High-security content systems
#
# Related examples:
# - moderated_agent.rb          - Input-only moderation
# - output_moderated_agent.rb   - Output-only moderation
# - block_based_moderation_agent.rb - Different thresholds per phase
#
# @example Basic usage
#   result = FullyModeratedAgent.call(message: "Hello, how are you?")
#   puts result.content
#
# @example Detecting which phase was flagged
#   result = FullyModeratedAgent.call(message: "some message")
#   if result.moderation_flagged?
#     case result.moderation_phase
#     when :input
#       puts "User input was inappropriate"
#     when :output
#       puts "LLM response was inappropriate"
#     end
#   end
#
# @example Handling with exception
#   begin
#     result = FullyModeratedAgent.call(message: user_input)
#     render json: { response: result.content }
#   rescue RubyLLM::Agents::ModerationError => e
#     render json: {
#       error: "Content policy violation",
#       phase: e.phase,
#       categories: e.flagged_categories
#     }, status: :unprocessable_entity
#   end
#
class FullyModeratedAgent < ApplicationAgent
  description "Demonstrates both input AND output moderation"
  version "1.0"

  model "gpt-4o"
  temperature 0.7

  # Moderate BOTH input and output
  # Same threshold and categories apply to both phases
  moderation :both,
    threshold: 0.6,
    categories: [:hate, :violence, :harassment, :self_harm],
    on_flagged: :raise  # Raise exception instead of blocking

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful and friendly customer support assistant.
      Always be polite, professional, and provide accurate information.
      If you don't know something, say so honestly.
    PROMPT
  end

  def user_prompt
    message
  end

  def execution_metadata
    {
      showcase: "moderation",
      features: %w[full_moderation input_output_checks customer_support]
    }
  end
end
