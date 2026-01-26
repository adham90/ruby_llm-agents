# frozen_string_literal: true

class SubmissionAgent < ApplicationAgent
  description "Submits documents to external system"
  model "gpt-4o-mini"

  param :document_id, required: true

  def user_prompt
    "Submit document #{document_id} to external system"
  end
end
