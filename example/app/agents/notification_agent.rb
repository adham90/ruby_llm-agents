# frozen_string_literal: true

class NotificationAgent < ApplicationAgent
  description 'Sends notifications to users'
  model 'gpt-4o-mini'

  param :to, required: true
  param :document_id, required: true
  param :status, required: true

  def user_prompt
    "Send notification to #{to} about document #{document_id}: status is #{status}"
  end
end
