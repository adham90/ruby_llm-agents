# frozen_string_literal: true

module RubyLLM
  module Agents
    # Execution model for tracking agent executions
    #
    # Stores all agent execution data including:
    # - Agent identification (type, version)
    # - Model configuration (model_id, temperature)
    # - Timing (started_at, completed_at, duration_ms)
    # - Token usage (input_tokens, output_tokens, cached_tokens)
    # - Costs (input_cost, output_cost, total_cost in dollars)
    # - Status (success, error, timeout)
    # - Parameters and metadata (JSONB)
    # - Error tracking (error_class, error_message)
    #
    class Execution < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_executions"

      include Execution::Metrics
      include Execution::Scopes
      include Execution::Analytics

      # Status enum
      enum :status, %w[success error timeout].index_by(&:itself), prefix: true

      # Validations
      validates :agent_type, :model_id, :started_at, presence: true
      validates :status, inclusion: { in: statuses.keys }
      validates :agent_version, presence: true
      validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
      validates :input_tokens, :output_tokens, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :input_cost, :output_cost, :total_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

      # Callbacks
      before_save :calculate_total_tokens, if: -> { input_tokens_changed? || output_tokens_changed? }
      before_save :calculate_total_cost, if: -> { input_cost_changed? || output_cost_changed? }

      private

      def calculate_total_tokens
        self.total_tokens = (input_tokens || 0) + (output_tokens || 0)
      end

      def calculate_total_cost
        self.total_cost = (input_cost || 0) + (output_cost || 0)
      end
    end
  end
end
