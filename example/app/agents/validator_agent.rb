# frozen_string_literal: true

class ValidatorAgent < ApplicationAgent
  description "Validates extracted data structure and completeness"
  model "gpt-4o-mini"
  temperature 0.0

  param :data, required: true
  param :expected_fields, required: false, default: %w[content entities]

  def system_prompt
    "You are a data validator. Check if the provided data has the expected structure and fields."
  end

  def user_prompt
    <<~PROMPT
      Validate the following data has these expected fields: #{expected_fields.join(', ')}

      Data:
      #{data.inspect}

      Return validation status and any missing or invalid fields.
    PROMPT
  end
end
