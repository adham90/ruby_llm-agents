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

            trace(context) do
              # Create "running" record immediately (SYNC - must appear on dashboard)
              execution = create_running_execution(context)
              context.execution_id = execution&.id
              emit_start_notification(context)
              status_update_completed = false
              raised_exception = nil

              begin
                @app.call(context)
                context.completed_at = Time.current

                begin
                  complete_execution(execution, context, status: "success")
                  status_update_completed = true
                rescue
                  # Let ensure block handle via mark_execution_failed!
                end

                emit_complete_notification(context, "success")
              rescue => e
                context.completed_at = Time.current
                context.error = e
                raised_exception = e

                begin
                  complete_execution(execution, context, status: determine_error_status(e))
                  status_update_completed = true
                rescue
                  # Let ensure block handle via mark_execution_failed!
                end

                emit_complete_notification(context, determine_error_status(e))
                raise
              ensure
                # Emergency fallback if update failed
                mark_execution_failed!(execution, error: raised_exception || $!) unless status_update_completed
              end

              context
            end
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
            execution = Execution.create!(data)

            # Root executions point root_execution_id at themselves
            if execution.parent_execution_id.nil? && execution.root_execution_id.nil?
              execution.update_column(:root_execution_id, execution.id)
            end
            context.root_execution_id = execution.root_execution_id || execution.id

            # Create detail record with parameters
            params = sanitize_parameters(context)
            if params.present? && params != {}
              execution.create_detail!(parameters: params)
            end

            execution
          rescue => e
            error("Failed to create running execution record: #{e.message}", context)
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
            execution.update!(update_data)

            # Save detail data (prompts, responses, tool calls, etc.)
            save_execution_details(execution, context, status)
          rescue => e
            error("Failed to complete execution record: #{e.message}", context)
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

            error_message = build_error_message(error)

            update_data = {
              status: "error",
              completed_at: Time.current,
              error_class: error&.class&.name || "UnknownError"
            }

            execution.class.where(id: execution.id, status: "running").update_all(update_data)

            # Store error_message in detail table (best-effort)
            begin
              detail_attrs = {error_message: error_message}
              if execution.detail
                execution.detail.update_columns(detail_attrs)
              else
                RubyLLM::Agents::ExecutionDetail.create!(detail_attrs.merge(execution_id: execution.id))
              end
            rescue => e
              debug("Failed to store error detail: #{e.message}")
            end
          rescue => e
            error("CRITICAL: Failed emergency status update for execution #{execution&.id}: #{e.message}")
          end

          # Builds an informative error message including backtrace context
          #
          # Preserves the error class, message, and the most relevant
          # backtrace frames (up to 10) so developers can trace the
          # failure origin without needing to reproduce it.
          #
          # @param error [Exception, nil] The exception
          # @return [String] Formatted error message with backtrace
          def build_error_message(error)
            return "Unknown error" unless error

            parts = ["#{error.class}: #{error.message}"]

            if error.backtrace&.any?
              relevant_frames = error.backtrace.first(10)
              parts << "Backtrace (first #{relevant_frames.size} frames):"
              parts.concat(relevant_frames.map { |frame| "  #{frame}" })
            end

            parts.join("\n").truncate(5000)
          end

          # Determines the status based on error type
          #
          # @param error [Exception] The exception that occurred
          # @return [String] The determined status ("timeout" or "error")
          def determine_error_status(error)
            error.is_a?(Timeout::Error) ? "timeout" : "error"
          end

          # Emits an AS::Notification for execution start
          #
          # Fires even when DB tracking is disabled — observability should
          # work independently of persistence.
          #
          # @param context [Context] The execution context
          def emit_start_notification(context)
            ActiveSupport::Notifications.instrument(
              "ruby_llm_agents.execution.start",
              agent_type: context.agent_class&.name,
              model: context.model,
              tenant_id: context.tenant_id,
              execution_id: context.execution_id
            )
          rescue => e
            debug("Start notification failed: #{e.message}", context)
          end

          # Emits an AS::Notification for execution completion or error
          #
          # Uses execution.complete for success, execution.error for failures.
          # Fires even when DB tracking is disabled.
          #
          # @param context [Context] The execution context
          # @param status [String] "success", "error", or "timeout"
          def emit_complete_notification(context, status)
            event = (status == "success") ? "ruby_llm_agents.execution.complete" : "ruby_llm_agents.execution.error"

            ActiveSupport::Notifications.instrument(
              event,
              agent_type: context.agent_class&.name,
              agent_type_symbol: context.agent_type,
              execution_id: context.execution_id,
              model: context.model,
              model_used: context.model_used,
              tenant_id: context.tenant_id,
              status: status,
              duration_ms: context.duration_ms,
              input_tokens: context.input_tokens,
              output_tokens: context.output_tokens,
              total_tokens: context.total_tokens,
              input_cost: context.input_cost,
              output_cost: context.output_cost,
              total_cost: context.total_cost,
              cached: context.cached?,
              attempts_made: context.attempts_made,
              finish_reason: context.finish_reason,
              time_to_first_token_ms: context.time_to_first_token_ms,
              error_class: context.error&.class&.name,
              error_message: context.error&.message
            )
          rescue => e
            debug("Complete notification failed: #{e.message}", context)
          end

          # Builds data for initial running execution record
          #
          # @param context [Context] The execution context
          # @return [Hash] Execution data for creating running record
          def build_running_execution_data(context)
            data = {
              agent_type: context.agent_class&.name,
              model_id: context.model,
              model_provider: resolve_model_provider(context.model),
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

            # Include agent-defined metadata so it appears on the dashboard immediately
            agent_meta = safe_agent_metadata(context)
            if agent_meta.any?
              data[:metadata] = agent_meta.transform_keys(&:to_s)

              # Extract tracing fields from metadata to dedicated columns
              data[:trace_id] = agent_meta[:trace_id] if agent_meta[:trace_id]
              data[:request_id] = agent_meta[:request_id] if agent_meta[:request_id]
              data[:parent_execution_id] = agent_meta[:parent_execution_id] if agent_meta[:parent_execution_id]
              data[:root_execution_id] = agent_meta[:root_execution_id] if agent_meta[:root_execution_id]
            end

            # Track replay source if this is a replayed execution
            replay_source_id = begin
              context.agent_instance&.send(:options)&.dig(:_replay_source_id)
            rescue
              nil
            end
            if replay_source_id
              data[:metadata] = (data[:metadata] || {}).merge("replay_source_id" => replay_source_id.to_s)
            end

            # Execution hierarchy (agent-as-tool) — context-level values take precedence
            if context.parent_execution_id.present?
              data[:parent_execution_id] = context.parent_execution_id
              data[:root_execution_id] = context.root_execution_id || context.parent_execution_id
            end

            # Inject tracker request_id and tags
            inject_tracker_data(context, data)

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
              attempts_count: context.attempts_made,
              chosen_model_id: context.model_used,
              finish_reason: context.finish_reason
            }

            # Merge metadata: agent metadata (base) < middleware metadata (overlay)
            agent_meta = safe_agent_metadata(context)
            merged_metadata = agent_meta.transform_keys(&:to_s)

            context_meta = begin
              context.metadata.dup
            rescue => e
              debug("Failed to read context metadata: #{e.message}", context)
              {}
            end
            context_meta.transform_keys!(&:to_s)
            merged_metadata.merge!(context_meta)

            if context.cached? && context[:cache_key]
              merged_metadata["response_cache_key"] = context[:cache_key]
            end
            data[:metadata] = merged_metadata if merged_metadata.any?

            # Error class on execution (error_message goes to detail)
            if context.error
              data[:error_class] = context.error.class.name
            end

            # Tool calls count on execution
            if context[:tool_calls].present?
              data[:tool_calls_count] = context[:tool_calls].size
            end

            # Attempts count on execution
            if context[:reliability_attempts].present?
              data[:attempts_count] = context[:reliability_attempts].size
            end

            data
          end

          # Saves detail data to the execution_details table after completion
          def save_execution_details(execution, context, status)
            return unless execution

            detail_data = {}

            if global_config.persist_prompts
              exec_opts = context.options[:options] || {}
              detail_data[:system_prompt] = exec_opts[:system_prompt]
              detail_data[:user_prompt] = context.input.to_s.presence
              detail_data[:assistant_prompt] = exec_opts[:assistant_prefill] if assistant_prompt_column_exists?
            end

            if context.error
              detail_data[:error_message] = build_error_message(context.error)
            end

            if context[:tool_calls].present?
              detail_data[:tool_calls] = context[:tool_calls]
            end

            if context[:reliability_attempts].present?
              detail_data[:attempts] = context[:reliability_attempts]
            end

            if global_config.persist_responses && context.output.respond_to?(:content)
              detail_data[:response] = serialize_response(context)
            end

            # Persist audio data for Speaker executions
            maybe_persist_audio_response(context, detail_data)

            has_data = detail_data.values.any? { |v| v.present? && v != {} && v != [] }
            return unless has_data

            if execution.detail
              execution.detail.update!(detail_data)
            else
              execution.create_detail!(detail_data)
            end
          rescue => e
            error("Failed to save execution details: #{e.message}", context)
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
          rescue => e
            error("Failed to record execution: #{e.message}", context)
          end

          # Builds execution data hash for the legacy single-step persistence path.
          #
          # Composes from build_running_execution_data and build_completion_data
          # to avoid duplication.
          #
          # @param context [Context] The execution context
          # @param status [String] "success" or "error"
          # @return [Hash] Execution data with _detail_data for detail record
          def build_execution_data(context, status)
            data = build_running_execution_data(context)
              .merge(build_completion_data(context, determine_status(context, status)))

            # Build detail data for separate creation
            detail_data = {parameters: sanitize_parameters(context)}
            if global_config.persist_prompts
              exec_opts = context.options[:options] || {}
              detail_data[:system_prompt] = exec_opts[:system_prompt]
              detail_data[:user_prompt] = context.input.to_s.presence
              detail_data[:assistant_prompt] = exec_opts[:assistant_prefill] if assistant_prompt_column_exists?
            end
            detail_data[:error_message] = build_error_message(context.error) if context.error
            detail_data[:tool_calls] = context[:tool_calls] if context[:tool_calls].present?
            detail_data[:attempts] = context[:reliability_attempts] if context[:reliability_attempts].present?
            if global_config.persist_responses && context.output.respond_to?(:content)
              detail_data[:response] = serialize_response(context)
            end

            maybe_persist_audio_response(context, detail_data)

            data[:_detail_data] = detail_data
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

            params = begin
              context.agent_instance.send(:options)
            rescue => e
              debug("Failed to extract agent options: #{e.message}", context)
              {}
            end
            params = params.dup
            params.transform_keys!(&:to_s)

            SENSITIVE_KEYS.each do |key|
              params[key] = "[REDACTED]" if params.key?(key)
            end

            INTERNAL_KEYS.each do |key|
              params.delete(key)
            end

            params
          end

          # Safely retrieves custom metadata from the agent instance
          #
          # Returns an empty hash if the agent doesn't define metadata,
          # the method raises, or the result isn't a Hash.
          #
          # @param context [Context] The execution context
          # @return [Hash] Agent-defined metadata, or empty hash
          def safe_agent_metadata(context)
            return {} unless context.agent_instance
            return {} unless context.agent_instance.respond_to?(:metadata)

            result = context.agent_instance.metadata
            result.is_a?(Hash) ? result : {}
          rescue => e
            debug("Failed to retrieve agent metadata: #{e.message}", context)
            {}
          end

          # Resolves the provider name for a given model ID
          #
          # Uses RubyLLM::Models.find which is an in-process registry lookup
          # (no API keys or network calls needed).
          #
          # @param model_id [String, nil] The model identifier
          # @return [String, nil] Provider name (e.g., "openai", "anthropic") or nil
          def resolve_model_provider(model_id)
            return nil unless model_id
            return nil unless defined?(RubyLLM::Models)

            model_info = RubyLLM::Models.find(model_id)
            provider = model_info&.provider
            provider&.to_s.presence
          rescue
            nil
          end

          # Injects tracker request_id and tags into execution data
          #
          # Reads @_track_request_id and @_track_tags from the agent instance,
          # which are set by BaseAgent#initialize when a Tracker is active.
          #
          # @param context [Context] The execution context
          # @param data [Hash] The execution data hash to modify
          def inject_tracker_data(context, data)
            agent = context.agent_instance
            return unless agent

            # Inject request_id
            track_request_id = agent.instance_variable_get(:@_track_request_id)
            if track_request_id && data[:request_id].blank?
              data[:request_id] = track_request_id
            end

            # Merge tracker tags into metadata
            track_tags = agent.instance_variable_get(:@_track_tags)
            if track_tags.is_a?(Hash) && track_tags.any?
              data[:metadata] = (data[:metadata] || {}).merge(
                "tags" => track_tags.transform_keys(&:to_s)
              )
            end
          rescue
            # Never let tracker data injection break execution
          end

          # Sensitive parameter keys that should be redacted
          SENSITIVE_KEYS = %w[
            password token api_key secret credential auth key
            access_token refresh_token private_key secret_key
          ].freeze

          # Internal keys that should be stripped from persisted parameters
          INTERNAL_KEYS = %w[
            _replay_source_id _ask_message _parent_execution_id _root_execution_id
          ].freeze

          # Truncates error message to prevent database issues
          #
          # @param message [String] The error message
          # @return [String] Truncated message
          def truncate_error_message(message)
            return "" if message.nil?

            message.to_s.truncate(5000)
          rescue
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
            response_data = {content: content}

            # Add model_id if available
            response_data[:model_id] = context.model_used if context.model_used

            # Add token info if available
            response_data[:input_tokens] = context.input_tokens if context.input_tokens
            response_data[:output_tokens] = context.output_tokens if context.output_tokens

            response_data
          rescue => e
            error("Failed to serialize response: #{e.message}", context)
            nil
          end

          # Persists audio response data for Speaker executions
          #
          # When persist_audio_data is enabled and the output is a SpeechResult with
          # audio binary data, stores a base64 data URI in the response column.
          # Always stores audio_url if present (lightweight, no binary).
          #
          # @param context [Context] The execution context
          # @param detail_data [Hash] The detail data hash to modify
          def maybe_persist_audio_response(context, detail_data)
            return unless context.output.is_a?(RubyLLM::Agents::SpeechResult)

            # Always persist audio_url if present (it's just a string, no binary)
            if context.output.audio_url.present?
              detail_data[:response] ||= {}
              detail_data[:response][:audio_url] = context.output.audio_url
            end

            # Persist full audio data URI only when opted in
            return unless global_config.respond_to?(:persist_audio_data) && global_config.persist_audio_data
            return unless context.output.audio.present?

            detail_data[:response] = serialize_audio_response(context.output)
          rescue => e
            error("Failed to persist audio response: #{e.message}", context)
          end

          # Serializes a SpeechResult into a hash for the response column
          #
          # @param result [SpeechResult] The speech result to serialize
          # @return [Hash] Serialized audio response data
          def serialize_audio_response(result)
            {
              audio_data_uri: result.to_data_uri,
              audio_url: result.audio_url,
              format: result.format.to_s,
              duration: result.duration,
              file_size: result.file_size,
              voice_id: result.voice_id,
              provider: result.provider.to_s
            }.compact
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
            detail_data = data.delete(:_detail_data)
            execution = Execution.create!(data)
            if detail_data&.values&.any? { |v| v.present? && v != {} && v != [] }
              execution.create_detail!(detail_data)
            end
            execution
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
            when :image
              cfg.track_image_generation
            when :audio
              cfg.track_audio
            else
              cfg.track_executions
            end
          rescue => e
            debug("Failed to check tracking config: #{e.message}", context)
            false
          end

          # Returns whether to track cache hits
          #
          # @return [Boolean]
          def track_cache_hits?
            global_config.respond_to?(:track_cache_hits) && global_config.track_cache_hits
          rescue => e
            debug("Failed to check track_cache_hits config: #{e.message}")
            false
          end

          # Returns whether async logging is enabled
          #
          # @return [Boolean]
          def async_logging?
            global_config.async_logging && defined?(Infrastructure::ExecutionLoggerJob)
          rescue => e
            debug("Failed to check async_logging config: #{e.message}")
            false
          end

          # Checks if the assistant_prompt column exists on execution_details
          #
          # Memoized to avoid repeated schema queries.
          #
          # @return [Boolean]
          def assistant_prompt_column_exists?
            return @_assistant_prompt_column_exists if defined?(@_assistant_prompt_column_exists)

            @_assistant_prompt_column_exists = begin
              defined?(RubyLLM::Agents::ExecutionDetail) &&
                RubyLLM::Agents::ExecutionDetail.column_names.include?("assistant_prompt")
            rescue => e
              debug("Failed to check assistant_prompt column: #{e.message}")
              false
            end
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
