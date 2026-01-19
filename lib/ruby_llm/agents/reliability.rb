# frozen_string_literal: true

module RubyLLM
  module Agents
    # Reliability module providing error classes and utilities for retry/fallback logic
    #
    # This module defines custom error types for reliability features and provides
    # utilities for determining which errors are retryable.
    #
    # @example Checking if an error is retryable
    #   Reliability.retryable_error?(Timeout::Error.new)  # => true
    #   Reliability.retryable_error?(ArgumentError.new)   # => false
    #
    # @see RubyLLM::Agents::Base
    # @api public
    module Reliability
      # Base error class for all reliability-related errors
      #
      # @api public
      class Error < StandardError; end

      # Raised when the circuit breaker is open and requests are being blocked
      #
      # @example
      #   raise CircuitBreakerOpenError.new("MyAgent", "gpt-4o")
      #
      # @api public
      class CircuitBreakerOpenError < Error
        attr_reader :agent_type, :model_id

        # @param agent_type [String] The agent class name
        # @param model_id [String] The model identifier
        def initialize(agent_type, model_id)
          @agent_type = agent_type
          @model_id = model_id
          super("Circuit breaker is open for #{agent_type} with model #{model_id}")
        end
      end

      # Raised when budget limits have been exceeded
      #
      # @example
      #   raise BudgetExceededError.new(:global_daily, 25.0, 27.5)
      #
      # @example With tenant
      #   raise BudgetExceededError.new(:global_daily, 25.0, 27.5, tenant_id: "acme")
      #
      # @api public
      class BudgetExceededError < Error
        attr_reader :scope, :limit, :current, :agent_type, :tenant_id

        # @param scope [Symbol] The budget scope (:global_daily, :global_monthly, :per_agent_daily, etc.)
        # @param limit [Float] The budget limit in USD
        # @param current [Float] The current spend in USD
        # @param agent_type [String, nil] The agent type for per-agent budgets
        # @param tenant_id [String, nil] The tenant identifier for multi-tenant budgets
        def initialize(scope, limit, current, agent_type: nil, tenant_id: nil)
          @scope = scope
          @limit = limit
          @current = current
          @agent_type = agent_type
          @tenant_id = tenant_id

          message = "Budget exceeded for #{scope}"
          message += " (tenant: #{tenant_id})" if tenant_id
          message += " (#{agent_type})" if agent_type
          message += ": limit $#{limit}, current $#{current}"
          super(message)
        end
      end

      # Raised when the total timeout for all retry/fallback attempts is exceeded
      #
      # @api public
      class TotalTimeoutError < Error
        attr_reader :timeout_seconds, :elapsed_seconds

        # @param timeout_seconds [Integer] The configured total timeout
        # @param elapsed_seconds [Float] The elapsed time when timeout occurred
        def initialize(timeout_seconds, elapsed_seconds)
          @timeout_seconds = timeout_seconds
          @elapsed_seconds = elapsed_seconds
          super("Total timeout of #{timeout_seconds}s exceeded (elapsed: #{elapsed_seconds.round(2)}s)")
        end
      end

      # Raised when all models in the fallback chain have been exhausted
      #
      # @api public
      class AllModelsExhaustedError < Error
        attr_reader :models_tried, :last_error

        # @param models_tried [Array<String>] List of models that were attempted
        # @param last_error [Exception] The last error that occurred
        def initialize(models_tried, last_error)
          @models_tried = models_tried
          @last_error = last_error
          super("All models exhausted: #{models_tried.join(', ')}. Last error: #{last_error.message}")
        end
      end

      class << self
        # Default list of error classes that are considered retryable
        #
        # These errors typically indicate transient issues that may resolve on retry.
        #
        # @return [Array<Class>] Error classes that are retryable by default
        def default_retryable_errors
          @default_retryable_errors ||= [
            Timeout::Error,
            defined?(Net::OpenTimeout) ? Net::OpenTimeout : nil,
            defined?(Net::ReadTimeout) ? Net::ReadTimeout : nil,
            defined?(Faraday::TimeoutError) ? Faraday::TimeoutError : nil,
            defined?(Faraday::ConnectionFailed) ? Faraday::ConnectionFailed : nil,
            defined?(Errno::ECONNREFUSED) ? Errno::ECONNREFUSED : nil,
            defined?(Errno::ECONNRESET) ? Errno::ECONNRESET : nil,
            defined?(Errno::ETIMEDOUT) ? Errno::ETIMEDOUT : nil,
            defined?(SocketError) ? SocketError : nil,
            defined?(OpenSSL::SSL::SSLError) ? OpenSSL::SSL::SSLError : nil
          ].compact
        end

        # Determines if an error is retryable based on default and custom error classes
        #
        # @param error [Exception] The error to check
        # @param custom_errors [Array<Class>] Additional error classes to consider retryable
        # @param custom_patterns [Array<String>, nil] Additional patterns to check in error messages
        # @return [Boolean] true if the error is retryable
        def retryable_error?(error, custom_errors: [], custom_patterns: nil)
          all_retryable = default_retryable_errors + Array(custom_errors)
          all_retryable.any? { |klass| error.is_a?(klass) } ||
            retryable_by_message?(error, custom_patterns: custom_patterns)
        end

        # Determines if an error is retryable based on its message content
        #
        # Some errors (like HTTP 5xx responses) may not have specific error classes
        # but can be identified by their message.
        #
        # @param error [Exception] The error to check
        # @param custom_patterns [Array<String>, nil] Additional patterns to check
        # @return [Boolean] true if the error message indicates a retryable condition
        def retryable_by_message?(error, custom_patterns: nil)
          message = error.message.to_s.downcase
          retryable_patterns(custom_patterns: custom_patterns).any? { |pattern| message.include?(pattern) }
        end

        # Patterns in error messages that indicate retryable errors
        #
        # @param custom_patterns [Array<String>, nil] Additional patterns to include
        # @return [Array<String>] Patterns to match against error messages
        def retryable_patterns(custom_patterns: nil)
          base = RubyLLM::Agents.configuration.all_retryable_patterns
          custom_patterns ? (base + Array(custom_patterns)).uniq : base
        end

        # Calculates the backoff delay for a retry attempt
        #
        # @param strategy [Symbol] The backoff strategy (:constant or :exponential)
        # @param base [Float] The base delay in seconds
        # @param max_delay [Float] The maximum delay in seconds
        # @param attempt [Integer] The current attempt number (0-indexed)
        # @return [Float] The delay in seconds (including jitter)
        def calculate_backoff(strategy:, base:, max_delay:, attempt:)
          delay = case strategy
          when :constant
            base
          when :exponential
            [base * (2**attempt), max_delay].min
          else
            base
          end

          # Add jitter (0 to 50% of delay)
          jitter = rand * delay * 0.5
          delay + jitter
        end
      end
    end
  end
end
