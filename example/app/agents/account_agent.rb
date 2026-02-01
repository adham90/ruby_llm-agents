# frozen_string_literal: true

require_relative 'concerns/validatable'
require_relative 'concerns/contextual'

# AccountAgent - Handles account-related support requests
#
# Used by SupportRouterWorkflow to handle account-specific issues
# like login problems, profile changes, and account settings.
#
# Example usage:
#
#   agent = AccountAgent.new(message: "I can't log in to my account")
#   result = agent.call
#
class AccountAgent < ApplicationAgent
  extend Concerns::Validatable::DSL
  extend Concerns::Contextual::DSL
  include Concerns::Validatable::Execution
  include Concerns::Contextual::Execution

  description 'Handles account issues: login, profile, settings, password resets'
  model 'gpt-4o'
  temperature 0.3

  validates_presence_of :message
  validates_length_of :message, min: 5, max: 5000,
                                message: 'message must be between 5 and 5000 characters'

  context_from :current_user, :options
  context_includes :user_id, :user_name, :account_type
  default_context account_type: 'standard'

  param :message, required: true
  param :current_user, default: nil

  def system_prompt
    base_prompt = <<~PROMPT
      You are an account support specialist. Help customers with:
      - Login and authentication issues
      - Password resets and recovery
      - Profile updates and changes
      - Account settings and preferences
      - Account security concerns

      Be helpful and guide users through step-by-step solutions.
      Never share sensitive account information in responses.
    PROMPT

    ctx = context_prompt_prefix
    ctx.present? ? "#{base_prompt}\n\n#{ctx}" : base_prompt
  end

  def user_prompt
    message
  end

  def call
    validate!
    super
  end
end
