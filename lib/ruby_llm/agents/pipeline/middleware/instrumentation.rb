# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Times execution and records results for observability.
        #
        # This middleware provides:
        # - Execution timing (start/end timestamps, duration)
        # - Success/failure recording to database
        # - Token usage and cost tracking
        # - Error details on failure
        #
        # Recording can be async (via background job) or sync depending
        # on configuration.
        #
        # Tracking is enabled/disabled per agent type via configuration:
        # - track_executions (conversation agents)
        # - track_embeddings
        # - track_moderations
        # - track_image_generations
        # - track_audio
        #
        # @example Configuration
        #   RubyLLM::Agents.configure do |config|
        #     config.track_executions = true
        #     config.track_embeddings = true
        #     config.async_logging = true  # Use background job
        #   end
        #
        class Instrumentation < Base
          # Process instrumentation
          #
          # Creates a "running" execution record at the start so executions
          # appear on the dashboard immediately, then updates it when complete.
          #
          # @param context [Context] The execution context
          # @return [Context] The context with timing info
          def call(context)
            context.started_at = Time.current

            # Create "running" record immediately (SYNC - must appear on dashboard)
            execution = create_running_execution(context)
            context.execution_id = execution&.id
            status_update_completed = false
            raised_exception = nil

            begin
              @app.call(context)
              context.completed_at = Time.current

              begin
                complete_execution(execution, context, status: "success")
                status_update_completed = true
              rescue StandardError
                # Let ensure block handle via mark_execution_failed!
              end
            rescue StandardError => e
              context.completed_at = Time.current
              context.error = e
              raised_exception = e

              begin
                complete_execution(execution, context, status: determine_error_status(e))
                status_update_completed = true
              rescue StandardError
                # Let ensure block handle via mark_execution_failed!
              end

              raise
            ensure
              # Emergency fallback if update failed
              mark_execution_failed!(execution, error: raised_exception || $!) unless status_update_completed
            end

            context
          end

          private

          # Creates initial execution record with 'running' status
          #
          # Creates the record synchronously so it appears on the dashboard immediately.
          # Returns nil on failure to avoid breaking the actual execution.
          #
          # @param context [Context] The execution context
          # @return [Execution, nil] The created record, or nil on failure
          def create_running_execution(context)
            return nil unless tracking_enabled?(context)
            return nil unless execution_model_available?
            return nil if context.cached? && !track_cache_hits?

            data = build_running_execution_data(context)
            Execution.create!(data)
          rescue StandardError => e
            error("Failed to create running execution record: #{e.message}")
            nil
          end

          # Updates execution record with completion data
          #
          # Updates the existing record with final status, duration, and metrics.
          # Falls back to creating a new record if the initial record is nil.
          # Errors are re-raised to allow the ensure block to handle them.
          #
          # @param execution [Execution, nil] The execution record to update
          # @param context [Context] The execution context
          # @param status [String] Final status ("success", "error", "timeout")
          # @raise [StandardError] Re-raises any errors for ensure block to handle
          def complete_execution(execution, context, status:)
            return unless tracking_enabled?(context)
            return if context.cached? && !track_cache_hits?
            return unless execution_model_available?

            # Fall back to legacy create if no execution record exists
            unless execution
              persist_execution(context, status: status)
              return
            end

            update_data = build_completion_data(context, status)

            if async_logging?
              # For async updates, use a job (if update support exists)
              # For now, update synchronously to ensure dashboard shows correct status
              execution.update!(update_data)
            else
              execution.update!(update_data)
            end
          rescue StandardError => e
            error("Failed to complete execution record: #{e.message}")
            raise # Re-raise for ensure block to handle via mark_execution_failed!
          end

          # Emergency fallback to mark execution as failed
          #
          # Uses update_all to bypass ActiveRecord callbacks and validations,
          # ensuring the status is updated even if the model is in an invalid state.
          # Only updates records that are still in 'running' status.
          #
          # @param execution [Execution, nil] The execution record
          # @param error [Exception, nil] The exception that caused the failure
          def mark_execution_failed!(execution, error: nil)
            return unless execution&.id
            return unless execution.status == "running"

            error_message = error ? "#{error.class}: #{error.message}".truncate(1000) : "Unknown error"

            update_data = {
              status: "error",
              completed_at: Time.current,
              error_class: error&.class&.name || "UnknownError",
              error_message: error_message
            }

            execution.class.where(id: execution.id, status: "running").update_all(update_data)
          rescue StandardError => e
            error("CRITICAL: Failed emergency status update for execution #{execution&.id}: #{e.message}")
          end

          # Determines the status based on error type
          #
          # @param error [Exception] The exception that occurred
          # @return [String] The determined status ("timeout" or "error")
          def determine_error_status(error)
            error.is_a?(Timeout::Error) ? "timeout" : "error"
          end

          # Builds data for initial running execution record
          #
          # @param context [Context] The execution context
          # @return [Hash] Execution data for creating running record
          def build_running_execution_data(context)
            data = {
              agent_type: context.agent_class&.name,
              agent_version: config(:version, "1.0"),
              model_id: context.model,
              status: "running",
              started_at: context.started_at,
              input_tokens: 0,
              output_tokens: 0,
              total_cost: 0,
              attempts_count: context.attempts_made
            }

            # Add tenant_id only if multi-tenancy is enabled and tenant is set
            if global_config.multi_tenancy_enabled? && context.tenant_id.present?
              data[:tenant_id] = context.tenant_id
            end

            # Add sanitized parameters
            data[:parameters] = sanitize_parameters(context)

            data
          end

          # Builds data for completing an execution record
          #
          # @param context [Context] The execution context
          # @param status [String] Final status ("success", "error", "timeout")
          # @return [Hash] Update data for completing the record
          def build_completion_data(context, status)
            data = {
              status: status,
              completed_at: context.completed_at,
              duration_ms: context.duration_ms,
              cache_hit: context.cached?,
              input_tokens: context.input_tokens || 0,
              output_tokens: context.output_tokens || 0,
              total_cost: context.total_cost || 0,
              attempts_count: context.attempts_made
            }

            # Add cache key for cache hit executions
            if context.cached? && context[:cache_key]
              data[:response_cache_key] = context[:cache_key]
            end

            # Add error details if present
            if context.error
              data[:error_class] = context.error.class.name
              data[:error_message] = truncate_error_message(context.error.message)
            end

            # Add custom metadata
            data[:metadata] = context.metadata if context.metadata.any?

            # Add enhanced tool calls if present
            if context[:tool_calls].present?
              data[:tool_calls] = context[:tool_calls]
              data[:tool_calls_count] = context[:tool_calls].size
            end

            # Add response if persist_responses is enabled
            if global_config.persist_responses && context.output.respond_to?(:content)
              data[:response] = serialize_response(context)
            end

            data
          end

          # Persists execution data to database (legacy fallback)
          #
          # Used when initial running record creation failed.
          #
          # @param context [Context] The execution context
          # @param status [String] "success" or "error"
          def persist_execution(context, status:)
            return unless execution_model_available?

            data = build_execution_data(context, status)

            if async_logging?
              queue_async_logging(data)
            else
              create_execution_record(data)
            end
          rescue StandardError => e
            error("Failed to record execution: #{e.message}")
          end

          # Builds execution data hash
          #
          # @param context [Context] The execution context
          # @param status [String] "success" or "error"
          # @return [Hash] Execution data
          def build_execution_data(context, status)
            data = {
              agent_type: context.agent_class&.name,
              agent_version: config(:version, "1.0"),
              model_id: context.model,
              status: determine_status(context, status),
              duration_ms: context.duration_ms,
              started_at: context.started_at,
              completed_at: context.completed_at,
              cache_hit: context.cached?,
              input_tokens: context.input_tokens || 0,
              output_tokens: context.output_tokens || 0,
              total_cost: context.total_cost || 0,
              attempts_count: context.attempts_made
            }

            # Add tenant_id only if multi-tenancy is enabled and tenant is set
            if global_config.multi_tenancy_enabled? && context.tenant_id.present?
              data[:tenant_id] = context.tenant_id
            end

            # Add cache key for cache hit executions
            if context.cached? && context[:cache_key]
              data[:response_cache_key] = context[:cache_key]
            end

            # Add error details if present
            if context.error
              data[:error_class] = context.error.class.name
              data[:error_message] = truncate_error_message(context.error.message)
            end

            # Add custom metadata
            data[:metadata] = context.metadata if context.metadata.any?

            # Add sanitized parameters
            data[:parameters] = sanitize_parameters(context)

            # Add enhanced tool calls if present
            if context[:tool_calls].present?
              data[:tool_calls] = context[:tool_calls]
              data[:tool_calls_count] = context[:tool_calls].size
            end

            # Add response if persist_responses is enabled
            if global_config.persist_responses && context.output.respond_to?(:content)
              data[:response] = serialize_response(context)
            end

            data
          end

          # Determines the status based on context and error type
          #
          # @param context [Context] The execution context
          # @param base_status [String] The base status ("success" or "error")
          # @return [String] The determined status
          def determine_status(context, base_status)
            return base_status if base_status == "success"

            # Check for timeout errors
            if context.error.is_a?(Timeout::Error)
              "timeout"
            else
              base_status
            end
          end

          # Sanitizes parameters for storage, redacting sensitive values
          #
          # @param context [Context] The execution context
          # @return [Hash] Sanitized parameters
          def sanitize_parameters(context)
            return {} unless context.agent_instance.respond_to?(:options, true)

            params = context.agent_instance.send(:options) rescue {}
            params = params.dup
            params.transform_keys!(&:to_s)

            SENSITIVE_KEYS.each do |key|
              params[key] = "[REDACTED]" if params.key?(key)
            end

            params
          end

          # Sensitive parameter keys that should be redacted
          SENSITIVE_KEYS = %w[
            password token api_key secret credential auth key
            access_token refresh_token private_key secret_key
          ].freeze

          # Truncates error message to prevent database issues
          #
          # @param message [String] The error message
          # @return [String] Truncated message
          def truncate_error_message(message)
            return "" if message.nil?

            message.to_s.truncate(1000)
          rescue StandardError
            message.to_s[0, 1000]
          end

          # Serializes the response content for storage
          #
          # @param context [Context] The execution context
          # @return [Hash, nil] Serialized response data
          def serialize_response(context)
            return nil unless context.output

            content = context.output.content
            return nil if content.nil?

            # Build response hash similar to core instrumentation
            response_data = { content: content }

            # Add model_id if available
            response_data[:model_id] = context.model_used if context.model_used

            # Add token info if available
            response_data[:input_tokens] = context.input_tokens if context.input_tokens
            response_data[:output_tokens] = context.output_tokens if context.output_tokens

            # Apply redaction for sensitive data
            Redactor.redact(response_data)
          rescue StandardError => e
            error("Failed to serialize response: #{e.message}")
            nil
          end

          # Queues async logging via background job
          #
          # @param data [Hash] Execution data
          def queue_async_logging(data)
            Infrastructure::ExecutionLoggerJob.perform_later(data)
          end

          # Creates execution record synchronously
          #
          # @param data [Hash] Execution data
          def create_execution_record(data)
            Execution.create!(data)
          end

          # Returns whether tracking is enabled for this agent type
          #
          # @param context [Context] The execution context
          # @return [Boolean]
          def tracking_enabled?(context)
            cfg = global_config

            case context.agent_type
            when :embedding
              cfg.track_embeddings
            when :moderation
              cfg.track_moderation
            when :image
              cfg.track_image_generation
            when :audio
              cfg.track_audio
            else
              cfg.track_executions
            end
          rescue StandardError
            false
          end

          # Returns whether to track cache hits
          #
          # @return [Boolean]
          def track_cache_hits?
            global_config.respond_to?(:track_cache_hits) && global_config.track_cache_hits
          rescue StandardError
            false
          end

          # Returns whether async logging is enabled
          #
          # @return [Boolean]
          def async_logging?
            global_config.async_logging && defined?(Infrastructure::ExecutionLoggerJob)
          rescue StandardError
            false
          end

          # Returns whether the Execution model is available
          #
          # @return [Boolean]
          def execution_model_available?
            defined?(RubyLLM::Agents::Execution)
          end
        end
      end
    end
  end
end
