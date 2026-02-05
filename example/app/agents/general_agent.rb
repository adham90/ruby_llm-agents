# frozen_string_literal: true

# GeneralAgent - Handles general customer inquiries
#
# A simple agent demonstrating the minimal simplified DSL.
#
class GeneralAgent < ApplicationAgent
  description "Handles general customer inquiries and support requests"
  model "gpt-4o-mini"
  temperature 0.5

  system "You are a helpful customer support assistant. Help customers with general inquiries."
  prompt "{message}"
end
