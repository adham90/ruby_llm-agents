# frozen_string_literal: true

class DocumentFetcherAgent < ApplicationAgent
  description "Fetches documents for review"
  model "gpt-4o-mini"

  param :document_id, required: true

  def user_prompt
    "Fetch document: #{document_id}"
  end
end
