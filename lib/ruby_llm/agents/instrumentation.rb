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
      def instrument_execution(&block)
        started_at = Time.current
        @last_response = nil

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

          result
        rescue Timeout::Error => e
          complete_execution(
            execution,
            completed_at: Time.current,
            status: "timeout",
            error: e
          )
          raise
        rescue => e
          complete_execution(
            execution,
            completed_at: Time.current,
            status: "error",
            error: e
          )
          raise
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

        # Add response data if available
        if response.is_a?(RubyLLM::Message)
          update_data.merge!(
            input_tokens: response.input_tokens,
            output_tokens: response.output_tokens,
            cached_tokens: response&.cached_tokens || 0,
            cache_creation_tokens: response&.cache_creation_tokens || 0,
            model_id: response.model_id || model,
            response: serialize_response(response)
          )
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
          execution.calculate_costs!
          execution.save!
        end
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Failed to update execution record: #{e.message}")
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

        if response.is_a?(RubyLLM::Message)
          execution_data.merge!(
            input_tokens: response.input_tokens,
            output_tokens: response.output_tokens,
            cached_tokens: response&.cached_tokens || 0,
            cache_creation_tokens: response&.cache_creation_tokens || 0,
            model_id: response.model_id || model,
            response: serialize_response(response)
          )
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

      # Serialize full RubyLLM::Message response to JSON
      def serialize_response(response)
        {
          content: response.content,
          model_id: response.model_id,
          input_tokens: response.input_tokens,
          output_tokens: response.output_tokens,
          cached_tokens: response&.cached_tokens || 0,
          cache_creation_tokens: response&.cache_creation_tokens || 0
        }.compact
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
    end
  end
end
