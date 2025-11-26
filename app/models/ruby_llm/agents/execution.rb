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

      # Allowed finish reasons from LLM providers
      FINISH_REASONS = %w[stop length content_filter tool_calls other].freeze

      # Allowed fallback reasons for model switching
      FALLBACK_REASONS = %w[price_limit quality_fail rate_limit timeout safety error other].freeze

      # Execution hierarchy associations
      belongs_to :parent_execution, class_name: "RubyLLM::Agents::Execution", optional: true
      belongs_to :root_execution, class_name: "RubyLLM::Agents::Execution", optional: true
      has_many :child_executions, class_name: "RubyLLM::Agents::Execution",
               foreign_key: :parent_execution_id, dependent: :nullify, inverse_of: :parent_execution

      # Validations
      validates :agent_type, :model_id, :started_at, presence: true
      validates :status, inclusion: { in: statuses.keys }
      validates :agent_version, presence: true
      validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
      validates :input_tokens, :output_tokens, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :input_cost, :output_cost, :total_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :finish_reason, inclusion: { in: FINISH_REASONS }, allow_nil: true
      validates :fallback_reason, inclusion: { in: FALLBACK_REASONS }, allow_nil: true
      validates :time_to_first_token_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

      before_save :calculate_total_tokens, if: -> { input_tokens_changed? || output_tokens_changed? }
      before_save :calculate_total_cost, if: -> { input_cost_changed? || output_cost_changed? }
      after_commit :broadcast_turbo_streams, on: %i[create update]

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

      # Returns whether this is a root (top-level) execution
      #
      # @return [Boolean] true if this is a root execution
      def root?
        parent_execution_id.nil?
      end

      # Returns whether this is a child (nested) execution
      #
      # @return [Boolean] true if this has a parent execution
      def child?
        parent_execution_id.present?
      end

      # Returns the execution tree depth
      #
      # @return [Integer] depth level (0 for root)
      def depth
        return 0 if root?

        parent_execution&.depth.to_i + 1
      end

      # Returns whether this execution was a cache hit
      #
      # @return [Boolean] true if response was served from cache
      def cached?
        cache_hit == true
      end

      # Returns whether this execution was rate limited
      #
      # @return [Boolean] true if rate limiting occurred
      def rate_limited?
        rate_limited == true
      end

      # Returns whether this execution used streaming
      #
      # @return [Boolean] true if streaming was enabled
      def streaming?
        streaming == true
      end

      # Returns whether the response was truncated due to max_tokens
      #
      # @return [Boolean] true if hit token limit
      def truncated?
        finish_reason == "length"
      end

      # Returns whether the response was blocked by content filter
      #
      # @return [Boolean] true if blocked by safety filter
      def content_filtered?
        finish_reason == "content_filter"
      end

      # Returns real-time dashboard data for the Now Strip
      #
      # @return [Hash] Now strip metrics
      def self.now_strip_data
        {
          running: running.count,
          errors_15m: status_error.where("created_at > ?", 15.minutes.ago).count,
          cost_today: today.sum(:total_cost) || 0,
          executions_today: today.count,
          success_rate: calculate_today_success_rate
        }
      end

      # Calculates today's success rate
      #
      # @return [Float] Success rate as percentage
      def self.calculate_today_success_rate
        total = today.count
        return 0.0 if total.zero?

        (today.successful.count.to_f / total * 100).round(1)
      end

      # Broadcasts execution changes via ActionCable for real-time dashboard updates
      #
      # Sends JSON with action, id, status, and rendered HTML partials.
      # The JavaScript client handles DOM updates based on the action type.
      #
      # @return [void]
      def broadcast_turbo_streams
        ActionCable.server.broadcast(
          "ruby_llm_agents:executions",
          {
            action: previously_new_record? ? "created" : "updated",
            id: id,
            status: status,
            html: render_execution_html,
            now_strip_html: render_now_strip_html
          }
        )
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to broadcast execution: #{e.message}")
      end

      private

      # Renders the execution item partial for broadcast
      #
      # @return [String, nil] HTML string or nil if rendering fails
      def render_execution_html
        ApplicationController.render(
          partial: "rubyllm/agents/dashboard/execution_item",
          locals: { execution: self }
        )
      rescue StandardError
        nil
      end

      # Renders the Now Strip values partial for broadcast
      #
      # @return [String, nil] HTML string or nil if rendering fails
      def render_now_strip_html
        ApplicationController.render(
          partial: "rubyllm/agents/dashboard/now_strip_values",
          locals: { now_strip: self.class.now_strip_data }
        )
      rescue StandardError
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
      # @param lookup_model_id [String, nil] The model identifier (defaults to self.model_id)
      # @return [Object, nil] Model info or nil
      def resolve_model_info(lookup_model_id = nil)
        lookup_model_id ||= model_id
        return nil unless lookup_model_id

        model, _provider = RubyLLM::Models.resolve(lookup_model_id)
        model
      rescue StandardError
        nil
      end
    end
  end
end
