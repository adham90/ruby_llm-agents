# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Reliability DSL for retries, fallbacks, and circuit breakers.
      #
      # This module provides configuration methods for reliability features
      # that can be mixed into any agent class.
      #
      # @example Block-style configuration
      #   class MyAgent < RubyLLM::Agents::BaseAgent
      #     extend DSL::Reliability
      #
      #     reliability do
      #       retries max: 3, backoff: :exponential
      #       fallback_models "gpt-4o-mini"
      #       total_timeout 30
      #       circuit_breaker errors: 5, within: 60
      #     end
      #   end
      #
      # @example Individual method configuration
      #   class MyAgent < RubyLLM::Agents::BaseAgent
      #     extend DSL::Reliability
      #
      #     retries max: 3
      #     fallback_models "gpt-4o-mini", "gpt-3.5-turbo"
      #   end
      #
      module Reliability
        # @!group Reliability DSL

        # Configures reliability features using a block syntax
        #
        # Groups all reliability configuration in a single block for clarity.
        #
        # @yield Block containing reliability configuration
        # @return [void]
        # @example
        #   reliability do
        #     retries max: 3, backoff: :exponential
        #     fallback_models "gpt-4o-mini"
        #     total_timeout 30
        #     circuit_breaker errors: 5
        #   end
        def reliability(&block)
          builder = ReliabilityBuilder.new
          builder.instance_eval(&block)

          @retries_config = builder.retries_config if builder.retries_config
          @fallback_models = builder.fallback_models_list if builder.fallback_models_list.any?
          @fallback_providers = builder.fallback_providers_list if builder.fallback_providers_list.any?
          @total_timeout = builder.total_timeout_value if builder.total_timeout_value
          @circuit_breaker_config = builder.circuit_breaker_config if builder.circuit_breaker_config
          @retryable_patterns = builder.retryable_patterns_list if builder.retryable_patterns_list
          @non_fallback_errors = builder.non_fallback_errors_list if builder.non_fallback_errors_list
        end

        # Alias for reliability with clearer intent-revealing name
        #
        # Configures what happens when an LLM call fails.
        # This is the preferred method in the simplified DSL.
        #
        # @yield Block containing failure handling configuration
        # @return [void]
        #
        # @example
        #   on_failure do
        #     retry times: 3, backoff: :exponential
        #     fallback to: ["gpt-4o-mini", "gpt-3.5-turbo"]
        #     circuit_breaker after: 5, cooldown: 5.minutes
        #     timeout 30.seconds
        #   end
        #
        def on_failure(&block)
          builder = OnFailureBuilder.new
          builder.instance_eval(&block)

          @retries_config = builder.retries_config if builder.retries_config
          @fallback_models = builder.fallback_models_list if builder.fallback_models_list.any?
          @fallback_providers = builder.fallback_providers_list if builder.fallback_providers_list.any?
          @total_timeout = builder.total_timeout_value if builder.total_timeout_value
          @circuit_breaker_config = builder.circuit_breaker_config if builder.circuit_breaker_config
          @retryable_patterns = builder.retryable_patterns_list if builder.retryable_patterns_list
          @non_fallback_errors = builder.non_fallback_errors_list if builder.non_fallback_errors_list
        end

        # Returns the complete reliability configuration hash
        #
        # Used by the Reliability middleware to get all settings.
        #
        # @return [Hash, nil] The reliability configuration
        def reliability_config
          return nil unless reliability_configured?

          {
            retries: retries_config,
            fallback_models: fallback_models,
            fallback_providers: fallback_providers,
            total_timeout: total_timeout,
            circuit_breaker: circuit_breaker_config,
            retryable_patterns: retryable_patterns,
            non_fallback_errors: non_fallback_errors
          }.compact
        end

        # Checks if any reliability features are configured
        #
        # @return [Boolean] true if reliability is configured
        def reliability_configured?
          (retries_config && retries_config[:max]&.positive?) ||
            fallback_models.any? ||
            fallback_providers.any? ||
            circuit_breaker_config.present?
        end

        # Configures retry behavior for this agent
        #
        # @param max [Integer] Maximum number of retry attempts (default: 0)
        # @param backoff [Symbol] Backoff strategy (:constant or :exponential)
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay between retries
        # @param on [Array<Class>] Error classes to retry on (extends defaults)
        # @return [Hash] The current retry configuration
        # @example
        #   retries max: 2, backoff: :exponential
        def retries(max: nil, backoff: nil, base: nil, max_delay: nil, on: nil)
          if max || backoff || base || max_delay || on
            @retries_config ||= default_retries_config.dup
            @retries_config[:max] = max if max
            @retries_config[:backoff] = backoff if backoff
            @retries_config[:base] = base if base
            @retries_config[:max_delay] = max_delay if max_delay
            @retries_config[:on] = on if on
          end
          @retries_config || inherited_retry_config || default_retries_config
        end

        # Returns the retry configuration
        #
        # @return [Hash, nil] The retry configuration
        def retries_config
          @retries_config || inherited_retry_config
        end

        # Sets or returns fallback models to try when primary model fails
        #
        # @param models [Array<String>] Model identifiers to use as fallbacks
        # @return [Array<String>] The current fallback models
        # @example
        #   fallback_models "gpt-4o-mini", "gpt-3.5-turbo"
        def fallback_models(*models)
          @fallback_models = models.flatten if models.any?
          @fallback_models || inherited_fallback_models || []
        end

        # Sets or returns fallback providers to try when primary provider fails
        #
        # Used primarily by audio agents (Speaker, Transcriber) that may need
        # to fall back to a different provider entirely.
        #
        # @param provider [Symbol] The provider to fall back to
        # @param options [Hash] Provider-specific options (e.g., voice:, model:)
        # @return [Array<Hash>] The current fallback providers
        # @example
        #   fallback_provider :openai, voice: "nova"
        def fallback_provider(provider = nil, **options)
          if provider
            @fallback_providers ||= []
            @fallback_providers << { provider: provider, **options }
          end
          @fallback_providers || inherited_fallback_providers || []
        end

        # Returns the fallback providers list
        #
        # @return [Array<Hash>] The fallback providers
        def fallback_providers
          @fallback_providers || inherited_fallback_providers || []
        end

        # Sets or returns the total timeout for all retry/fallback attempts
        #
        # @param seconds [Integer, nil] Total timeout in seconds
        # @return [Integer, nil] The current total timeout
        # @example
        #   total_timeout 30
        def total_timeout(seconds = nil)
          @total_timeout = seconds if seconds
          @total_timeout || inherited_total_timeout
        end

        # Configures circuit breaker for this agent
        #
        # @param errors [Integer] Number of errors to trigger open state
        # @param within [Integer] Rolling window in seconds
        # @param cooldown [Integer] Cooldown period in seconds when open
        # @return [Hash, nil] The current circuit breaker configuration
        # @example
        #   circuit_breaker errors: 10, within: 60, cooldown: 300
        def circuit_breaker(errors: nil, within: nil, cooldown: nil)
          if errors || within || cooldown
            @circuit_breaker_config ||= { errors: 10, within: 60, cooldown: 300 }
            @circuit_breaker_config[:errors] = errors if errors
            @circuit_breaker_config[:within] = within if within
            @circuit_breaker_config[:cooldown] = cooldown if cooldown
          end
          @circuit_breaker_config || inherited_circuit_breaker_config
        end

        # Returns the circuit breaker configuration
        #
        # @return [Hash, nil] The circuit breaker configuration
        def circuit_breaker_config
          @circuit_breaker_config || inherited_circuit_breaker_config
        end

        # Sets or returns additional retryable patterns for error message matching
        #
        # @param patterns [Array<String>] Pattern strings to match in error messages
        # @return [Array<String>, nil] The current retryable patterns
        # @example
        #   retryable_patterns "custom_error", "another_pattern"
        def retryable_patterns(*patterns)
          @retryable_patterns = patterns.flatten if patterns.any?
          @retryable_patterns || inherited_retryable_patterns
        end

        # Sets or returns additional error classes that should never trigger fallback
        #
        # @param error_classes [Array<Class>] Error classes that should fail immediately
        # @return [Array<Class>, nil] The current non-fallback error classes
        # @example
        #   non_fallback_errors MyValidationError, MySchemaError
        def non_fallback_errors(*error_classes)
          @non_fallback_errors = error_classes.flatten if error_classes.any?
          @non_fallback_errors || inherited_non_fallback_errors
        end

        # @!endgroup

        private

        def inherited_retry_config
          return nil unless superclass.respond_to?(:retries_config)

          superclass.retries_config
        end

        def inherited_fallback_models
          return nil unless superclass.respond_to?(:fallback_models)

          superclass.fallback_models
        end

        def inherited_fallback_providers
          return nil unless superclass.respond_to?(:fallback_providers)

          superclass.fallback_providers
        end

        def inherited_total_timeout
          return nil unless superclass.respond_to?(:total_timeout)

          superclass.total_timeout
        end

        def inherited_circuit_breaker_config
          return nil unless superclass.respond_to?(:circuit_breaker_config)

          superclass.circuit_breaker_config
        end

        def inherited_retryable_patterns
          return nil unless superclass.respond_to?(:retryable_patterns)

          superclass.retryable_patterns
        end

        def inherited_non_fallback_errors
          return nil unless superclass.respond_to?(:non_fallback_errors)

          superclass.non_fallback_errors
        end

        def default_retries_config
          {
            max: 0,
            backoff: :exponential,
            base: 0.4,
            max_delay: 3.0,
            on: []
          }
        end

        # Inner builder class for block-style configuration
        class ReliabilityBuilder
          attr_reader :retries_config, :fallback_models_list, :total_timeout_value,
                      :circuit_breaker_config, :retryable_patterns_list, :fallback_providers_list,
                      :non_fallback_errors_list

          def initialize
            @retries_config = nil
            @fallback_models_list = []
            @total_timeout_value = nil
            @circuit_breaker_config = nil
            @retryable_patterns_list = nil
            @fallback_providers_list = []
            @non_fallback_errors_list = nil
          end

          def retries(max: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [])
            @retries_config = {
              max: max,
              backoff: backoff,
              base: base,
              max_delay: max_delay,
              on: on
            }
          end

          def fallback_models(*models)
            @fallback_models_list = models.flatten
          end

          # Configures a fallback provider with optional settings
          #
          # @param provider [Symbol] The provider to fall back to (e.g., :openai, :elevenlabs)
          # @param options [Hash] Provider-specific options (e.g., voice:, model:)
          # @example
          #   fallback_provider :openai, voice: "nova"
          #   fallback_provider :elevenlabs, voice: "Rachel", model: "eleven_multilingual_v2"
          def fallback_provider(provider, **options)
            @fallback_providers_list << { provider: provider, **options }
          end

          def total_timeout(seconds)
            @total_timeout_value = seconds
          end

          def circuit_breaker(errors: 10, within: 60, cooldown: 300)
            @circuit_breaker_config = {
              errors: errors,
              within: within,
              cooldown: cooldown
            }
          end

          def retryable_patterns(*patterns)
            @retryable_patterns_list = patterns.flatten
          end

          def non_fallback_errors(*error_classes)
            @non_fallback_errors_list = error_classes.flatten
          end
        end

        # Builder class for on_failure block with simplified syntax
        #
        # Uses more intuitive method names:
        # - `retry times:` instead of `retries max:`
        # - `fallback to:` instead of `fallback_models`
        # - `circuit_breaker after:` instead of `circuit_breaker errors:`
        # - `timeout` instead of `total_timeout`
        #
        class OnFailureBuilder
          attr_reader :retries_config, :fallback_models_list, :total_timeout_value,
                      :circuit_breaker_config, :retryable_patterns_list, :fallback_providers_list,
                      :non_fallback_errors_list

          def initialize
            @retries_config = nil
            @fallback_models_list = []
            @total_timeout_value = nil
            @circuit_breaker_config = nil
            @retryable_patterns_list = nil
            @fallback_providers_list = []
            @non_fallback_errors_list = nil
          end

          # Configure retry behavior
          #
          # @param times [Integer] Number of retry attempts
          # @param backoff [Symbol] Backoff strategy (:constant or :exponential)
          # @param base [Float] Base delay in seconds
          # @param max_delay [Float] Maximum delay between retries
          # @param on [Array<Class>] Error classes to retry on
          #
          # @example
          #   retries times: 3, backoff: :exponential
          #
          def retries(times: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [])
            @retries_config = {
              max: times,
              backoff: backoff,
              base: base,
              max_delay: max_delay,
              on: on
            }
          end

          # Configure fallback models
          #
          # @param to [String, Array<String>] Model(s) to fall back to
          #
          # @example
          #   fallback to: "gpt-4o-mini"
          #   fallback to: ["gpt-4o-mini", "gpt-3.5-turbo"]
          #
          def fallback(to:)
            @fallback_models_list = Array(to)
          end

          # Also support fallback_models for compatibility
          def fallback_models(*models)
            @fallback_models_list = models.flatten
          end

          # Configure a fallback provider (for audio agents)
          #
          # @param provider [Symbol] The provider to fall back to
          # @param options [Hash] Provider-specific options
          #
          def fallback_provider(provider, **options)
            @fallback_providers_list << { provider: provider, **options }
          end

          # Configure timeout for all retry/fallback attempts
          #
          # @param duration [Integer, ActiveSupport::Duration] Timeout duration
          #
          # @example
          #   timeout 30
          #   timeout 30.seconds
          #
          def timeout(duration)
            # Handle ActiveSupport::Duration
            @total_timeout_value = duration.respond_to?(:to_i) ? duration.to_i : duration
          end

          # Also support total_timeout for compatibility
          alias total_timeout timeout

          # Configure circuit breaker
          #
          # @param after [Integer] Number of errors to trigger open state
          # @param errors [Integer] Alias for after (compatibility)
          # @param within [Integer] Rolling window in seconds
          # @param cooldown [Integer, ActiveSupport::Duration] Cooldown period
          #
          # @example
          #   circuit_breaker after: 5, cooldown: 5.minutes
          #   circuit_breaker errors: 10, within: 60, cooldown: 300
          #
          def circuit_breaker(after: nil, errors: nil, within: 60, cooldown: 300)
            error_threshold = after || errors || 10
            cooldown_seconds = cooldown.respond_to?(:to_i) ? cooldown.to_i : cooldown

            @circuit_breaker_config = {
              errors: error_threshold,
              within: within,
              cooldown: cooldown_seconds
            }
          end

          # Configure additional retryable patterns
          def retryable_patterns(*patterns)
            @retryable_patterns_list = patterns.flatten
          end

          # Configure errors that should never trigger fallback
          def non_fallback_errors(*error_classes)
            @non_fallback_errors_list = error_classes.flatten
          end
        end
      end
    end
  end
end
