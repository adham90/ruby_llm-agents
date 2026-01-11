# frozen_string_literal: true

class GeneralAgent < ApplicationAgent
  description "Handles general customer inquiries and support requests"
  model "gpt-4o-mini"
  temperature 0.5

  param :message, required: true

  def system_prompt
    "You are a helpful customer support assistant. Help customers with general inquiries."
  end

  def user_prompt
    message
  end
end
