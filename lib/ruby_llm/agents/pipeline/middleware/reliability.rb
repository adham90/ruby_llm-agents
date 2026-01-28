# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Handles retries, fallbacks, and circuit breakers.
        #
        # This middleware provides reliability features for agent executions:
        # - Retries with configurable backoff (constant or exponential)
        # - Model fallbacks when primary model fails
        # - Circuit breaker protection per model
        # - Total timeout across all attempts
        #
        # Reliability is enabled via the agent's reliability DSL:
        #   class MyAgent < ApplicationAgent
        #     reliability do
        #       retries max: 3, backoff: :exponential
        #       fallback_models "gpt-4o-mini"
        #       total_timeout 30
        #       circuit_breaker errors: 5, within: 60
        #     end
        #   end
        #
        # @example Simple retry
        #   class MyEmbedder < RubyLLM::Agents::Embedder
        #     model "text-embedding-3-small"
        #     reliability do
        #       retries max: 2
        #     end
        #   end
        #
        class Reliability < Base
          # Process with reliability features
          #
          # @param context [Context] The execution context
          # @return [Context] The context after execution
          # @raise [AllModelsFailedError] If all models fail
          # @raise [TotalTimeoutError] If total timeout exceeded
          # @raise [CircuitOpenError] If circuit breaker is open for all models
          def call(context)
            return @app.call(context) unless reliability_enabled?

            config = reliability_config
            models_to_try = build_models_list(context, config)
            total_deadline = calculate_deadline(config)

            execute_with_reliability(context, models_to_try, config, total_deadline)
          end

          private

          # Returns whether reliability is enabled for this agent
          #
          # @return [Boolean]
          def reliability_enabled?
            @agent_class&.respond_to?(:reliability_config) &&
              @agent_class.reliability_config.present?
          end

          # Returns the reliability configuration from the agent class
          #
          # @return [Hash] The reliability configuration
          def reliability_config
            @agent_class.reliability_config || {}
          end

          # Builds the list of models to try
          #
          # @param context [Context] The execution context
          # @param config [Hash] The reliability configuration
          # @return [Array<String>] List of models
          def build_models_list(context, config)
            primary = context.model || @agent_class&.model
            fallbacks = config[:fallback_models] || []
            [primary, *fallbacks].compact.uniq
          end

          # Calculates the total deadline for all attempts
          #
          # @param config [Hash] The reliability configuration
          # @return [Time, nil] The deadline or nil if no timeout
          def calculate_deadline(config)
            return nil unless config[:total_timeout]

            Time.current + config[:total_timeout]
          end

          # Executes with retry, fallback, and circuit breaker logic
          #
          # @param context [Context] The execution context
          # @param models_to_try [Array<String>] List of models to try
          # @param config [Hash] The reliability configuration
          # @param total_deadline [Time, nil] The total deadline
          # @return [Context] The context after execution
          def execute_with_reliability(context, models_to_try, config, total_deadline)
            started_at = Time.current
            last_error = nil
            context.attempts_made = 0
            tracker = Agents::AttemptTracker.new

            models_to_try.each do |current_model|
              # Check circuit breaker for this model
              breaker = get_circuit_breaker(current_model, context)
              if breaker&.open?
                debug("Circuit breaker open for #{current_model}, skipping")
                tracker.record_short_circuit(current_model)
                next
              end

              result = try_model_with_retries(
                context: context,
                model: current_model,
                config: config,
                total_deadline: total_deadline,
                started_at: started_at,
                breaker: breaker,
                tracker: tracker
              )

              if result
                context[:reliability_attempts] = tracker.to_json_array
                return result
              end

              # Capture the last error from context for the final error
              last_error = context.error
            end

            # Store attempts even on total failure
            context[:reliability_attempts] = tracker.to_json_array

            # All models exhausted
            raise Agents::Reliability::AllModelsExhaustedError.new(
              models_to_try, last_error,
              attempts: tracker.to_json_array
            )
          end

          # Tries a model with retry logic
          #
          # @param context [Context] The execution context
          # @param model [String] The model to try
          # @param config [Hash] The reliability configuration
          # @param total_deadline [Time, nil] The total deadline
          # @param started_at [Time] When execution started
          # @param breaker [CircuitBreaker, nil] The circuit breaker for this model
          # @return [Context, nil] The context if successful, nil to try next model
          def try_model_with_retries(context:, model:, config:, total_deadline:, started_at:, breaker:, tracker:)
            retries_config = config[:retries] || {}
            max_retries = retries_config[:max] || 0
            attempt_index = 0

            loop do
              # Check total timeout
              check_total_timeout!(total_deadline, started_at)

              context.attempt = attempt_index + 1
              context.attempts_made += 1

              attempt = tracker.start_attempt(model)

              begin
                # Override the model for this attempt
                original_model = context.model
                context.model = model

                @app.call(context)

                # Success - record in circuit breaker and tracker
                breaker&.record_success!
                tracker.complete_attempt(attempt, success: true, response: context.output)

                return context

              rescue StandardError => e
                context.error = e
                breaker&.record_failure!
                tracker.complete_attempt(attempt, success: false, error: e)

                # Programming errors fail immediately — no retry, no fallback
                raise if non_fallback_error?(e, config)

                # Check if we should retry
                if should_retry?(e, config, attempt_index, max_retries, total_deadline)
                  attempt_index += 1
                  delay = calculate_backoff(retries_config, attempt_index)
                  async_aware_sleep(delay)
                else
                  # Move to next model
                  return nil
                end
              ensure
                # Restore original model if we're going to retry or try another model
                context.model = original_model if context.error
              end
            end
          end

          # Checks if we've exceeded the total timeout
          #
          # @param deadline [Time, nil] The deadline
          # @param started_at [Time] When execution started
          # @raise [TotalTimeoutError] If timeout exceeded
          def check_total_timeout!(deadline, started_at)
            return unless deadline && Time.current > deadline

            elapsed = Time.current - started_at
            timeout_value = deadline - started_at + elapsed
            raise Agents::Reliability::TotalTimeoutError.new(timeout_value, elapsed)
          end

          # Determines if we should retry the error
          #
          # @param error [Exception] The error that occurred
          # @param config [Hash] The reliability configuration
          # @param attempt_index [Integer] Current attempt index
          # @param max_retries [Integer] Maximum retries allowed
          # @param total_deadline [Time, nil] The total deadline
          # @return [Boolean] Whether to retry
          def should_retry?(error, config, attempt_index, max_retries, total_deadline)
            return false if attempt_index >= max_retries
            return false if total_deadline && Time.current > total_deadline
            # Don't retry if fallback models are available — move to next model instead
            return false if has_fallback_models?(config)

            retryable_error?(error, config)
          end

          # Checks if an error is a programming error that should not trigger fallback
          #
          # @param error [Exception] The error to check
          # @param config [Hash] The reliability configuration
          # @return [Boolean] Whether the error should fail immediately
          def non_fallback_error?(error, config)
            custom_errors = config[:non_fallback_errors] || []
            Agents::Reliability.non_fallback_error?(error, custom_errors: custom_errors)
          end

          # Returns whether fallback models are configured
          #
          # @param config [Hash] The reliability configuration
          # @return [Boolean]
          def has_fallback_models?(config)
            fallbacks = config[:fallback_models]
            fallbacks.is_a?(Array) && fallbacks.any?
          end

          # Checks if an error is retryable
          #
          # @param error [Exception] The error to check
          # @param config [Hash] The reliability configuration
          # @return [Boolean] Whether the error is retryable
          def retryable_error?(error, config)
            custom_errors = config.dig(:retries, :on) || []
            custom_patterns = config[:retryable_patterns]

            Agents::Reliability.retryable_error?(
              error,
              custom_errors: custom_errors,
              custom_patterns: custom_patterns
            )
          end

          # Calculates the backoff delay
          #
          # @param retries_config [Hash] The retries configuration
          # @param attempt_index [Integer] The current attempt index
          # @return [Float] The delay in seconds
          def calculate_backoff(retries_config, attempt_index)
            Agents::Reliability.calculate_backoff(
              strategy: retries_config[:backoff] || :exponential,
              base: retries_config[:base] || 0.4,
              max_delay: retries_config[:max_delay] || 3.0,
              attempt: attempt_index
            )
          end

          # Gets or creates a circuit breaker for a model
          #
          # @param model_id [String] The model identifier
          # @param context [Context] The execution context
          # @return [CircuitBreaker, nil] The circuit breaker or nil
          def get_circuit_breaker(model_id, context)
            cb_config = reliability_config[:circuit_breaker]
            return nil unless cb_config

            CircuitBreaker.from_config(
              @agent_class&.name,
              model_id,
              cb_config,
              tenant_id: context.tenant_id
            )
          end

          # Sleeps without blocking other fibers when in async context
          #
          # @param seconds [Numeric] Duration to sleep
          # @return [void]
          def async_aware_sleep(seconds)
            config = global_config

            if config.respond_to?(:async_context?) && config.async_context?
              ::Async::Task.current.sleep(seconds)
            else
              sleep(seconds)
            end
          rescue StandardError
            # Fall back to regular sleep if async detection fails
            sleep(seconds)
          end
        end
      end
    end
  end
end
