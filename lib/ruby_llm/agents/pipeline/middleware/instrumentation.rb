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
          # @param context [Context] The execution context
          # @return [Context] The context with timing info
          def call(context)
            context.started_at = Time.current

            begin
              @app.call(context)
              context.completed_at = Time.current
              record_success(context)
            rescue StandardError => e
              context.completed_at = Time.current
              context.error = e
              record_failure(context)
              raise
            end

            context
          end

          private

          # Records a successful execution
          #
          # @param context [Context] The execution context
          def record_success(context)
            return unless tracking_enabled?(context)
            return if context.cached? && !track_cache_hits?

            persist_execution(context, status: "success")
          end

          # Records a failed execution
          #
          # @param context [Context] The execution context
          def record_failure(context)
            return unless tracking_enabled?(context)

            persist_execution(context, status: "error")
          end

          # Persists execution data to database
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

          # Queues async logging via background job
          #
          # @param data [Hash] Execution data
          def queue_async_logging(data)
            ExecutionLoggerJob.perform_later(data)
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
            global_config.async_logging && defined?(ExecutionLoggerJob)
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
