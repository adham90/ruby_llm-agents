# frozen_string_literal: true

module RubyLLM
  module Agents
    module Reliability
      # Manages circuit breakers for multiple models
      #
      # Provides centralized access to circuit breakers with
      # multi-tenant support and caching.
      #
      # @example
      #   manager = BreakerManager.new("MyAgent", config: { errors: 5, within: 60 })
      #   manager.open?("gpt-4o")        # => false
      #   manager.record_failure!("gpt-4o")
      #   manager.record_success!("gpt-4o")
      #
      # @api private
      class BreakerManager
        # @param agent_type [String] The agent class name
        # @param config [Hash, nil] Circuit breaker configuration
        # @param tenant_id [String, nil] Optional tenant identifier
        def initialize(agent_type, config:, tenant_id: nil)
          @agent_type = agent_type
          @config = config
          @tenant_id = tenant_id
          @breakers = {}
        end

        # Gets or creates a circuit breaker for a model
        #
        # @param model_id [String] Model identifier
        # @return [CircuitBreaker, nil] The circuit breaker or nil if not configured
        def for_model(model_id)
          return nil unless @config

          @breakers[model_id] ||= CircuitBreaker.from_config(
            @agent_type,
            model_id,
            @config,
            tenant_id: @tenant_id
          )
        end

        # Checks if a model's circuit breaker is open
        #
        # @param model_id [String] Model identifier
        # @return [Boolean] true if breaker is open
        def open?(model_id)
          breaker = for_model(model_id)
          breaker&.open? || false
        end

        # Records a success for a model
        #
        # @param model_id [String] Model identifier
        # @return [void]
        def record_success!(model_id)
          for_model(model_id)&.record_success!
        end

        # Records a failure for a model
        #
        # @param model_id [String] Model identifier
        # @return [Boolean] true if breaker is now open
        def record_failure!(model_id)
          breaker = for_model(model_id)
          breaker&.record_failure!
          breaker&.open? || false
        end

        # Checks if circuit breaker is configured
        #
        # @return [Boolean] true if config present
        def enabled?
          @config.present?
        end
      end
    end
  end
end
