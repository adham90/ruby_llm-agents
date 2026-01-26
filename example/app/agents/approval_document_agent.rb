# frozen_string_literal: true

class ApprovalDocumentAgent < ApplicationAgent
  description "Creates approval records"
  model "gpt-4o-mini"

  param :document_id, required: true
  param :amount, required: true
  param :approved_by, required: true
  param :classification, required: false

  def user_prompt
    "Generate approval record for document #{document_id}, amount: #{amount}, approved by: #{approved_by}"
  end
end
