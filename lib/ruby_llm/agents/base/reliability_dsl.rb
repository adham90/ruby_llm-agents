# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # DSL builder for reliability configuration
      #
      # Provides a block-based configuration syntax for grouping
      # all reliability settings together.
      #
      # @example Basic usage
      #   class MyAgent < ApplicationAgent
      #     reliability do
      #       retries max: 3, backoff: :exponential
      #       fallback_models "gpt-4o-mini"
      #       total_timeout 30
      #       circuit_breaker errors: 5, within: 60
      #     end
      #   end
      #
      # @api public
      class ReliabilityDSL
        attr_reader :retries_config, :fallback_models_list, :total_timeout_value,
                    :circuit_breaker_config, :retryable_patterns_list

        def initialize
          @retries_config = nil
          @fallback_models_list = []
          @total_timeout_value = nil
          @circuit_breaker_config = nil
          @retryable_patterns_list = nil
        end

        # Configures retry behavior
        #
        # @param max [Integer] Maximum retry attempts
        # @param backoff [Symbol] :constant or :exponential
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay between retries
        # @param on [Array<Class>] Additional error classes to retry on
        # @return [void]
        def retries(max: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [])
          @retries_config = {
            max: max,
            backoff: backoff,
            base: base,
            max_delay: max_delay,
            on: on
          }
        end

        # Sets fallback models
        #
        # @param models [Array<String>] Model identifiers
        # @return [void]
        def fallback_models(*models)
          @fallback_models_list = models.flatten
        end

        # Sets total timeout across all retry/fallback attempts
        #
        # @param seconds [Integer] Total timeout in seconds
        # @return [void]
        def total_timeout(seconds)
          @total_timeout_value = seconds
        end

        # Configures circuit breaker
        #
        # @param errors [Integer] Failure threshold
        # @param within [Integer] Rolling window in seconds
        # @param cooldown [Integer] Cooldown period in seconds
        # @return [void]
        def circuit_breaker(errors: 10, within: 60, cooldown: 300)
          @circuit_breaker_config = {
            errors: errors,
            within: within,
            cooldown: cooldown
          }
        end

        # Sets additional retryable patterns for error message matching
        #
        # These patterns are added to the global defaults from configuration.
        #
        # @param patterns [Array<String>] Pattern strings to match in error messages
        # @return [void]
        # @example
        #   retryable_patterns "my_custom_error", "another_pattern"
        def retryable_patterns(*patterns)
          @retryable_patterns_list = patterns.flatten
        end
      end
    end
  end
end
