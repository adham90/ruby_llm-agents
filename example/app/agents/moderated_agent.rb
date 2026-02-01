# frozen_string_literal: true

# ModeratedAgent - Demonstrates input-only content moderation
#
# This agent showcases the moderation DSL for automatically checking
# user input before the LLM call. This is the simplest moderation
# pattern - check input and block harmful requests early.
#
# ============================================================================
# RELATED MODERATION EXAMPLES
# ============================================================================
#
# See these files for other moderation patterns:
#   - output_moderated_agent.rb           - Output-only moderation
#   - fully_moderated_agent.rb            - Both input AND output moderation
#   - block_based_moderation_agent.rb     - Block DSL with phase-specific thresholds
#   - custom_handler_moderation_agent.rb  - Custom handler with business logic
#   - moderation_actions_agent.rb         - Using :raise action with exceptions
#
# See these files for standalone moderators:
#   - moderators/content_moderator.rb     - Standard standalone moderator
#   - moderators/child_safe_moderator.rb  - Very strict (threshold 0.3)
#   - moderators/forum_moderator.rb       - Balanced (threshold 0.8)
#
# ============================================================================
#
# This agent checks user input against safety policies using
# RubyLLM's moderation API (powered by OpenAI).
#
# Content moderation is essential for production applications to:
# - Prevent harmful content from being processed or generated
# - Meet content policy requirements for user-facing applications
# - Reject problematic inputs before expensive LLM calls
# - Track moderation decisions for compliance reporting
#
# Supported moderation categories:
# - hate, hate/threatening
# - harassment, harassment/threatening
# - self-harm, self-harm/intent, self-harm/instructions
# - sexual, sexual/minors
# - violence, violence/graphic
#
# @example Basic usage
#   result = ModeratedAgent.call(message: "Hello!")
#   puts result.content  # => Normal response
#
# @example Flagged content
#   result = ModeratedAgent.call(message: "harmful content")
#   if result.moderation_flagged?
#     puts "Content blocked: #{result.moderation_categories.join(', ')}"
#     puts "Phase: #{result.moderation_phase}"
#   end
#
# @example Check moderation result
#   result = ModeratedAgent.call(message: "Some text")
#   if result.moderation_passed?
#     puts "Content is safe"
#   else
#     puts "Scores: #{result.moderation_scores}"
#   end
#
# @example Runtime override
#   # Disable moderation for specific call
#   result = ModeratedAgent.call(message: "test", moderation: false)
#
#   # Override threshold at runtime
#   result = ModeratedAgent.call(
#     message: "test",
#     moderation: { threshold: 0.95 }
#   )
#
# @example Using on_flagged: :raise
#   begin
#     result = StrictAgent.call(message: user_input)
#   rescue RubyLLM::Agents::ModerationError => e
#     puts "Blocked: #{e.flagged_categories.join(', ')}"
#     puts "Scores: #{e.category_scores}"
#   end
#
class ModeratedAgent < ApplicationAgent
  description 'Demonstrates content moderation support'
  version '1.0'

  model 'gpt-4o'
  temperature 0.7

  # Enable input moderation
  # Options:
  #   :input - Check user input before LLM call
  #   :output - Check LLM response before returning
  #   :both - Check both input and output
  #
  # Additional options:
  #   model: - Moderation model (default: omni-moderation-latest)
  #   threshold: - Score threshold 0.0-1.0 (nil = any flagged)
  #   categories: - Only flag specific categories
  #   on_flagged: - Action: :block (default), :raise, :warn, :log
  #   custom_handler: - Method name for custom handling
  moderation :input,
             threshold: 0.7,
             categories: %i[hate violence harassment]

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful and friendly assistant. Always be polite
      and provide accurate, helpful information.
    PROMPT
  end

  def user_prompt
    message
  end

  def execution_metadata
    {
      showcase: 'moderation',
      features: %w[content_moderation input_filtering safety_checks]
    }
  end
end
