# frozen_string_literal: true

module RubyLLM
  module Agents
    # Base error class for RubyLLM::Agents
    class Error < StandardError; end

    # ============================================================
    # Pipeline Errors
    # ============================================================

    # Base class for pipeline-related errors
    class PipelineError < Error; end

    # ============================================================
    # Reliability Errors
    # ============================================================

    # Base class for reliability-related errors
    class ReliabilityError < Error; end

    # Raised when an error is retryable (transient)
    class RetryableError < ReliabilityError; end

    # Raised when a circuit breaker is open
    class CircuitOpenError < ReliabilityError
      # @return [String] The model that has an open circuit
      attr_reader :model

      def initialize(message = nil, model: nil)
        @model = model
        super(message || "Circuit breaker is open#{model ? " for #{model}" : ""}")
      end
    end

    # Raised when total timeout is exceeded across all attempts
    class TotalTimeoutError < ReliabilityError
      # @return [Float] The timeout that was exceeded
      attr_reader :timeout

      # @return [Float] The elapsed time
      attr_reader :elapsed

      def initialize(message = nil, timeout: nil, elapsed: nil)
        @timeout = timeout
        @elapsed = elapsed
        super(message || "Total timeout of #{timeout}s exceeded (elapsed: #{elapsed&.round(2)}s)")
      end
    end

    # Raised when all models (primary + fallbacks) fail
    class AllModelsFailedError < ReliabilityError
      # @return [Array<Hash>] Details of each failed attempt
      attr_reader :attempts

      def initialize(message = nil, attempts: [])
        @attempts = attempts
        models = attempts.map { |a| a[:model] }.compact.join(", ")
        super(message || "All models failed: #{models}")
      end
    end

    # ============================================================
    # Budget Errors
    # ============================================================

    # Base class for budget-related errors
    class BudgetError < Error; end

    # Raised when budget is exceeded
    class BudgetExceededError < BudgetError
      # @return [String, nil] The tenant ID
      attr_reader :tenant_id

      # @return [String, nil] The budget type (daily, monthly, etc.)
      attr_reader :budget_type

      def initialize(message = nil, tenant_id: nil, budget_type: nil)
        @tenant_id = tenant_id
        @budget_type = budget_type
        super(message || "Budget exceeded#{tenant_id ? " for tenant #{tenant_id}" : ""}")
      end
    end

    # ============================================================
    # Configuration Errors
    # ============================================================

    # Raised for configuration issues
    class ConfigurationError < Error; end

    # Raised when content is flagged during moderation
    #
    # Contains the full moderation result and the phase where
    # the content was flagged.
    #
    # @example Handling moderation errors
    #   begin
    #     result = MyAgent.call(message: user_input)
    #   rescue RubyLLM::Agents::ModerationError => e
    #     puts "Content blocked: #{e.flagged_categories.join(', ')}"
    #     puts "Phase: #{e.phase}"
    #     puts "Scores: #{e.category_scores}"
    #   end
    #
    # @api public
    class ModerationError < Error
      # @return [Object] The raw moderation result from RubyLLM
      attr_reader :moderation_result

      # @return [Symbol] The phase where content was flagged (:input or :output)
      attr_reader :phase

      # Creates a new ModerationError
      #
      # @param moderation_result [Object] The moderation result from RubyLLM
      # @param phase [Symbol] The phase where content was flagged
      def initialize(moderation_result, phase)
        @moderation_result = moderation_result
        @phase = phase

        categories = moderation_result.flagged_categories
        category_list = categories.respond_to?(:join) ? categories.join(", ") : categories.to_s

        super("Content flagged during #{phase} moderation: #{category_list}")
      end

      # Returns the flagged categories from the moderation result
      #
      # @return [Array<String, Symbol>] List of flagged categories
      def flagged_categories
        moderation_result.flagged_categories
      end

      # Returns the category scores from the moderation result
      #
      # @return [Hash{String, Symbol => Float}] Category to score mapping
      def category_scores
        moderation_result.category_scores
      end

      # Returns whether the moderation result was flagged
      #
      # @return [Boolean] Always true for ModerationError
      def flagged?
        true
      end
    end
  end
end
