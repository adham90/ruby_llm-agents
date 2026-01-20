# frozen_string_literal: true

require_relative "cache_helper"

module RubyLLM
  module Agents
    # Cache-based circuit breaker for protecting against cascading failures
    #
    # Implements a simple circuit breaker pattern using Rails.cache:
    # - Tracks failure counts in a rolling window
    # - Opens the breaker when failure threshold is reached
    # - Stays open for a cooldown period
    # - Automatically closes after cooldown expires
    #
    # In multi-tenant mode, circuit breakers are isolated per tenant,
    # so one tenant's failures don't affect other tenants.
    #
    # @example Basic usage
    #   breaker = CircuitBreaker.new("MyAgent", "gpt-4o", errors: 10, within: 60, cooldown: 300)
    #   breaker.open?         # => false
    #   breaker.record_failure!
    #   # ... after 10 failures within 60 seconds ...
    #   breaker.open?         # => true
    #
    # @example Multi-tenant usage
    #   breaker = CircuitBreaker.new("MyAgent", "gpt-4o", tenant_id: "acme", errors: 10)
    #   breaker.open?  # Isolated to "acme" tenant
    #
    # @see RubyLLM::Agents::Reliability
    # @api public
    class CircuitBreaker
      include CacheHelper
      attr_reader :agent_type, :model_id, :tenant_id, :errors_threshold, :window_seconds, :cooldown_seconds

      # @param agent_type [String] The agent class name
      # @param model_id [String] The model identifier
      # @param tenant_id [String, nil] Optional tenant identifier for multi-tenant isolation
      # @param errors [Integer] Number of errors to trigger open state (default: 10)
      # @param within [Integer] Rolling window in seconds (default: 60)
      # @param cooldown [Integer] Cooldown period in seconds when open (default: 300)
      def initialize(agent_type, model_id, tenant_id: nil, errors: 10, within: 60, cooldown: 300)
        @agent_type = agent_type
        @model_id = model_id
        @tenant_id = resolve_tenant_id(tenant_id)
        @errors_threshold = errors
        @window_seconds = within
        @cooldown_seconds = cooldown
      end

      # Creates a CircuitBreaker from a configuration hash
      #
      # @param agent_type [String] The agent class name
      # @param model_id [String] The model identifier
      # @param config [Hash] Configuration with :errors, :within, :cooldown keys
      # @param tenant_id [String, nil] Optional tenant identifier
      # @return [CircuitBreaker] A new circuit breaker instance
      def self.from_config(agent_type, model_id, config, tenant_id: nil)
        return nil unless config.is_a?(Hash)

        new(
          agent_type,
          model_id,
          tenant_id: tenant_id,
          errors: config[:errors] || 10,
          within: config[:within] || 60,
          cooldown: config[:cooldown] || 300
        )
      end

      # Checks if the circuit breaker is currently open
      #
      # @return [Boolean] true if the breaker is open and requests should be blocked
      def open?
        cache_exist?(open_key)
      end

      # Records a failed attempt and potentially opens the breaker
      #
      # Increments the failure counter and checks if the threshold has been reached.
      # If the threshold is exceeded, opens the breaker for the cooldown period.
      #
      # @return [Boolean] true if the breaker is now open
      def record_failure!
        # Increment the failure counter (atomic operation)
        count = increment_failure_count

        # Check if we should open the breaker
        if count >= errors_threshold && !open?
          open_breaker!
          true
        else
          open?
        end
      end

      # Records a successful attempt
      #
      # Optionally resets the failure counter to reduce false positives.
      #
      # @param reset_counter [Boolean] Whether to reset the failure counter (default: true)
      # @return [void]
      def record_success!(reset_counter: true)
        cache_delete(count_key) if reset_counter
      end

      # Manually resets the circuit breaker
      #
      # Clears both the open flag and the failure counter.
      #
      # @return [void]
      def reset!
        cache_delete(open_key)
        cache_delete(count_key)
      end

      # Returns the current failure count
      #
      # @return [Integer] The current failure count in the rolling window
      def failure_count
        cache_read(count_key).to_i
      end

      # Returns the time remaining until the breaker closes
      #
      # @return [Integer, nil] Seconds until cooldown expires, or nil if not open
      def time_until_close
        return nil unless open?

        # We can't easily get TTL from Rails.cache, so this is an approximation
        # In a real implementation, you might store the open time as well
        cooldown_seconds
      end

      # Returns status information for the circuit breaker
      #
      # @return [Hash] Status information including open state and failure count
      def status
        {
          agent_type: agent_type,
          model_id: model_id,
          tenant_id: tenant_id,
          open: open?,
          failure_count: failure_count,
          errors_threshold: errors_threshold,
          window_seconds: window_seconds,
          cooldown_seconds: cooldown_seconds
        }
      end

      private

      # Resolves the current tenant ID
      #
      # @param explicit_tenant_id [String, nil] Explicitly passed tenant ID
      # @return [String, nil] Resolved tenant ID or nil
      def resolve_tenant_id(explicit_tenant_id)
        config = RubyLLM::Agents.configuration
        return nil unless config.multi_tenancy_enabled?
        return explicit_tenant_id if explicit_tenant_id.present?

        config.tenant_resolver&.call
      end

      # Increments the failure counter with TTL
      #
      # @return [Integer] The new failure count
      def increment_failure_count
        cache_increment(count_key, 1, expires_in: window_seconds)
      end

      # Opens the circuit breaker
      #
      # @return [void]
      def open_breaker!
        cache_write(open_key, Time.current.to_s, expires_in: cooldown_seconds)

        # Fire alert if configured
        if RubyLLM::Agents.configuration.alerts_enabled? &&
           RubyLLM::Agents.configuration.alert_events.include?(:breaker_open)
          AlertManager.notify(:breaker_open, {
            agent_type: agent_type,
            model_id: model_id,
            tenant_id: tenant_id,
            errors: errors_threshold,
            within: window_seconds,
            cooldown: cooldown_seconds,
            timestamp: Time.current.iso8601
          })
        end
      end

      # Returns the cache key for the failure counter
      #
      # @return [String] Cache key
      def count_key
        if tenant_id.present?
          cache_key("cb", "tenant", tenant_id, "count", agent_type, model_id)
        else
          cache_key("cb", "count", agent_type, model_id)
        end
      end

      # Returns the cache key for the open flag
      #
      # @return [String] Cache key
      def open_key
        if tenant_id.present?
          cache_key("cb", "tenant", tenant_id, "open", agent_type, model_id)
        else
          cache_key("cb", "open", agent_type, model_id)
        end
      end
    end
  end
end
