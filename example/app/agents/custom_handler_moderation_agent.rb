# frozen_string_literal: true

# CustomHandlerModerationAgent - Demonstrates custom moderation handling
#
# This agent uses a custom handler method to implement business logic
# for moderation decisions. Instead of simply blocking or raising,
# you can log, notify, conditionally proceed, or take other actions.
#
# Use cases:
# - Logging moderation events for compliance
# - Conditional blocking based on score thresholds
# - Notifying administrators of flagged content
# - A/B testing moderation policies
# - Implementing soft warnings
#
# Related examples:
# - moderated_agent.rb          - Standard moderation with :block
# - moderation_actions_agent.rb - Using :raise action
# - fully_moderated_agent.rb    - Both phases with standard handling
#
# @example Basic usage
#   result = CustomHandlerModerationAgent.call(message: "Hello!")
#   # Custom handler logs and may allow borderline content
#
# @example With moderately flagged content
#   result = CustomHandlerModerationAgent.call(message: "borderline content")
#   # If max score is 0.5-0.9, handler logs a warning and continues
#   # If max score is >= 0.9, handler blocks the content
#
# @example Checking if handler was invoked
#   result = CustomHandlerModerationAgent.call(message: "test")
#   # Check your logs for moderation events
#
class CustomHandlerModerationAgent < ApplicationAgent
  description 'Demonstrates custom moderation handling logic'
  version '1.0'

  model 'gpt-4o'
  temperature 0.7

  # Use custom handler for moderation decisions
  # The method name specified here will be called when content is flagged
  moderation :input,
             threshold: 0.5,
             categories: %i[hate violence harassment],
             custom_handler: :handle_moderation_result

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful assistant. Provide accurate and thoughtful
      responses to user questions.
    PROMPT
  end

  def user_prompt
    message
  end

  def execution_metadata
    {
      showcase: 'moderation',
      features: %w[custom_handler business_logic conditional_moderation]
    }
  end

  private

  # Custom handler for moderation results
  #
  # This method is called when content is flagged by moderation.
  # Return :continue to proceed anyway, :block to stop execution.
  #
  # @param result [ModerationResult] The moderation result object
  # @param phase [Symbol] Which phase was moderated (:input or :output)
  # @return [Symbol] :continue to proceed, :block to stop
  def handle_moderation_result(result, phase)
    max_score = result.category_scores.values.max
    flagged = result.flagged_categories

    # Log the moderation event
    log_moderation_event(phase, max_score, flagged)

    # Business logic: Only block if score is very high
    if max_score >= 0.9
      # Severe violation - block completely
      notify_admin(phase, result)
      :block
    elsif max_score >= 0.7
      # Moderate concern - log warning but allow
      log_warning(phase, max_score, flagged)
      :continue
    else
      # Low concern - just log and continue
      :continue
    end
  end

  # Log moderation event for compliance tracking
  # @param phase [Symbol]
  # @param score [Float]
  # @param categories [Array<Symbol>]
  def log_moderation_event(phase, score, categories)
    # In a real app, this would log to your compliance system
    Rails.logger.info(
      "[Moderation] Phase: #{phase}, Score: #{score.round(4)}, " \
      "Categories: #{categories.join(', ')}"
    )
  end

  # Log warning for borderline content
  # @param phase [Symbol]
  # @param score [Float]
  # @param categories [Array<Symbol>]
  def log_warning(phase, score, categories)
    Rails.logger.warn(
      "[Moderation Warning] Phase: #{phase}, Score: #{score.round(4)}, " \
      "Categories: #{categories.join(', ')}, Action: Allowed with warning"
    )
  end

  # Notify admin of severe violations
  # @param phase [Symbol]
  # @param result [ModerationResult]
  def notify_admin(phase, result)
    # In a real app, this might:
    # - Send an email to admins
    # - Create a ticket in your support system
    # - Post to a Slack channel
    # - Queue for human review
    Rails.logger.error(
      "[Moderation BLOCKED] Phase: #{phase}, " \
      "Scores: #{result.category_scores.inspect}"
    )
  end
end
