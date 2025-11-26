# frozen_string_literal: true

module RubyLLM
  module Agents
    # Tracks attempts during agent execution with reliability features
    #
    # Records details about each attempt (retries and fallbacks) during an execution,
    # including timing, token usage, and errors. This data is stored in the execution
    # record's `attempts` JSONB array.
    #
    # @example Tracking attempts
    #   tracker = AttemptTracker.new
    #   attempt = tracker.start_attempt("gpt-4o")
    #   # ... execute LLM call ...
    #   tracker.complete_attempt(attempt, success: true, response: response)
    #
    # @see RubyLLM::Agents::Instrumentation
    # @api private
    class AttemptTracker
      attr_reader :attempts

      def initialize
        @attempts = []
        @current_attempt = nil
      end

      # Starts tracking a new attempt
      #
      # @param model_id [String] The model identifier being used
      # @return [Hash] The attempt hash (pass to complete_attempt)
      def start_attempt(model_id)
        @current_attempt = {
          model_id: model_id,
          started_at: Time.current.iso8601,
          completed_at: nil,
          duration_ms: nil,
          input_tokens: nil,
          output_tokens: nil,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          error_class: nil,
          error_message: nil,
          short_circuited: false
        }

        emit_start_notification(@current_attempt)

        @current_attempt
      end

      # Completes the current attempt with results
      #
      # @param attempt [Hash] The attempt hash from start_attempt
      # @param success [Boolean] Whether the attempt succeeded
      # @param response [Object, nil] The LLM response (if successful)
      # @param error [Exception, nil] The error (if failed)
      # @return [Hash] The completed attempt
      def complete_attempt(attempt, success:, response: nil, error: nil)
        started_at = Time.parse(attempt[:started_at])
        completed_at = Time.current

        attempt[:completed_at] = completed_at.iso8601
        attempt[:duration_ms] = ((completed_at - started_at) * 1000).round

        if response
          attempt[:input_tokens] = safe_value(response, :input_tokens)
          attempt[:output_tokens] = safe_value(response, :output_tokens)
          attempt[:cached_tokens] = safe_value(response, :cached_tokens, 0)
          attempt[:cache_creation_tokens] = safe_value(response, :cache_creation_tokens, 0)
          attempt[:model_id] = safe_value(response, :model_id) || attempt[:model_id]
        end

        if error
          attempt[:error_class] = error.class.name
          attempt[:error_message] = error.message.to_s.truncate(1000)
        end

        @attempts << attempt
        @current_attempt = nil

        emit_finish_notification(attempt, success)

        attempt
      end

      # Records a short-circuited attempt (circuit breaker open)
      #
      # @param model_id [String] The model identifier
      # @return [Hash] The recorded attempt
      def record_short_circuit(model_id)
        now = Time.current

        attempt = {
          model_id: model_id,
          started_at: now.iso8601,
          completed_at: now.iso8601,
          duration_ms: 0,
          input_tokens: nil,
          output_tokens: nil,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          error_class: "RubyLLM::Agents::Reliability::CircuitBreakerOpenError",
          error_message: "Circuit breaker is open",
          short_circuited: true
        }

        @attempts << attempt

        emit_short_circuit_notification(attempt)

        attempt
      end

      # Finds the successful attempt (if any)
      #
      # @return [Hash, nil] The successful attempt or nil
      def successful_attempt
        @attempts.find { |a| a[:error_class].nil? && !a[:short_circuited] }
      end

      # Finds the last failed attempt
      #
      # @return [Hash, nil] The last failed attempt or nil
      def last_failed_attempt
        @attempts.reverse.find { |a| a[:error_class].present? }
      end

      # Returns the chosen model (from successful attempt)
      #
      # @return [String, nil] The model ID that succeeded
      def chosen_model_id
        successful_attempt&.dig(:model_id)
      end

      # Calculates total tokens across all attempts
      #
      # @return [Integer] Total input + output tokens
      def total_tokens
        @attempts.sum { |a| (a[:input_tokens] || 0) + (a[:output_tokens] || 0) }
      end

      # Calculates total input tokens across all attempts
      #
      # @return [Integer] Total input tokens
      def total_input_tokens
        @attempts.sum { |a| a[:input_tokens] || 0 }
      end

      # Calculates total output tokens across all attempts
      #
      # @return [Integer] Total output tokens
      def total_output_tokens
        @attempts.sum { |a| a[:output_tokens] || 0 }
      end

      # Calculates total cached tokens across all attempts
      #
      # @return [Integer] Total cached tokens
      def total_cached_tokens
        @attempts.sum { |a| a[:cached_tokens] || 0 }
      end

      # Calculates total duration across all attempts
      #
      # @return [Integer] Total duration in milliseconds
      def total_duration_ms
        @attempts.sum { |a| a[:duration_ms] || 0 }
      end

      # Returns the number of attempts made
      #
      # @return [Integer] Number of attempts
      def attempts_count
        @attempts.length
      end

      # Returns the number of failed attempts
      #
      # @return [Integer] Number of failed attempts
      def failed_attempts_count
        @attempts.count { |a| a[:error_class].present? }
      end

      # Returns the number of short-circuited attempts
      #
      # @return [Integer] Number of short-circuited attempts
      def short_circuited_count
        @attempts.count { |a| a[:short_circuited] }
      end

      # Returns attempts as JSON-compatible array
      #
      # @return [Array<Hash>] Attempts data for persistence
      def to_json_array
        @attempts.map do |attempt|
          attempt.transform_keys(&:to_s)
        end
      end

      private

      # Safely extracts a value from a response object
      #
      # @param response [Object] The response object
      # @param method [Symbol] The method to call
      # @param default [Object] Default value if method unavailable
      # @return [Object] The extracted value or default
      def safe_value(response, method, default = nil)
        return default unless response.respond_to?(method)
        response.public_send(method)
      rescue StandardError
        default
      end

      # Emits notification when attempt starts
      #
      # @param attempt [Hash] The attempt data
      # @return [void]
      def emit_start_notification(attempt)
        ActiveSupport::Notifications.instrument(
          "ruby_llm_agents.attempt.start",
          model_id: attempt[:model_id],
          attempt_index: @attempts.length
        )
      rescue StandardError
        # Ignore notification failures
      end

      # Emits notification when attempt finishes
      #
      # @param attempt [Hash] The attempt data
      # @param success [Boolean] Whether it succeeded
      # @return [void]
      def emit_finish_notification(attempt, success)
        event = success ? "ruby_llm_agents.attempt.finish" : "ruby_llm_agents.attempt.error"

        payload = {
          model_id: attempt[:model_id],
          duration_ms: attempt[:duration_ms],
          input_tokens: attempt[:input_tokens],
          output_tokens: attempt[:output_tokens],
          success: success
        }

        if !success && attempt[:error_class]
          payload[:error_class] = attempt[:error_class]
          payload[:error_message] = attempt[:error_message]
        end

        ActiveSupport::Notifications.instrument(event, payload)
      rescue StandardError
        # Ignore notification failures
      end

      # Emits notification when attempt is short-circuited
      #
      # @param attempt [Hash] The attempt data
      # @return [void]
      def emit_short_circuit_notification(attempt)
        ActiveSupport::Notifications.instrument(
          "ruby_llm_agents.attempt.short_circuit",
          model_id: attempt[:model_id]
        )
      rescue StandardError
        # Ignore notification failures
      end
    end
  end
end
