# frozen_string_literal: true

module RubyLLM
  module Agents
    module Reliability
      # Coordinates reliability features during agent execution
      #
      # Orchestrates retry strategy, fallback routing, circuit breakers,
      # and execution constraints into a cohesive execution flow.
      #
      # @example
      #   executor = Executor.new(
      #     config: { retries: { max: 3 }, fallback_models: ["gpt-4o-mini"] },
      #     primary_model: "gpt-4o",
      #     agent_type: "MyAgent"
      #   )
      #   executor.execute { |model| call_llm(model) }
      #
      # @api private
      class Executor
        attr_reader :retry_strategy, :fallback_routing, :breaker_manager, :constraints

        # @param config [Hash] Reliability configuration
        # @param primary_model [String] Primary model identifier
        # @param agent_type [String] Agent class name
        # @param tenant_id [String, nil] Optional tenant identifier
        def initialize(config:, primary_model:, agent_type:, tenant_id: nil)
          retries_config = config[:retries] || {}

          @retry_strategy = RetryStrategy.new(
            max: retries_config[:max] || 0,
            backoff: retries_config[:backoff] || :exponential,
            base: retries_config[:base] || 0.4,
            max_delay: retries_config[:max_delay] || 3.0,
            on: retries_config[:on] || [],
            patterns: config[:retryable_patterns]
          )

          @fallback_routing = FallbackRouting.new(
            primary_model,
            fallback_models: config[:fallback_models] || []
          )

          @breaker_manager = BreakerManager.new(
            agent_type,
            config: config[:circuit_breaker],
            tenant_id: tenant_id
          )

          @constraints = ExecutionConstraints.new(
            total_timeout: config[:total_timeout]
          )

          @last_error = nil
        end

        # Returns all models that will be tried
        #
        # @return [Array<String>] Model identifiers
        def models_to_try
          fallback_routing.models
        end

        # Executes with full reliability support
        #
        # Iterates through models with retries, respecting circuit breakers
        # and timeout constraints.
        #
        # @yield [model] Block to execute with the current model
        # @yieldparam model [String] The model to use for this attempt
        # @return [Object] Result of successful execution
        # @raise [AllModelsExhaustedError] If all models fail
        # @raise [TotalTimeoutError] If total timeout exceeded
        def execute
          until fallback_routing.exhausted?
            model = fallback_routing.current_model

            # Check circuit breaker
            if breaker_manager.open?(model)
              fallback_routing.advance!
              next
            end

            # Try with retries
            result = execute_with_retries(model) { |m| yield(m) }
            return result if result

            fallback_routing.advance!
          end

          raise AllModelsExhaustedError.new(
            fallback_routing.models,
            @last_error || StandardError.new("All models failed")
          )
        end

        private

        def execute_with_retries(model)
          attempt_index = 0

          loop do
            constraints.enforce_timeout!

            begin
              result = yield(model)
              breaker_manager.record_success!(model)
              return result
            rescue => e
              @last_error = e
              breaker_manager.record_failure!(model)

              if retry_strategy.retryable?(e) && retry_strategy.should_retry?(attempt_index)
                attempt_index += 1
                sleep(retry_strategy.delay_for(attempt_index))
              else
                return nil # Move to next model
              end
            end
          end
        end
      end
    end
  end
end
