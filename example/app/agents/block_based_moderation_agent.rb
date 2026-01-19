# frozen_string_literal: true

# BlockBasedModerationAgent - Demonstrates block DSL with phase-specific thresholds
#
# This agent uses the block-based moderation DSL to configure different
# settings for input and output moderation phases. This allows fine-grained
# control over moderation behavior.
#
# Use cases:
# - Different strictness for input vs output
# - Checking different categories per phase
# - Complex moderation configurations
# - Enterprise applications with specific policies
#
# Related examples:
# - moderated_agent.rb          - Simple input moderation
# - fully_moderated_agent.rb    - Same settings for both phases
# - custom_handler_moderation_agent.rb - Custom handling logic
#
# @example Basic usage
#   result = BlockBasedModerationAgent.call(message: "Hello!")
#   puts result.content
#
# @example Understanding phase-specific behavior
#   # Input is checked with threshold 0.5 (strict)
#   # Output is checked with threshold 0.8 (lenient)
#   result = BlockBasedModerationAgent.call(message: "test message")
#
# @example Checking configuration
#   config = BlockBasedModerationAgent.moderation_config
#   puts config[:input][:threshold]   # => 0.5
#   puts config[:output][:threshold]  # => 0.8
#
class BlockBasedModerationAgent < ApplicationAgent
  description "Demonstrates block DSL with phase-specific thresholds"
  version "1.0"

  model "gpt-4o"
  temperature 0.7

  # Block-based moderation configuration
  # Allows different settings for input and output phases
  moderation do
    # Strict input moderation - block harmful user input early
    input enabled: true, threshold: 0.5

    # More lenient output moderation - allow creative responses
    output enabled: true, threshold: 0.8

    # Shared settings
    model "omni-moderation-latest"
    categories :hate, :violence, :harassment

    # Block flagged content (default behavior)
    on_flagged :block
  end

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a creative writing assistant. Help users develop their
      stories and ideas. Be imaginative while staying appropriate.
    PROMPT
  end

  def user_prompt
    message
  end

  def execution_metadata
    {
      showcase: "moderation",
      features: %w[block_dsl phase_specific_thresholds granular_control]
    }
  end
end
