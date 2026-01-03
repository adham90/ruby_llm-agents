# frozen_string_literal: true

class TechnicalAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.3

  param :message, required: true

  def system_prompt
    "You are a technical support specialist. Help customers with technical issues, bugs, errors, and troubleshooting."
  end

  def user_prompt
    message
  end
end
