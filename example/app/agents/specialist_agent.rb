# frozen_string_literal: true

class SpecialistAgent < ApplicationAgent
  description 'Specialist support agent for escalated technical issues'
  model 'gpt-4o'
  temperature 0.3

  param :problem, required: true
  param :context, required: false
  param :escalation_reason, required: false

  def system_prompt
    <<~PROMPT
      You are a specialist support agent handling escalated technical issues.
      You have deep expertise in complex technical problems that frontline agents cannot resolve.
      Provide thorough, detailed solutions with step-by-step guidance.
    PROMPT
  end

  def user_prompt
    parts = ["Technical Issue: #{problem}"]
    parts << "Previous Context: #{context}" if context.present?
    parts << "Escalation Reason: #{escalation_reason}" if escalation_reason.present?
    parts.join("\n\n")
  end
end
