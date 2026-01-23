# frozen_string_literal: true

# ModerationActionsAgent - Demonstrates :raise action with exception handling
#
# This agent uses on_flagged: :raise to throw an exception when content
# is flagged. This pattern is useful when you want to handle moderation
# failures in your application's error handling flow.
#
# Available on_flagged actions:
# - :block (default) - Returns result with moderation_flagged? = true
# - :raise           - Raises RubyLLM::Agents::ModerationError exception
# - :warn            - Logs warning and continues with LLM call
# - :log             - Logs info and continues with LLM call
#
# Use cases:
# - API endpoints that return structured error responses
# - Controller actions with rescue_from handlers
# - Strict enforcement where flagged content must halt execution
# - Integration with error tracking systems (Sentry, Bugsnag, etc.)
#
# Related examples:
# - moderated_agent.rb          - Uses :block (default)
# - custom_handler_moderation_agent.rb - Custom handling logic
# - fully_moderated_agent.rb    - Also uses :raise
#
# @example Controller usage with rescue_from
#   class ChatController < ApplicationController
#     rescue_from RubyLLM::Agents::ModerationError, with: :handle_moderation_error
#
#     def create
#       result = ModerationActionsAgent.call(message: params[:message])
#       render json: { response: result.content }
#     end
#
#     private
#
#     def handle_moderation_error(error)
#       render json: {
#         error: "Content policy violation",
#         phase: error.phase,
#         categories: error.flagged_categories,
#         scores: error.category_scores
#       }, status: :unprocessable_entity
#     end
#   end
#
# @example Direct exception handling
#   begin
#     result = ModerationActionsAgent.call(message: user_input)
#     puts result.content
#   rescue RubyLLM::Agents::ModerationError => e
#     puts "Blocked by moderation!"
#     puts "Phase: #{e.phase}"
#     puts "Categories: #{e.flagged_categories.join(', ')}"
#     puts "Max score: #{e.category_scores.values.max}"
#
#     # Report to error tracking
#     Sentry.capture_exception(e, extra: {
#       user_id: current_user.id,
#       categories: e.flagged_categories
#     })
#   end
#
# @example Testing moderation
#   # In RSpec
#   it "raises ModerationError for harmful content" do
#     expect {
#       ModerationActionsAgent.call(message: harmful_content)
#     }.to raise_error(RubyLLM::Agents::ModerationError) do |error|
#       expect(error.phase).to eq(:input)
#       expect(error.flagged_categories).to include(:violence)
#     end
#   end
#
class ModerationActionsAgent < ApplicationAgent
  description "Demonstrates :raise action with exception handling"
  version "1.0"

  model "gpt-4o"
  temperature 0.7

  # Use :raise action - throws exception when content is flagged
  moderation :input,
    threshold: 0.6,
    categories: [:hate, :violence, :harassment, :self_harm],
    on_flagged: :raise

  param :message, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful assistant. Provide clear, accurate responses
      to user questions. Be friendly and professional.
    PROMPT
  end

  def user_prompt
    message
  end

  def execution_metadata
    {
      showcase: "moderation",
      features: %w[raise_action exception_handling error_flow]
    }
  end
end
