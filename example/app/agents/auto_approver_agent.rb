# frozen_string_literal: true

class AutoApproverAgent < ApplicationAgent
  description "Auto-approves low-value requests"
  model "gpt-4o-mini"

  param :document_id, required: true
  param :reason, required: false

  def user_prompt
    "Auto-approve document #{document_id}: #{reason}"
  end
end
