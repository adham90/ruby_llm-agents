# frozen_string_literal: true

module Chat
  class SupportAgent < ApplicationAgent
    # ============================================
    # Model Configuration
    # ============================================

    model "gpt-4o-mini"
    temperature 0.7
    version "1.0"

    # ============================================
    # Parameters
    # ============================================

    param :message, required: true
    param :context, default: nil

    private

    # ============================================
    # Prompts (required)
    # ============================================

    def system_prompt
      <<~PROMPT
        You are a helpful customer support assistant.
        Be friendly, professional, and concise in your responses.
      PROMPT
    end

    def user_prompt
      prompt = message
      prompt += "\n\nContext: #{context}" if context.present?
      prompt
    end
  end
end
