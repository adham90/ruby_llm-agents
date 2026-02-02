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
        metadata = execution_metadata

        # Separate niche tracing fields into metadata
        exec_metadata = metadata.dup
        exec_metadata["span_id"] = exec_metadata.delete(:span_id) if exec_metadata[:span_id]

        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          started_at: started_at,
          status: "running",
          metadata: exec_metadata,
          streaming: self.class.streaming,
          messages_count: resolved_messages.size
        }

        # Extract tracing fields from metadata if present
        execution_data[:request_id] = metadata[:request_id] if metadata[:request_id]
        execution_data[:trace_id] = metadata[:trace_id] if metadata[:trace_id]
        execution_data[:parent_execution_id] = metadata[:parent_execution_id] if metadata[:parent_execution_id]
        execution_data[:root_execution_id] = metadata[:root_execution_id] if metadata[:root_execution_id]

        # Add fallback chain tracking (count only on execution, chain stored in detail)
        if fallback_chain.any?
          execution_data[:attempts_count] = 0
          @_pending_detail_data = { fallback_chain: fallback_chain, attempts: [] }
        end

        # Add tenant_id if multi-tenancy is enabled
        if config.multi_tenancy_enabled?
          execution_data[:tenant_id] = config.current_tenant_id
        end

        execution = RubyLLM::Agents::Execution.create!(execution_data)

        # Create detail record with prompts and parameters
        detail_data = {
          parameters: redacted_parameters,
          messages_summary: config.persist_messages_summary ? messages_summary : {},
          system_prompt: config.persist_prompts ? redacted_system_prompt : nil,
          user_prompt: config.persist_prompts ? redacted_user_prompt : nil
        }
        detail_data.merge!(@_pending_detail_data) if @_pending_detail_data
        @_pending_detail_data = nil

        has_data = detail_data.values.any? { |v| v.present? && v != {} && v != [] }
        execution.create_detail!(detail_data) if has_data

        execution
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

        # Store niche streaming metrics in metadata
        if respond_to?(:time_to_first_token_ms) && time_to_first_token_ms
          update_data[:metadata] = (execution.metadata || {}).merge("time_to_first_token_ms" => time_to_first_token_ms)
        end

        # Add response data if available (using safe extraction)
        response_data = safe_extract_response_data(response)
        if response_data.any?
          # Separate execution-level fields from detail-level fields
          detail_fields = response_data.extract!(:response, :tool_calls, :cache_creation_tokens)
          update_data.merge!(response_data.except(:tool_calls_count))
          update_data[:tool_calls_count] = detail_fields[:tool_calls]&.size || 0
          update_data[:model_id] ||= model
        end

        # Add error class on execution (error_message goes to detail)
        if error
          update_data[:error_class] = error.class.name
        end

        execution.update!(update_data)

        # Update or create detail record with completion data
        detail_update = {}
        detail_update[:response] = detail_fields[:response] if detail_fields&.dig(:response)
        detail_update[:tool_calls] = detail_fields[:tool_calls] if detail_fields&.dig(:tool_calls)
        detail_update[:cache_creation_tokens] = detail_fields[:cache_creation_tokens] if detail_fields&.dig(:cache_creation_tokens)
        detail_update[:error_message] = error.message if error

        if detail_update.values.any?(&:present?)
          if execution.detail
            execution.detail.update!(detail_update)
          else
            execution.create_detail!(detail_update)
          end
        end

        # Calculate costs if token data is available
        if execution.input_tokens && execution.output_tokens
          begin
            execution.calculate_costs!
            execution.save!
          rescue StandardError => cost_error
            Rails.logger.warn("[RubyLLM::Agents] Cost calculation failed: #{cost_error.message}")
          end
        end

        # Record token usage for budget tracking
        record_token_usage(execution)
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
          attempts_count: attempt_tracker.attempts_count,
          chosen_model_id: attempt_tracker.chosen_model_id,
          input_tokens: attempt_tracker.total_input_tokens,
          output_tokens: attempt_tracker.total_output_tokens,
          total_tokens: attempt_tracker.total_tokens,
          cached_tokens: attempt_tracker.total_cached_tokens
        }

        # Store niche streaming metrics in metadata
        merged_metadata = execution.metadata || {}
        if respond_to?(:time_to_first_token_ms) && time_to_first_token_ms
          merged_metadata["time_to_first_token_ms"] = time_to_first_token_ms
        end

        # Add finish reason from response if available
        if @last_response
          finish_reason = safe_extract_finish_reason(@last_response)
          update_data[:finish_reason] = finish_reason if finish_reason
        end

        # Store routing/retry niche fields in metadata
        routing_data = extract_routing_data(attempt_tracker, error)
        merged_metadata["fallback_reason"] = routing_data[:fallback_reason] if routing_data[:fallback_reason]
        merged_metadata["retryable"] = routing_data[:retryable] if routing_data.key?(:retryable)
        merged_metadata["rate_limited"] = routing_data[:rate_limited] if routing_data.key?(:rate_limited)

        update_data[:metadata] = merged_metadata if merged_metadata.any?

        # Tool calls count on execution
        if respond_to?(:accumulated_tool_calls) && accumulated_tool_calls.present?
          update_data[:tool_calls_count] = accumulated_tool_calls.size
        end

        # Error class on execution (error_message goes to detail)
        if error
          update_data[:error_class] = error.class.name
        end

        execution.update!(update_data)

        # Update or create detail record
        detail_update = {
          attempts: attempt_tracker.to_json_array
        }
        if @last_response && config.persist_responses
          detail_update[:response] = redacted_response(@last_response)
        end
        if respond_to?(:accumulated_tool_calls) && accumulated_tool_calls.present?
          detail_update[:tool_calls] = accumulated_tool_calls
        end
        if error
          detail_update[:error_message] = error.message.to_s.truncate(65535)
        end

        if execution.detail
          execution.detail.update!(detail_update)
        else
          execution.create_detail!(detail_update)
        end

        # Calculate costs from all attempts
        if attempt_tracker.attempts_count > 0
          begin
            execution.aggregate_attempt_costs!
            execution.save!
          rescue StandardError => cost_error
            Rails.logger.warn("[RubyLLM::Agents] Cost calculation failed: #{cost_error.message}")
          end
        end

        # Record token usage for budget tracking
        record_token_usage(execution)
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
        config = RubyLLM::Agents.configuration

        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          started_at: Time.current,
          completed_at: completed_at,
          duration_ms: 0,
          status: status,
          metadata: execution_metadata,
          messages_count: resolved_messages.size
        }

        # Add response data if available (using safe extraction)
        response_data = safe_extract_response_data(response)
        if response_data.any?
          detail_fields = response_data.extract!(:response, :tool_calls, :cache_creation_tokens)
          execution_data.merge!(response_data.except(:tool_calls_count))
          execution_data[:tool_calls_count] = detail_fields[:tool_calls]&.size || 0
          execution_data[:model_id] ||= model
        end

        if error
          execution_data[:error_class] = error.class.name
        end

        # Detail data stored separately
        detail_data = {
          parameters: sanitized_parameters,
          system_prompt: safe_system_prompt,
          user_prompt: safe_user_prompt,
          messages_summary: config.persist_messages_summary ? messages_summary : {},
          error_message: error&.message
        }.merge(detail_fields || {})

        execution_data[:_detail_data] = detail_data

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

      # Returns a summary of messages (first and last, truncated)
      #
      # Creates a summary of the conversation messages containing the first
      # and last messages (if different) with content truncated for storage.
      #
      # @return [Hash] Summary with :first and :last message hashes, or empty hash
      def messages_summary
        msgs = resolved_messages
        return {} if msgs.blank?

        max_len = RubyLLM::Agents.configuration.messages_summary_max_length || 500

        summary = {}

        if msgs.first
          summary[:first] = {
            role: msgs.first[:role].to_s,
            content: Redactor.redact_string(msgs.first[:content].to_s).truncate(max_len)
          }
        end

        # Only add last if there are multiple messages and last is different from first
        if msgs.size > 1 && msgs.last
          summary[:last] = {
            role: msgs.last[:role].to_s,
            content: Redactor.redact_string(msgs.last[:content].to_s).truncate(max_len)
          }
        end

        summary
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
        return {} unless response.respond_to?(:input_tokens)

        # Use accumulated_tool_calls which captures tool calls from ALL responses
        # during multi-turn conversations (when tools are used)
        tool_calls_data = respond_to?(:accumulated_tool_calls) ? accumulated_tool_calls : []

        # Extract thinking data if present
        thinking_data = safe_extract_thinking_data(response)

        {
          input_tokens: safe_response_value(response, :input_tokens),
          output_tokens: safe_response_value(response, :output_tokens),
          cached_tokens: safe_response_value(response, :cached_tokens, 0),
          cache_creation_tokens: safe_response_value(response, :cache_creation_tokens, 0),
          model_id: safe_response_value(response, :model_id),
          finish_reason: safe_extract_finish_reason(response),
          response: safe_serialize_response(response),
          tool_calls: tool_calls_data || [],
          tool_calls_count: tool_calls_data&.size || 0
        }.merge(thinking_data).compact
      end

      # Extracts finish reason from response, normalizing to standard values
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [String, nil] Normalized finish reason
      def safe_extract_finish_reason(response)
        reason = safe_response_value(response, :finish_reason) ||
                 safe_response_value(response, :stop_reason)
        return nil unless reason

        # Normalize to standard values
        normalized = reason.to_s.downcase
        case normalized
        when "stop", "end_turn", "stop_sequence"
          "stop"
        when "length", "max_tokens"
          "length"
        when "content_filter", "safety"
          "content_filter"
        when "tool_calls", "tool_use", "function_call"
          "tool_calls"
        else
          "other"
        end
      end

      # Extracts thinking data from response
      #
      # Handles different response structures from various providers.
      # The thinking object typically has text, signature, and tokens.
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [Hash] Thinking data (empty if none present)
      def safe_extract_thinking_data(response)
        thinking = safe_response_value(response, :thinking)
        return {} unless thinking

        {
          thinking_text: thinking.respond_to?(:text) ? thinking.text : thinking[:text],
          thinking_signature: thinking.respond_to?(:signature) ? thinking.signature : thinking[:signature],
          thinking_tokens: thinking.respond_to?(:tokens) ? thinking.tokens : thinking[:tokens]
        }.compact
      end

      # Extracts routing/retry tracking data from attempt tracker
      #
      # Analyzes the execution attempts to determine:
      # - Why a fallback was used (fallback_reason)
      # - Whether the error is retryable
      # - Whether rate limiting occurred
      #
      # @param attempt_tracker [AttemptTracker] The attempt tracker
      # @param error [Exception, nil] The final error (if any)
      # @return [Hash] Routing data to merge into execution
      def extract_routing_data(attempt_tracker, error)
        data = {}

        # Determine if a fallback was used and why
        if attempt_tracker.used_fallback?
          data[:fallback_reason] = determine_fallback_reason(attempt_tracker)
        end

        # Check if error is retryable
        if error
          data[:retryable] = retryable_error?(error)
          data[:rate_limited] = rate_limit_error?(error)
        end

        data
      end

      # Determines the reason for using a fallback model
      #
      # @param attempt_tracker [AttemptTracker] The attempt tracker
      # @return [String] Fallback reason
      def determine_fallback_reason(attempt_tracker)
        # Analyze failed attempts to determine why fallback was needed
        failed = attempt_tracker.failed_attempts
        return "other" if failed.empty?

        last_failed = failed.last
        error_class = last_failed[:error_class]

        case error_class
        when /RateLimitError/, /TooManyRequestsError/
          "rate_limit"
        when /Timeout/
          "timeout"
        when /ContentFilter/, /SafetyError/
          "safety"
        when /BudgetExceeded/
          "price_limit"
        else
          "error"
        end
      end

      # Checks if an error is retryable
      #
      # @param error [Exception] The error
      # @return [Boolean] true if retryable
      def retryable_error?(error)
        return false unless error

        # Check against known retryable error patterns
        error_class = error.class.name
        error_class.match?(/Timeout|ConnectionError|RateLimitError|ServiceUnavailable|BadGateway/)
      end

      # Checks if an error indicates rate limiting
      #
      # @param error [Exception] The error
      # @return [Boolean] true if rate limited
      def rate_limit_error?(error)
        return false unless error

        error_class = error.class.name
        error_message = error.message.to_s.downcase

        error_class.match?(/RateLimitError|TooManyRequests/) ||
          error_message.include?("rate limit") ||
          error_message.include?("too many requests")
      end

      # Serializes response to a hash for storage
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [Hash] Serialized response data
      def safe_serialize_response(response)
        # Use accumulated_tool_calls which captures tool calls from ALL responses
        tool_calls_data = respond_to?(:accumulated_tool_calls) ? accumulated_tool_calls : nil

        {
          content: safe_response_value(response, :content),
          model_id: safe_response_value(response, :model_id),
          input_tokens: safe_response_value(response, :input_tokens),
          output_tokens: safe_response_value(response, :output_tokens),
          cached_tokens: safe_response_value(response, :cached_tokens, 0),
          cache_creation_tokens: safe_response_value(response, :cache_creation_tokens, 0),
          tool_calls: tool_calls_data.presence
        }.compact
      end

      # Serializes tool calls to an array of hashes for storage
      #
      # @param response [RubyLLM::Message] The LLM response
      # @return [Array<Hash>, nil] Serialized tool calls or nil if none
      def serialize_tool_calls(response)
        tool_calls = safe_response_value(response, :tool_calls)
        return nil if tool_calls.nil? || tool_calls.empty?

        tool_calls.map do |id, tool_call|
          if tool_call.respond_to?(:to_h)
            tool_call.to_h
          else
            { id: id, name: tool_call[:name], arguments: tool_call[:arguments] }
          end
        end
      end

      # Records an execution for a cache hit
      #
      # Creates a minimal execution record with cache_hit: true, 0 tokens,
      # and 0 cost. This allows tracking cache hits in the dashboard.
      #
      # @param cache_key [String] The cache key that was hit
      # @param cached_result [Object] The cached result returned
      # @param started_at [Time] When the cache lookup started
      # @return [void]
      def record_cache_hit_execution(cache_key, cached_result, started_at)
        config = RubyLLM::Agents.configuration
        completed_at = Time.current
        duration_ms = ((completed_at - started_at) * 1000).round

        exec_metadata = execution_metadata.dup
        exec_metadata["response_cache_key"] = cache_key
        exec_metadata["span_id"] = exec_metadata.delete(:span_id) if exec_metadata[:span_id]

        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          status: "success",
          cache_hit: true,
          started_at: started_at,
          completed_at: completed_at,
          duration_ms: duration_ms,
          input_tokens: 0,
          output_tokens: 0,
          cached_tokens: 0,
          total_tokens: 0,
          input_cost: 0,
          output_cost: 0,
          total_cost: 0,
          metadata: exec_metadata,
          streaming: self.class.streaming,
          messages_count: resolved_messages.size
        }

        # Add tracing fields from metadata if present
        metadata = execution_metadata
        execution_data[:request_id] = metadata[:request_id] if metadata[:request_id]
        execution_data[:trace_id] = metadata[:trace_id] if metadata[:trace_id]
        execution_data[:parent_execution_id] = metadata[:parent_execution_id] if metadata[:parent_execution_id]
        execution_data[:root_execution_id] = metadata[:root_execution_id] if metadata[:root_execution_id]

        # Add tenant_id if multi-tenancy is enabled
        if config.multi_tenancy_enabled?
          execution_data[:tenant_id] = config.current_tenant_id
        end

        if config.async_logging
          RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
        else
          execution = RubyLLM::Agents::Execution.create!(execution_data)
          # Create detail with cache-related fields
          detail_data = {
            parameters: redacted_parameters,
            messages_summary: config.persist_messages_summary ? messages_summary : {},
            cached_at: completed_at,
            cache_creation_tokens: 0
          }
          execution.create_detail!(detail_data) if detail_data.values.any?(&:present?)
        end
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to record cache hit execution: #{e.message}")
      end

      # Records token usage to the BudgetTracker
      #
      # @param execution [Execution] The completed execution record
      # @return [void]
      def record_token_usage(execution)
        return unless execution&.total_tokens && execution.total_tokens > 0

        begin
          tenant_id = respond_to?(:resolved_tenant_id) ? resolved_tenant_id : nil
          tenant_config = respond_to?(:runtime_tenant_config) ? runtime_tenant_config : nil

          BudgetTracker.record_tokens!(
            self.class.name,
            execution.total_tokens,
            tenant_id: tenant_id,
            tenant_config: tenant_config
          )
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents] Failed to record token usage: #{e.message}")
        end
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
          error_class: error.class.name
        }

        execution.class.where(id: execution.id, status: "running").update_all(update_data)

        # Store error_message in detail table (best-effort)
        begin
          detail_attrs = { error_message: error_message.to_s.truncate(65535) }
          if execution.detail
            execution.detail.update_columns(detail_attrs)
          else
            RubyLLM::Agents::ExecutionDetail.create!(detail_attrs.merge(execution_id: execution.id))
          end
        rescue StandardError
          # Non-critical — error_class on execution is sufficient for filtering
        end
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] CRITICAL: Failed emergency status update for execution #{execution&.id}: #{e.message}")
      end
    end
  end
end
