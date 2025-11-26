# frozen_string_literal: true

module RubyLLM
  module Agents
    # Instrumentation concern for tracking agent executions
    #
    # Provides comprehensive execution tracking including:
    # - Timing metrics (started_at, completed_at, duration_ms)
    # - Token usage tracking (input, output, cached)
    # - Cost calculation via RubyLLM pricing data
    # - Error and timeout handling with status tracking
    # - Safe parameter sanitization for logging
    #
    # Included automatically in {RubyLLM::Agents::Base}.
    #
    # @example Adding custom metadata to executions
    #   class MyAgent < ApplicationAgent
    #     def execution_metadata
    #       { user_id: Current.user&.id, request_id: request.uuid }
    #     end
    #   end
    #
    # @see RubyLLM::Agents::Execution
    # @see RubyLLM::Agents::ExecutionLoggerJob
    # @api private
    module Instrumentation
      extend ActiveSupport::Concern

      included do
        # @!attribute [rw] execution_id
        #   The ID of the current execution record
        #   @return [Integer, nil]
        attr_accessor :execution_id
      end

      # Wraps agent execution with comprehensive metrics tracking (for reliability-enabled agents)
      #
      # Creates a single execution record and tracks multiple attempts within it.
      # Used by execute_with_reliability for retry/fallback scenarios.
      #
      # Uses catch/throw pattern because the yielded block uses `throw :execution_success`
      # to exit early on success. Regular `return` from within a block would bypass
      # our completion code, so we use throw/catch to properly intercept success cases.
      #
      # @param models_to_try [Array<String>] List of models in the fallback chain
      # @yield [AttemptTracker] Block receives attempt tracker for recording attempts
      # @return [Object] The result from the yielded block
      # @raise [Timeout::Error] Re-raised after logging timeout status
      # @raise [StandardError] Re-raised after logging error status
      def instrument_execution_with_attempts(models_to_try:, &block)
        started_at = Time.current
        @last_response = nil
        @status_update_completed = false
        raised_exception = nil
        completion_error = nil

        attempt_tracker = AttemptTracker.new

        # Create execution record with running status and fallback chain
        execution = create_running_execution(started_at, fallback_chain: models_to_try)
        self.execution_id = execution&.id

        # Use catch to intercept successful early returns from the block
        # The block uses `throw :execution_success, result` instead of `return`
        result = catch(:execution_success) do
          begin
            yield(attempt_tracker)
            # If we reach here normally (no throw), the block completed without success
            # This happens when AllModelsExhaustedError is raised
            nil
          rescue Timeout::Error, Reliability::TotalTimeoutError => e
            raised_exception = e
            begin
              complete_execution_with_attempts(
                execution,
                attempt_tracker: attempt_tracker,
                completed_at: Time.current,
                status: "timeout",
                error: e
              )
              @status_update_completed = true
            rescue StandardError => completion_err
              completion_error = completion_err
            end
            raise
          rescue StandardError => e
            raised_exception = e
            begin
              complete_execution_with_attempts(
                execution,
                attempt_tracker: attempt_tracker,
                completed_at: Time.current,
                status: "error",
                error: e
              )
              @status_update_completed = true
            rescue StandardError => completion_err
              completion_error = completion_err
            end
            raise
          ensure
            # Only run emergency fallback if we haven't completed AND we're not in success path
            # The success path completion happens AFTER the catch block
            unless @status_update_completed || !$!
              actual_error = completion_error || raised_exception || $!
              mark_execution_failed!(execution, error: actual_error)
            end
          end
        end

        # If we caught a successful throw, complete the execution properly
        # result will be non-nil if throw :execution_success was called
        if result && !@status_update_completed
          begin
            complete_execution_with_attempts(
              execution,
              attempt_tracker: attempt_tracker,
              completed_at: Time.current,
              status: "success"
            )
            @status_update_completed = true
          rescue StandardError => e
            Rails.logger.error("[RubyLLM::Agents] Failed to complete successful execution: #{e.class}: #{e.message}")
            mark_execution_failed!(execution, error: e)
          end
        end

        result
      end

      # Wraps agent execution with comprehensive metrics tracking
      #
      # Execution lifecycle:
      # 1. Creates execution record immediately with 'running' status
      # 2. Yields to the block for actual agent execution
      # 3. Updates record with final status and metrics
      # 4. Uses ensure block to guarantee status update even on failures
      #
      # @yield The block containing the actual agent execution
      # @return [Object] The result from the yielded block
      # @raise [Timeout::Error] Re-raised after logging timeout status
      # @raise [StandardError] Re-raised after logging error status
      def instrument_execution(&block)
        started_at = Time.current
        @last_response = nil
        @status_update_completed = false
        raised_exception = nil
        completion_error = nil

        # Create execution record immediately with running status
        execution = create_running_execution(started_at)
        self.execution_id = execution&.id

        begin
          result = yield

          # Update to success
          # NOTE: If this fails, we capture the error but DON'T re-raise
          # The ensure block will handle it via mark_execution_failed!
          begin
            complete_execution(
              execution,
              completed_at: Time.current,
              status: "success",
              response: @last_response
            )
            @status_update_completed = true
          rescue StandardError => e
            completion_error = e
            # Don't re-raise - let ensure block handle via mark_execution_failed!
          end

          result
        rescue Timeout::Error => e
          raised_exception = e
          begin
            complete_execution(
              execution,
              completed_at: Time.current,
              status: "timeout",
              error: e
            )
            @status_update_completed = true
          rescue StandardError => completion_err
            completion_error = completion_err
          end
          raise
        rescue StandardError => e
          raised_exception = e
          begin
            complete_execution(
              execution,
              completed_at: Time.current,
              status: "error",
              error: e
            )
            @status_update_completed = true
          rescue StandardError => completion_err
            completion_error = completion_err
          end
          raise
        ensure
          # Emergency fallback: mark as error if complete_execution itself failed
          # This ensures executions never remain stuck in 'running' status
          unless @status_update_completed
            # Prefer completion_error (from update! failure) over raised_exception (from execution)
            # Use $! as final fallback - it holds the current exception being propagated
            actual_error = completion_error || raised_exception || $!
            mark_execution_failed!(execution, error: actual_error)
          end
        end
      end

      # Stores the LLM response for metrics extraction
      #
      # Called by the agent after receiving a response from the LLM.
      # The response is used to extract token counts and model information.
      #
      # @param response [RubyLLM::Message] The response from the LLM
      # @return [RubyLLM::Message] The same response (for method chaining)
      def capture_response(response)
        @last_response = response
        response
      end

      private

      # Creates initial execution record with 'running' status
      #
      # @param started_at [Time] When the execution started
      # @param fallback_chain [Array<String>] Optional list of models in fallback chain
      # @return [RubyLLM::Agents::Execution, nil] The created record, or nil on failure
      def create_running_execution(started_at, fallback_chain: [])
        config = RubyLLM::Agents.configuration

        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          started_at: started_at,
          status: "running",
          parameters: redacted_parameters,
          metadata: execution_metadata,
          system_prompt: config.persist_prompts ? redacted_system_prompt : nil,
          user_prompt: config.persist_prompts ? redacted_user_prompt : nil
        }

        # Add fallback chain if provided (for reliability-enabled executions)
        if fallback_chain.any?
          execution_data[:fallback_chain] = fallback_chain
          execution_data[:attempts] = []
          execution_data[:attempts_count] = 0
        end

        RubyLLM::Agents::Execution.create!(execution_data)
      rescue StandardError => e
        # Log error but don't fail the agent execution itself
        Rails.logger.error("[RubyLLM::Agents] Failed to create execution record: #{e.message}")
        nil
      end

      # Updates execution record with completion data
      #
      # Calculates duration, extracts response metrics, and saves final status.
      # Falls back to legacy logging if the initial execution record is nil.
      #
      # @param execution [Execution, nil] The execution record to update
      # @param completed_at [Time] When the execution completed
      # @param status [String] Final status ("success", "error", "timeout")
      # @param response [RubyLLM::Message, nil] The LLM response (if successful)
      # @param error [Exception, nil] The exception (if failed)
      # @return [void]
      def complete_execution(execution, completed_at:, status:, response: nil, error: nil)
        return legacy_log_execution(completed_at: completed_at, status: status, response: response, error: error) unless execution

        started_at = execution.started_at
        duration_ms = ((completed_at - started_at) * 1000).round

        update_data = {
          completed_at: completed_at,
          duration_ms: duration_ms,
          status: status
        }

        # Add response data if available (using safe extraction)
        response_data = safe_extract_response_data(response)
        if response_data.any?
          update_data.merge!(response_data)
          update_data[:model_id] ||= model
        end

        # Add error data if failed
        if error
          update_data.merge!(
            error_message: error.message,
            error_class: error.class.name
          )
        end

        execution.update!(update_data)

        # Calculate costs if token data is available
        if execution.input_tokens && execution.output_tokens
          begin
            execution.calculate_costs!
            execution.save!
          rescue StandardError => cost_error
            Rails.logger.warn("[RubyLLM::Agents] Cost calculation failed: #{cost_error.message}")
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[RubyLLM::Agents] Validation failed for execution #{execution&.id}: #{e.record.errors.full_messages.join(', ')}")
        if Rails.env.development? || Rails.env.test?
          Rails.logger.error("[RubyLLM::Agents] Update data: #{update_data.inspect}")
        end
        raise
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to update execution record #{execution&.id}: #{e.class}: #{e.message}")
        if Rails.env.development? || Rails.env.test?
          Rails.logger.error("[RubyLLM::Agents] Update data: #{update_data.inspect}")
        end
        raise
      end

      # Updates execution record with completion data and attempt tracking
      #
      # Similar to complete_execution but handles multi-attempt scenarios with
      # aggregated token counts and costs from all attempts.
      #
      # @param execution [Execution, nil] The execution record to update
      # @param attempt_tracker [AttemptTracker] The attempt tracker with attempt data
      # @param completed_at [Time] When the execution completed
      # @param status [String] Final status ("success", "error", "timeout")
      # @param error [Exception, nil] The exception (if failed)
      # @return [void]
      def complete_execution_with_attempts(execution, attempt_tracker:, completed_at:, status:, error: nil)
        return unless execution

        started_at = execution.started_at
        duration_ms = ((completed_at - started_at) * 1000).round

        config = RubyLLM::Agents.configuration

        update_data = {
          completed_at: completed_at,
          duration_ms: duration_ms,
          status: status,
          attempts: attempt_tracker.to_json_array,
          attempts_count: attempt_tracker.attempts_count,
          chosen_model_id: attempt_tracker.chosen_model_id,
          input_tokens: attempt_tracker.total_input_tokens,
          output_tokens: attempt_tracker.total_output_tokens,
          total_tokens: attempt_tracker.total_tokens,
          cached_tokens: attempt_tracker.total_cached_tokens
        }

        # Add response data if we have a last response
        if @last_response && config.persist_responses
          update_data[:response] = redacted_response(@last_response)
        end

        # Add error data if failed
        if error
          update_data.merge!(
            error_message: error.message.to_s.truncate(65535),
            error_class: error.class.name
          )
        end

        execution.update!(update_data)

        # Calculate costs from all attempts
        if attempt_tracker.attempts_count > 0
          begin
            execution.aggregate_attempt_costs!
            execution.save!
          rescue StandardError => cost_error
            Rails.logger.warn("[RubyLLM::Agents] Cost calculation failed: #{cost_error.message}")
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[RubyLLM::Agents] Validation failed for execution #{execution&.id}: #{e.record.errors.full_messages.join(', ')}")
        if Rails.env.development? || Rails.env.test?
          Rails.logger.error("[RubyLLM::Agents] Update data: #{update_data.inspect}")
        end
        raise
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to update execution record #{execution&.id}: #{e.class}: #{e.message}")
        if Rails.env.development? || Rails.env.test?
          Rails.logger.error("[RubyLLM::Agents] Update data: #{update_data.inspect}")
        end
        raise
      end

      # Fallback logging when initial execution record creation failed
      #
      # Creates execution via background job or synchronously based on configuration.
      # Used as a last resort to ensure execution data is captured.
      #
      # @param completed_at [Time] When the execution completed
      # @param status [String] Final status
      # @param response [RubyLLM::Message, nil] The LLM response
      # @param error [Exception, nil] The exception if failed
      # @return [void]
      def legacy_log_execution(completed_at:, status:, response: nil, error: nil)
        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          started_at: Time.current,
          completed_at: completed_at,
          duration_ms: 0,
          status: status,
          parameters: sanitized_parameters,
          metadata: execution_metadata,
          system_prompt: safe_system_prompt,
          user_prompt: safe_user_prompt
        }

        # Add response data if available (using safe extraction)
        response_data = safe_extract_response_data(response)
        if response_data.any?
          execution_data.merge!(response_data)
          execution_data[:model_id] ||= model
        end

        if error
          execution_data.merge!(
            error_message: error.message,
            error_class: error.class.name
          )
        end

        if RubyLLM::Agents.configuration.async_logging
          RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
        else
          RubyLLM::Agents::ExecutionLoggerJob.new.perform(execution_data)
        end
      end

      # Sanitizes parameters by removing sensitive data
      #
      # @deprecated Use {#redacted_parameters} instead
      # @return [Hash] Sanitized parameters safe for logging
      def sanitized_parameters
        redacted_parameters
      end

      # Returns parameters with sensitive data redacted using the Redactor
      #
      # Uses the configured redaction rules to remove sensitive fields and
      # apply pattern-based redaction. Also converts ActiveRecord objects
      # to ID references.
      #
      # @return [Hash] Redacted parameters safe for logging
      def redacted_parameters
        params = @options.except(:skip_cache, :dry_run)
        Redactor.redact(params)
      end

      # Returns the system prompt with redaction applied
      #
      # @return [String, nil] The redacted system prompt
      def redacted_system_prompt
        prompt = safe_system_prompt
        return nil unless prompt

        Redactor.redact_string(prompt)
      end

      # Returns the user prompt with redaction applied
      #
      # @return [String, nil] The redacted user prompt
      def redacted_user_prompt
        prompt = safe_user_prompt
        return nil unless prompt

        Redactor.redact_string(prompt)
      end

      # Returns the response with redaction applied
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [Hash] Redacted response data
      def redacted_response(response)
        data = safe_serialize_response(response)
        Redactor.redact(data)
      end

      # Hook for subclasses to add custom metadata to executions
      #
      # Override this method in your agent to include application-specific
      # data like user IDs, request IDs, or feature flags.
      #
      # @return [Hash] Custom metadata to store with the execution
      # @example
      #   def execution_metadata
      #     { user_id: Current.user&.id, experiment: "v2" }
      #   end
      def execution_metadata
        {}
      end

      # Safely captures system prompt, handling errors gracefully
      #
      # @return [String, nil] The system prompt or nil if unavailable
      def safe_system_prompt
        respond_to?(:system_prompt) ? system_prompt.to_s : nil
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Could not capture system_prompt: #{e.message}")
        nil
      end

      # Safely captures user prompt, handling errors gracefully
      #
      # @return [String, nil] The user prompt or nil if unavailable
      def safe_user_prompt
        respond_to?(:user_prompt) ? user_prompt.to_s : nil
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Could not capture user_prompt: #{e.message}")
        nil
      end

      # Safely extracts a value from response object
      #
      # @param response [Object] The response object
      # @param method [Symbol] The method to call
      # @param default [Object] Default value if method unavailable
      # @return [Object] The extracted value or default
      def safe_response_value(response, method, default = nil)
        return default unless response.respond_to?(method)
        response.public_send(method)
      rescue StandardError
        default
      end

      # Extracts all response metrics with safe fallbacks
      #
      # @param response [RubyLLM::Message, nil] The LLM response
      # @return [Hash] Extracted response data (empty if response invalid)
      def safe_extract_response_data(response)
        return {} unless response.is_a?(RubyLLM::Message)

        {
          input_tokens: safe_response_value(response, :input_tokens),
          output_tokens: safe_response_value(response, :output_tokens),
          cached_tokens: safe_response_value(response, :cached_tokens, 0),
          cache_creation_tokens: safe_response_value(response, :cache_creation_tokens, 0),
          model_id: safe_response_value(response, :model_id),
          response: safe_serialize_response(response)
        }.compact
      end

      # Serializes response to a hash for storage
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [Hash] Serialized response data
      def safe_serialize_response(response)
        {
          content: safe_response_value(response, :content),
          model_id: safe_response_value(response, :model_id),
          input_tokens: safe_response_value(response, :input_tokens),
          output_tokens: safe_response_value(response, :output_tokens),
          cached_tokens: safe_response_value(response, :cached_tokens, 0),
          cache_creation_tokens: safe_response_value(response, :cache_creation_tokens, 0)
        }.compact
      end

      # Emergency fallback to mark execution as failed
      #
      # Uses update_all to bypass ActiveRecord callbacks and validations,
      # ensuring the status is updated even if the model is in an invalid state.
      # Only updates records that are still in 'running' status to prevent
      # race conditions.
      #
      # @param execution [Execution, nil] The execution record
      # @param error [Exception, nil] The exception that caused the failure
      # @return [void]
      def mark_execution_failed!(execution, error: nil)
        return unless execution&.id
        return unless execution.status == "running"

        # If no error was captured, create a synthetic one with current stack trace
        # This helps debug cases where error details are lost
        if error.nil?
          Rails.logger.error("[RubyLLM::Agents] BUG: mark_execution_failed! called with nil error")
          Rails.logger.error("[RubyLLM::Agents] Stack trace:\n  #{caller.first(15).join("\n  ")}")

          synthetic_error = RuntimeError.new("No error was captured - check logs for stack trace")
          synthetic_error.set_backtrace(caller)
          error = synthetic_error
        end

        # Build a detailed error message including backtrace for debugging
        backtrace_info = error.backtrace&.first(5)&.join("\n  ") || ""
        error_message = "#{error.class}: #{error.message}"
        error_message += "\n  #{backtrace_info}" if backtrace_info.present?

        update_data = {
          status: "error",
          completed_at: Time.current,
          error_class: error.class.name,
          error_message: error_message.to_s.truncate(65535)
        }

        execution.class.where(id: execution.id, status: "running").update_all(update_data)
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] CRITICAL: Failed emergency status update for execution #{execution&.id}: #{e.message}")
      end
    end
  end
end
