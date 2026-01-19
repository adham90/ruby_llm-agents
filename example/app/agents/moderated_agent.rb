# frozen_string_literal: true

# ModeratedAgent - Demonstrates content moderation support
#
# This agent showcases the moderation DSL for automatically checking
# user input and/or LLM output against safety policies using
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
  description "Demonstrates content moderation support"
  version "1.0"

  model "gpt-4o"
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
    categories: [:hate, :violence, :harassment]

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
      showcase: "moderation",
      features: %w[content_moderation input_filtering safety_checks]
    }
  end
end

# Example with output moderation
#
# class ContentGeneratorAgent < ApplicationAgent
#   model "gpt-4o"
#
#   # Check generated content before returning
#   moderation :output, threshold: 0.5
#
#   param :topic, required: true
#
#   def user_prompt
#     "Write a story about #{topic}"
#   end
# end

# Example with both input and output moderation
#
# class FullyModeratedAgent < ApplicationAgent
#   model "gpt-4o"
#
#   # Moderate both directions
#   moderation :both,
#     threshold: 0.6,
#     categories: [:hate, :violence, :harassment],
#     on_flagged: :raise
#
#   param :message, required: true
#
#   def user_prompt
#     message
#   end
# end

# Example with block-based DSL
#
# class AdvancedModeratedAgent < ApplicationAgent
#   model "gpt-4o"
#
#   moderation do
#     input enabled: true, threshold: 0.7
#     output enabled: true, threshold: 0.9
#     model 'omni-moderation-latest'
#     categories :hate, :violence, :harassment
#     on_flagged :block
#   end
#
#   param :message, required: true
#
#   def user_prompt
#     message
#   end
# end

# Example with custom handler
#
# class CustomModeratedAgent < ApplicationAgent
#   model "gpt-4o"
#
#   moderation :input, custom_handler: :handle_moderation
#
#   param :message, required: true
#
#   def user_prompt
#     message
#   end
#
#   private
#
#   def handle_moderation(result, phase)
#     # Log the moderation event
#     Rails.logger.warn("Content flagged: #{result.flagged_categories}")
#
#     # Return :continue to proceed anyway, :block to stop
#     if result.category_scores.values.max > 0.9
#       :block
#     else
#       :continue
#     end
#   end
# end
