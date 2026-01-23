# frozen_string_literal: true

class BillingAgent < ApplicationAgent
  description "Handles billing questions, charges, refunds, and invoice inquiries"
  model "gpt-4o"
  temperature 0.3

  param :message, required: true

  def system_prompt
    "You are a billing support specialist. Help customers with billing questions, charges, refunds, and invoice inquiries."
  end

  def user_prompt
    message
  end
end
