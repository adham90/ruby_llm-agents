# frozen_string_literal: true

# KnowledgeAgent - Demonstrates the Knowledge DSL
#
# This agent showcases the `knows` DSL for injecting domain knowledge
# into system prompts. Supports static files, dynamic blocks, and
# conditional inclusion.
#
# @example Basic usage
#   result = KnowledgeAgent.call(question: "What is the refund policy?")
#
# @example With premium tier
#   result = KnowledgeAgent.call(
#     question: "How long does shipping take?",
#     premium: true
#   )
#
class KnowledgeAgent < ApplicationAgent
  model "gpt-4o"
  description "Support agent with domain knowledge"

  # ===========================================
  # Knowledge (from files — inline multi-arg form)
  # ===========================================
  knowledge_path "app/knowledge"

  knows :refund_policy, :shipping_faq

  # ===========================================
  # Knowledge (conditional)
  # ===========================================
  knows :premium_perks, if: -> { premium } do
    [
      "Priority support with 1-hour response time",
      "Free express shipping on all orders",
      "Extended 90-day return window"
    ]
  end

  # ===========================================
  # Knowledge (dynamic)
  # ===========================================
  knows :current_promotions do
    # In a real app, this would query the database
    "Summer sale: 20% off all orders with code SUMMER2024"
  end

  # ===========================================
  # Prompts
  # ===========================================
  system <<~PROMPT
    You are a friendly customer support agent.
    Answer questions using ONLY the knowledge provided below.
    If you don't know the answer, say so honestly.
  PROMPT

  user "{question}"

  param :premium, default: false

  # ===========================================
  # Error Handling
  # ===========================================
  on_failure do
    retries times: 2, backoff: :exponential
    fallback to: "gpt-4o-mini"
  end
end

# Usage:
#   result = KnowledgeAgent.call(question: "Can I get a refund?")
#   result.content  # => "Yes! We offer a full refund within 30 days..."
#
#   result = KnowledgeAgent.call(question: "What perks do I get?", premium: true)
#   result.content  # => "As a premium member, you get priority support..."
