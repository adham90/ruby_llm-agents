# frozen_string_literal: true

# ClassifierAgent - Classifies content into categories
#
# Demonstrates the simplified DSL with structured output.
#
class ClassifierAgent < ApplicationAgent
  description "Classifies content into categories: article, news, review, tutorial, or other"
  model "gpt-4o-mini"
  temperature 0.0

  system "You are a content classifier. Analyze content and categorize it accurately."
  prompt "Classify this content into one of: article, news, review, tutorial, other.\n\n{text}"

  returns do
    string :category, description: "The classification category"
    number :confidence, description: "Confidence score from 0 to 1"
    string :reasoning, description: "Brief explanation for the classification"
  end
end
