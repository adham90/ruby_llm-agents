# frozen_string_literal: true

require_relative 'concerns/loggable'
require_relative 'concerns/measurable'
require_relative 'concerns/validatable'
require_relative 'concerns/contextual'

# ConcernsShowcaseAgent - Demonstrates all example concerns working together
#
# This agent showcases how to combine multiple concerns for:
# - Logging (before/after execution with configurable format)
# - Metrics (performance timing and token tracking)
# - Validation (declarative input validation)
# - Context (user/request context injection)
#
# Example usage:
#
#   # Basic usage with validation
#   agent = ConcernsShowcaseAgent.new(
#     query: "What is the weather like?",
#     priority: "high"
#   )
#   agent.valid?  # => true
#   agent.call    # => Executes with logging and metrics
#
#   # With user context
#   agent = ConcernsShowcaseAgent.new(
#     query: "Hello world",
#     current_user: OpenStruct.new(id: 42, name: "Alice"),
#     priority: "normal"
#   )
#   agent.resolved_context
#   # => { user_id: 42, user_name: "Alice", timezone: "UTC" }
#   agent.context_prompt_prefix
#   # => "Context:\n- User id: 42\n- User name: Alice\n- Timezone: UTC"
#
#   # After execution, check metrics
#   result = agent.call
#   agent.execution_metrics
#   # => { duration_ms: 1234.56, success: true, ... }
#   agent.performance_summary
#   # => { agent: "ConcernsShowcaseAgent", duration_ms: 1234.56, ... }
#
#   # Validation errors
#   bad_agent = ConcernsShowcaseAgent.new(query: "hi", priority: "invalid")
#   bad_agent.valid?  # => false
#   bad_agent.validation_errors
#   # => ["query is too short (minimum 3 characters)", "priority must be one of: low, normal, high, urgent"]
#
class ConcernsShowcaseAgent < ApplicationAgent
  # ===========================================
  # Extend DSL modules (class-level configuration)
  # ===========================================
  extend Concerns::Loggable::DSL
  extend Concerns::Validatable::DSL
  extend Concerns::Contextual::DSL

  # ===========================================
  # Include Execution modules (instance methods)
  # ===========================================
  include Concerns::Loggable::Execution
  include Concerns::Measurable::Execution
  include Concerns::Validatable::Execution
  include Concerns::Contextual::Execution

  # ===========================================
  # Agent Configuration
  # ===========================================
  description 'Showcases all example concerns working together'
  model 'gpt-4o-mini'
  temperature 0.7

  # ===========================================
  # Logging Configuration
  # ===========================================
  log_level :info
  log_format :detailed
  log_include :input, :output, :duration, :tokens, :model

  # ===========================================
  # Validation Rules
  # ===========================================
  validates_presence_of :query
  validates_length_of :query, min: 3, max: 1000
  validate :priority, inclusion: %w[low normal high urgent]

  # ===========================================
  # Context Configuration
  # ===========================================
  context_from :current_user, :options
  context_includes :user_id, :user_name, :timezone, :locale
  default_context timezone: 'UTC', locale: 'en'

  # ===========================================
  # Parameters
  # ===========================================
  param :query, required: true
  param :priority, default: 'normal'
  param :current_user, default: nil

  # ===========================================
  # Prompts
  # ===========================================

  def system_prompt
    base_prompt = <<~PROMPT
      You are a helpful assistant demonstrating the concerns showcase agent.
      Respond helpfully to user queries while being aware of their context.
    PROMPT

    # Inject context into system prompt if available
    context_prefix = context_prompt_prefix
    if context_prefix.present?
      "#{base_prompt}\n\n#{context_prefix}"
    else
      base_prompt
    end
  end

  def user_prompt
    query
  end

  # ===========================================
  # Execution with Concerns Integration
  # ===========================================

  # Override call to integrate all concerns
  def call
    # Validate input first
    validate!

    # Measure and log execution
    measure_execution do
      log_before_execution(user_prompt)
      record_metric(:priority, priority)
      record_metric(:context_fields, resolved_context.keys.count)

      result = super

      # Extract and record token usage if available
      record_token_metrics(result) if result.respond_to?(:usage)

      log_after_execution(result, started_at: @execution_started_at)
      result
    end
  rescue Concerns::Validatable::Execution::ValidationError => e
    log_error(e)
    raise
  end

  private

  def record_token_metrics(result)
    usage = result.usage
    return unless usage

    record_token_usage(
      input_tokens: usage[:input_tokens] || 0,
      output_tokens: usage[:output_tokens] || 0,
      model: self.class.model
    )
  end

  # Custom validation example
  validates_with :validate_query_not_spam

  def validate_query_not_spam
    return unless query.to_s.downcase.include?('buy now')

    @validation_errors ||= []
    @validation_errors << 'query appears to contain spam content'
  end
end
