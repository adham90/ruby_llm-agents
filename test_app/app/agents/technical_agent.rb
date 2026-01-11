# frozen_string_literal: true

class TechnicalAgent < ApplicationAgent
  description "Assists with technical issues, bugs, errors, and troubleshooting"
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
