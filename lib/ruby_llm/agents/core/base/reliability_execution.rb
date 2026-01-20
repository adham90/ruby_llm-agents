# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Reliability execution with retry/fallback/circuit breaker support
      #
      # Handles executing agents with automatic retries, model fallbacks,
      # circuit breaker protection, and budget enforcement.
      module ReliabilityExecution
        # Executes the agent with retry/fallback/circuit breaker support
        #
        # @yield [chunk] Yields chunks when streaming is enabled
        # @return [Object] The processed response
        # @raise [Reliability::AllModelsExhaustedError] If all models fail
        # @raise [Reliability::BudgetExceededError] If budget limits exceeded
        # @raise [Reliability::TotalTimeoutError] If total timeout exceeded
        def execute_with_reliability(&block)
          config = reliability_config
          models_to_try = [model, *config[:fallback_models]].uniq
          total_deadline = config[:total_timeout] ? Time.current + config[:total_timeout] : nil
          started_at = Time.current

          # Get current tenant_id for multi-tenancy support
          global_config = RubyLLM::Agents.configuration
          tenant_id = global_config.multi_tenancy_enabled? ? global_config.current_tenant_id : nil

          # Pre-check budget (tenant_id is resolved automatically if not passed)
          BudgetTracker.check_budget!(self.class.name, tenant_id: tenant_id) if global_config.budgets_enabled?

          instrument_execution_with_attempts(models_to_try: models_to_try) do |attempt_tracker|
            last_error = nil

            models_to_try.each do |current_model|
              # Check circuit breaker (with tenant isolation if enabled)
              breaker = get_circuit_breaker(current_model, tenant_id: tenant_id)
              if breaker&.open?
                attempt_tracker.record_short_circuit(current_model)
                next
              end

              retries_remaining = config[:retries]&.dig(:max) || 0
              attempt_index = 0

              loop do
                # Check total timeout
                if total_deadline && Time.current > total_deadline
                  elapsed = Time.current - started_at
                  raise Reliability::TotalTimeoutError.new(config[:total_timeout], elapsed)
                end

                attempt = attempt_tracker.start_attempt(current_model)

                begin
                  result = execute_single_attempt(model_override: current_model, &block)
                  attempt_tracker.complete_attempt(attempt, success: true, response: @last_response)

                  # Record success in circuit breaker
                  breaker&.record_success!

                  # Record budget spend (with tenant isolation if enabled)
                  if @last_response && global_config.budgets_enabled?
                    record_attempt_cost(attempt_tracker, tenant_id: tenant_id)
                  end

                  # Use throw instead of return to allow instrument_execution_with_attempts
                  # to properly complete the execution record before returning
                  throw :execution_success, result

                rescue StandardError => e
                  last_error = e
                  attempt_tracker.complete_attempt(attempt, success: false, error: e)
                  breaker&.record_failure!

                  # Check if error is retryable (by class or message pattern)
                  custom_errors = config[:retries]&.dig(:on) || []
                  custom_patterns = config[:retryable_patterns]
                  is_retryable = Reliability.retryable_error?(
                    e,
                    custom_errors: custom_errors,
                    custom_patterns: custom_patterns
                  )

                  if is_retryable && retries_remaining > 0 && !past_deadline?(total_deadline)
                    retries_remaining -= 1
                    attempt_index += 1
                    retries_config = config[:retries] || {}
                    delay = Reliability.calculate_backoff(
                      strategy: retries_config[:backoff] || :exponential,
                      base: retries_config[:base] || 0.4,
                      max_delay: retries_config[:max_delay] || 3.0,
                      attempt: attempt_index
                    )
                    async_aware_sleep(delay)
                  else
                    break # Move to next model (non-retryable or no retries left)
                  end
                end
              end
            end

            # All models exhausted
            raise Reliability::AllModelsExhaustedError.new(models_to_try, last_error)
          end
        end

        # Checks if the total deadline has passed
        #
        # @param deadline [Time, nil] The deadline
        # @return [Boolean] true if past deadline
        def past_deadline?(deadline)
          deadline && Time.current > deadline
        end

        # Gets or creates a circuit breaker for a model
        #
        # @param model_id [String] The model identifier
        # @param tenant_id [String, nil] Optional tenant identifier for multi-tenant isolation
        # @return [CircuitBreaker, nil] The circuit breaker or nil if not configured
        def get_circuit_breaker(model_id, tenant_id: nil)
          config = reliability_config[:circuit_breaker]
          return nil unless config

          CircuitBreaker.from_config(self.class.name, model_id, config, tenant_id: tenant_id)
        end

        # Sleeps without blocking other fibers when in async context
        #
        # Automatically uses async sleep when in async context,
        # falls back to regular sleep otherwise.
        #
        # @param seconds [Numeric] Duration to sleep
        # @return [void]
        def async_aware_sleep(seconds)
          config = RubyLLM::Agents.configuration

          if config.async_context?
            ::Async::Task.current.sleep(seconds)
          else
            sleep(seconds)
          end
        end
      end
    end
  end
end
