# frozen_string_literal: true

module RubyLLM
  module Agents
    module Reliability
      # Handles retry logic with configurable backoff strategies
      #
      # Provides exponential and constant backoff with jitter,
      # retry counting, and delay calculation.
      #
      # @example
      #   strategy = RetryStrategy.new(max: 3, backoff: :exponential, base: 0.4)
      #   strategy.should_retry?(attempt_index) # => true/false
      #   strategy.delay_for(attempt_index)     # => 0.6 (with jitter)
      #
      # @api private
      class RetryStrategy
        attr_reader :max, :backoff, :base, :max_delay, :custom_errors, :custom_patterns

        # @param max [Integer] Maximum retry attempts
        # @param backoff [Symbol] :constant or :exponential
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay cap
        # @param on [Array<Class>] Additional error classes to retry on
        # @param patterns [Array<String>, nil] Additional patterns to match in error messages
        def initialize(max: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [], patterns: nil)
          @max = max
          @backoff = backoff
          @base = base
          @max_delay = max_delay
          @custom_errors = Array(on)
          @custom_patterns = patterns
        end

        # Determines if retry should occur
        #
        # @param attempt_index [Integer] Current attempt number (0-indexed)
        # @return [Boolean] true if should retry
        def should_retry?(attempt_index)
          attempt_index < max
        end

        # Calculates delay before next retry
        #
        # @param attempt_index [Integer] Current attempt number
        # @return [Float] Delay in seconds (includes jitter)
        def delay_for(attempt_index)
          base_delay = case backoff
          when :constant
            base
          when :exponential
            [base * (2**attempt_index), max_delay].min
          else
            base
          end

          # Add jitter (0-50% of base delay)
          base_delay + (rand * base_delay * 0.5)
        end

        # Checks if an error is retryable
        #
        # @param error [Exception] The error to check
        # @return [Boolean] true if retryable
        def retryable?(error)
          RubyLLM::Agents::Reliability.retryable_error?(
            error,
            custom_errors: custom_errors,
            custom_patterns: custom_patterns
          )
        end

        # Returns all retryable error classes
        #
        # @return [Array<Class>] Error classes to retry on
        def retryable_errors
          RubyLLM::Agents::Reliability.default_retryable_errors + custom_errors
        end
      end
    end
  end
end
