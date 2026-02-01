# frozen_string_literal: true

require_relative 'concerns/loggable'
require_relative 'concerns/measurable'

# SentimentAgent - Analyzes text sentiment with logging and metrics
#
# Demonstrates integration of Loggable and Measurable concerns
# for monitoring and debugging sentiment analysis.
#
# Example usage:
#
#   agent = SentimentAgent.new(text: "I love this product!")
#   result = agent.call
#
#   # Check execution metrics
#   agent.execution_metrics
#   # => { duration_ms: 523.45, success: true, ... }
#
class SentimentAgent < ApplicationAgent
  # Add concern DSL and execution modules
  extend Concerns::Loggable::DSL
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution

  description 'Analyzes text sentiment as positive, negative, or neutral'
  model 'gpt-4o-mini'
  temperature 0.0

  # Logging configuration
  log_level :info
  log_format :simple
  log_include :duration, :tokens

  param :text, required: true

  def system_prompt
    'You are a sentiment analysis assistant.'
  end

  def user_prompt
    "Analyze the sentiment of this text (positive, negative, or neutral):\n\n#{text}"
  end

  # Override call to integrate concerns
  def call
    measure_execution do
      log_before_execution(text)
      record_metric(:text_length, text.length)

      result = super

      log_after_execution(result, started_at: @execution_started_at)
      result
    end
  end
end
