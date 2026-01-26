# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Manages rate limiting and throttling for workflow steps
      #
      # Provides two modes of rate limiting:
      # 1. Throttle: Ensures minimum time between executions of the same step
      # 2. Rate limit: Limits the number of calls within a time window (token bucket)
      #
      # Thread-safe using a Mutex for concurrent access.
      #
      # @example Using throttle
      #   manager = ThrottleManager.new
      #   manager.throttle("step:fetch", 1.0) # Wait at least 1 second between calls
      #
      # @example Using rate limit
      #   manager = ThrottleManager.new
      #   manager.rate_limit("api:external", calls: 10, per: 60) # 10 calls per minute
      #
      # @api private
      class ThrottleManager
        def initialize
          @last_execution = {}
          @rate_limiters = {}
          @mutex = Mutex.new
        end

        # Throttle execution to ensure minimum time between calls
        #
        # Blocks the current thread if necessary to maintain the minimum interval.
        #
        # @param key [String] Unique identifier for the throttle target
        # @param duration [Float, Integer] Minimum seconds between executions
        # @return [Float] Actual seconds waited (0 if no wait needed)
        def throttle(key, duration)
          duration_seconds = normalize_duration(duration)

          @mutex.synchronize do
            last = @last_execution[key]
            waited = 0

            if last
              elapsed = Time.now - last
              remaining = duration_seconds - elapsed

              if remaining > 0
                @mutex.sleep(remaining)
                waited = remaining
              end
            end

            @last_execution[key] = Time.now
            waited
          end
        end

        # Check if a call would be throttled without actually waiting
        #
        # @param key [String] Unique identifier for the throttle target
        # @param duration [Float, Integer] Minimum seconds between executions
        # @return [Float] Seconds until next allowed execution (0 if ready)
        def throttle_remaining(key, duration)
          duration_seconds = normalize_duration(duration)

          @mutex.synchronize do
            last = @last_execution[key]
            return 0 unless last

            elapsed = Time.now - last
            remaining = duration_seconds - elapsed
            [remaining, 0].max
          end
        end

        # Apply rate limiting using a token bucket algorithm
        #
        # Blocks until a token is available if the rate limit is exceeded.
        #
        # @param key [String] Unique identifier for the rate limit target
        # @param calls [Integer] Number of calls allowed per window
        # @param per [Float, Integer] Time window in seconds
        # @return [Float] Seconds waited (0 if no wait needed)
        def rate_limit(key, calls:, per:)
          per_seconds = normalize_duration(per)
          bucket = get_or_create_bucket(key, calls, per_seconds)

          @mutex.synchronize do
            waited = bucket.acquire
            waited
          end
        end

        # Check if a call would be rate limited without consuming a token
        #
        # @param key [String] Unique identifier for the rate limit target
        # @param calls [Integer] Number of calls allowed per window
        # @param per [Float, Integer] Time window in seconds
        # @return [Boolean] true if a call would be allowed immediately
        def rate_limit_available?(key, calls:, per:)
          per_seconds = normalize_duration(per)
          bucket = get_or_create_bucket(key, calls, per_seconds)

          @mutex.synchronize do
            bucket.available?
          end
        end

        # Reset throttle state for a specific key
        #
        # @param key [String] The throttle key to reset
        # @return [void]
        def reset_throttle(key)
          @mutex.synchronize do
            @last_execution.delete(key)
          end
        end

        # Reset rate limiter state for a specific key
        #
        # @param key [String] The rate limiter key to reset
        # @return [void]
        def reset_rate_limit(key)
          @mutex.synchronize do
            @rate_limiters.delete(key)
          end
        end

        # Reset all throttle and rate limit state
        #
        # @return [void]
        def reset_all!
          @mutex.synchronize do
            @last_execution.clear
            @rate_limiters.clear
          end
        end

        private

        def normalize_duration(duration)
          if duration.respond_to?(:to_f)
            duration.to_f
          else
            duration.to_i.to_f
          end
        end

        def get_or_create_bucket(key, calls, per)
          @rate_limiters[key] ||= TokenBucket.new(calls, per)
        end

        # Simple token bucket implementation for rate limiting
        #
        # @api private
        class TokenBucket
          def initialize(capacity, refill_time)
            @capacity = capacity
            @refill_time = refill_time
            @tokens = capacity.to_f
            @last_refill = Time.now
          end

          # Try to acquire a token, waiting if necessary
          #
          # @return [Float] Seconds waited
          def acquire
            refill
            waited = 0

            if @tokens < 1
              # Calculate wait time for next token
              tokens_needed = 1 - @tokens
              wait_time = tokens_needed * @refill_time / @capacity
              sleep(wait_time)
              waited = wait_time
              refill
            end

            @tokens -= 1
            waited
          end

          # Check if a token is available without consuming it
          #
          # @return [Boolean]
          def available?
            refill
            @tokens >= 1
          end

          private

          def refill
            now = Time.now
            elapsed = now - @last_refill
            refill_amount = elapsed * @capacity / @refill_time
            @tokens = [@tokens + refill_amount, @capacity].min
            @last_refill = now
          end
        end
      end
    end
  end
end
