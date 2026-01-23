# frozen_string_literal: true

require_relative "concerns/validatable"
require_relative "concerns/contextual"

# TechnicalAgent - Technical support with validation and context
#
# Demonstrates integration of Validatable and Contextual concerns
# for input validation and user context injection.
#
# Example usage:
#
#   # Basic usage with validation
#   agent = TechnicalAgent.new(message: "My app is crashing")
#   agent.valid?  # => true
#
#   # With user context for personalized support
#   agent = TechnicalAgent.new(
#     message: "Help with deployment",
#     current_user: OpenStruct.new(id: 1, name: "DevOps Team"),
#     product: "Enterprise"
#   )
#   agent.resolved_context
#   # => { user_id: 1, user_name: "DevOps Team", product: "Enterprise", support_tier: "standard" }
#
class TechnicalAgent < ApplicationAgent
  # Add concern DSL and execution modules
  extend Concerns::Validatable::DSL
  extend Concerns::Contextual::DSL
  include Concerns::Validatable::Execution
  include Concerns::Contextual::Execution

  description "Assists with technical issues, bugs, errors, and troubleshooting"
  model "gpt-4o"
  temperature 0.3

  # Validation rules
  validates_presence_of :message
  validates_length_of :message, min: 10, max: 5000,
                                message: "message must be between 10 and 5000 characters for effective troubleshooting"

  # Context configuration
  context_from :current_user, :options
  context_includes :user_id, :user_name, :product, :support_tier
  default_context support_tier: "standard"

  param :message, required: true
  param :current_user, default: nil
  param :product, default: nil

  def system_prompt
    base_prompt = <<~PROMPT
      You are a technical support specialist. Help customers with technical issues, bugs, errors, and troubleshooting.
      Be thorough, patient, and provide step-by-step solutions when possible.
    PROMPT

    # Add user context if available
    ctx = context_prompt_prefix
    if ctx.present?
      "#{base_prompt}\n\n#{ctx}"
    else
      base_prompt
    end
  end

  def user_prompt
    message
  end

  # Override call to validate first
  def call
    validate!
    super
  end
end
