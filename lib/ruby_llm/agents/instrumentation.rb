# frozen_string_literal: true

module RubyLLM
  module Agents
    # Instrumentation concern for tracking agent executions
    #
    # Provides execution timing, token tracking, cost calculation, and error handling.
    # Logs all executions to the database via a background job.
    #
    # == Usage
    #
    # Included automatically in RubyLLM::Agents::Base
    #
    # == Customization
    #
    # Override `execution_metadata` in your agent to add custom data:
    #
    #   def execution_metadata
    #     { query: query, user_id: Current.user&.id }
    #   end
    #
    module Instrumentation
      extend ActiveSupport::Concern

      included do
        attr_accessor :execution_id
      end

      # Wrap agent execution with metrics tracking
      # Creates execution record at start with 'running' status, updates on completion
      # Uses ensure block to guarantee status is updated even if complete_execution fails
      def instrument_execution(&block)
        started_at = Time.current
        @last_response = nil
        @execution_status_updated = false
        original_error = nil

        # Create execution record immediately with running status
        execution = create_running_execution(started_at)
        self.execution_id = execution&.id

        begin
          result = yield

          # Update to success
          complete_execution(
            execution,
            completed_at: Time.current,
            status: "success",
            response: @last_response
          )
          @execution_status_updated = true

          result
        rescue Timeout::Error => e
          original_error = e
          complete_execution(
            execution,
            completed_at: Time.current,
            status: "timeout",
            error: e
          )
          @execution_status_updated = true
          raise
        rescue => e
          original_error = e
          complete_execution(
            execution,
            completed_at: Time.current,
            status: "error",
            error: e
          )
          @execution_status_updated = true
          raise
        ensure
          # Guarantee execution is marked as error if complete_execution failed
          unless @execution_status_updated
            mark_execution_failed!(execution, error: original_error)
          end
        end
      end

      # Store response for metrics extraction
      def capture_response(response)
        @last_response = response
        response
      end

      private

      # Create execution record with running status at start
      def create_running_execution(started_at)
        execution_data = {
          agent_type: self.class.name,
          agent_version: self.class.version,
          model_id: model,
          temperature: temperature,
          started_at: started_at,
          status: "running",
          parameters: sanitized_parameters,
          metadata: execution_metadata,
          system_prompt: safe_system_prompt,
          user_prompt: safe_user_prompt
        }

        RubyLLM::Agents::Execution.create!(execution_data)
      rescue StandardError => e
        # Log error but don't fail the execution
        Rails.logger.error("[RubyLLM::Agents] Failed to create execution record: #{e.message}")
        nil
      end

      # Update execution record on completion
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
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to update execution record: #{e.message}")
        raise # Re-raise so ensure block can handle emergency update
      end

      # Fallback for when initial execution creation failed
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

      # Sanitize parameters to remove sensitive data
      def sanitized_parameters
        params = @options.dup

        # Remove sensitive keys
        sensitive_keys = %i[password token api_key secret credential auth key]
        sensitive_keys.each { |key| params.delete(key) }

        # Convert ActiveRecord objects to IDs
        params.transform_values do |value|
          case value
          when defined?(ActiveRecord::Base) && ActiveRecord::Base
            { id: value.id, type: value.class.name }
          when Array
            if value.first.is_a?(ActiveRecord::Base)
              { ids: value.first(10).map(&:id), type: value.first.class.name, count: value.size }
            else
              value.first(10)
            end
          else
            value
          end
        end
      end

      # Hook for subclasses to add custom metadata
      def execution_metadata
        {}
      end

      # Safely capture system prompt (may raise or return nil)
      def safe_system_prompt
        respond_to?(:system_prompt) ? system_prompt.to_s : nil
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Could not capture system_prompt: #{e.message}")
        nil
      end

      # Safely capture user prompt (may raise or return nil)
      def safe_user_prompt
        respond_to?(:user_prompt) ? user_prompt.to_s : nil
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Could not capture user_prompt: #{e.message}")
        nil
      end

      # Safely extract a value from response, returning default if method doesn't exist
      def safe_response_value(response, method, default = nil)
        return default unless response.respond_to?(method)
        response.public_send(method)
      rescue StandardError
        default
      end

      # Safely extract all response data with fallbacks
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

      # Safe version of serialize_response
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

      # Emergency fallback - mark execution as error using update_columns
      # Bypasses callbacks/validations to ensure status is always updated
      def mark_execution_failed!(execution, error: nil)
        return unless execution&.id
        return unless execution.status == "running"

        update_data = {
          status: "error",
          completed_at: Time.current,
          error_class: error&.class&.name || "InstrumentationError",
          error_message: (error&.message || "Execution status update failed").to_s.truncate(65535)
        }

        execution.class.where(id: execution.id, status: "running").update_all(update_data)
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] CRITICAL: Failed emergency status update for execution #{execution&.id}: #{e.message}")
      end
    end
  end
end
