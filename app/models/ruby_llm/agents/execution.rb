# frozen_string_literal: true

module RubyLLM
  module Agents
    # ActiveRecord model for tracking agent executions
    #
    # Stores comprehensive execution data for observability and analytics.
    #
    # @!attribute [rw] agent_type
    #   @return [String] Full class name of the agent (e.g., "SearchAgent")
    # @!attribute [rw] agent_version
    #   @return [String] Version string for cache invalidation
    # @!attribute [rw] model_id
    #   @return [String] LLM model identifier used
    # @!attribute [rw] temperature
    #   @return [Float] Temperature setting used (0.0-2.0)
    # @!attribute [rw] status
    #   @return [String] Execution status: "running", "success", "error", "timeout"
    # @!attribute [rw] started_at
    #   @return [Time] When execution started
    # @!attribute [rw] completed_at
    #   @return [Time, nil] When execution completed
    # @!attribute [rw] duration_ms
    #   @return [Integer, nil] Execution duration in milliseconds
    # @!attribute [rw] input_tokens
    #   @return [Integer, nil] Number of input tokens
    # @!attribute [rw] output_tokens
    #   @return [Integer, nil] Number of output tokens
    # @!attribute [rw] total_tokens
    #   @return [Integer, nil] Sum of input and output tokens
    # @!attribute [rw] input_cost
    #   @return [BigDecimal, nil] Cost of input tokens in USD
    # @!attribute [rw] output_cost
    #   @return [BigDecimal, nil] Cost of output tokens in USD
    # @!attribute [rw] total_cost
    #   @return [BigDecimal, nil] Total cost in USD
    # @!attribute [rw] parameters
    #   @return [Hash] Sanitized parameters passed to the agent
    # @!attribute [rw] metadata
    #   @return [Hash] Custom metadata from execution_metadata hook
    # @!attribute [rw] error_class
    #   @return [String, nil] Exception class name if failed
    # @!attribute [rw] error_message
    #   @return [String, nil] Exception message if failed
    #
    # @see RubyLLM::Agents::Instrumentation
    # @api public
    class Execution < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_executions"

      include Execution::Metrics
      include Execution::Scopes
      include Execution::Analytics

      # Status enum
      # - running: execution in progress
      # - success: completed successfully
      # - error: completed with error
      # - timeout: completed due to timeout
      enum :status, %w[running success error timeout].index_by(&:itself), prefix: true

      # Validations
      validates :agent_type, :model_id, :started_at, presence: true
      validates :status, inclusion: { in: statuses.keys }
      validates :agent_version, presence: true
      validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
      validates :input_tokens, :output_tokens, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :input_cost, :output_cost, :total_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

      before_save :calculate_total_tokens, if: -> { input_tokens_changed? || output_tokens_changed? }
      before_save :calculate_total_cost, if: -> { input_cost_changed? || output_cost_changed? }
      after_commit :broadcast_execution, on: %i[create update]

      # Aggregates costs from all attempts using each attempt's model pricing
      #
      # Used for multi-attempt executions (retries/fallbacks) where different models
      # may have been used. Calculates total cost by summing individual attempt costs.
      #
      # @return [void]
      def aggregate_attempt_costs!
        return if attempts.blank?

        total_input_cost = 0
        total_output_cost = 0

        attempts.each do |attempt|
          # Skip short-circuited attempts (no actual API call made)
          next if attempt["short_circuited"]

          model_info = resolve_model_info(attempt["model_id"])
          next unless model_info&.pricing

          input_price = model_info.pricing.text_tokens&.input || 0
          output_price = model_info.pricing.text_tokens&.output || 0

          input_tokens = attempt["input_tokens"] || 0
          output_tokens = attempt["output_tokens"] || 0

          total_input_cost += (input_tokens / 1_000_000.0) * input_price
          total_output_cost += (output_tokens / 1_000_000.0) * output_price
        end

        self.input_cost = total_input_cost.round(6)
        self.output_cost = total_output_cost.round(6)
      end

      # Returns whether this execution had multiple attempts
      #
      # @return [Boolean] true if more than one attempt was made
      def has_retries?
        (attempts_count || 0) > 1
      end

      # Returns whether this execution used fallback models
      #
      # @return [Boolean] true if a different model than requested succeeded
      def used_fallback?
        chosen_model_id.present? && chosen_model_id != model_id
      end

      # Returns the successful attempt data (if any)
      #
      # @return [Hash, nil] The successful attempt or nil
      def successful_attempt
        return nil if attempts.blank?

        attempts.find { |a| a["error_class"].nil? && !a["short_circuited"] }
      end

      # Returns failed attempts
      #
      # @return [Array<Hash>] Failed attempt data
      def failed_attempts
        return [] if attempts.blank?

        attempts.select { |a| a["error_class"].present? }
      end

      # Returns short-circuited attempts (circuit breaker blocked)
      #
      # @return [Array<Hash>] Short-circuited attempt data
      def short_circuited_attempts
        return [] if attempts.blank?

        attempts.select { |a| a["short_circuited"] }
      end

      # Broadcasts execution changes via ActionCable for real-time dashboard updates
      #
      # Sends to "ruby_llm_agents:executions" channel with action, id, status, and HTML.
      #
      # @return [void]
      def broadcast_execution
        ActionCable.server.broadcast(
          "ruby_llm_agents:executions",
          {
            action: previously_new_record? ? "created" : "updated",
            id: id,
            status: status,
            html: render_execution_html
          }
        )
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to broadcast execution: #{e.message}")
      end

      private

      # Renders the execution partial for ActionCable broadcast
      #
      # @return [String, nil] HTML string or nil if partial unavailable
      def render_execution_html
        ApplicationController.render(
          partial: "rubyllm/agents/dashboard/execution_item",
          locals: { execution: self }
        )
      rescue StandardError
        # Partial may not exist in all contexts
        nil
      end

      # Calculates and sets total_tokens from input and output
      #
      # @return [Integer] The calculated total
      def calculate_total_tokens
        self.total_tokens = (input_tokens || 0) + (output_tokens || 0)
      end

      # Calculates and sets total_cost from input and output costs
      #
      # @return [BigDecimal] The calculated total
      def calculate_total_cost
        self.total_cost = (input_cost || 0) + (output_cost || 0)
      end

      # Resolves model info for cost calculation
      #
      # @param model_id [String] The model identifier
      # @return [Object, nil] Model info or nil
      def resolve_model_info(model_id)
        return nil unless model_id

        RubyLLM::Models.resolve(model_id)
      rescue StandardError
        nil
      end
    end
  end
end
