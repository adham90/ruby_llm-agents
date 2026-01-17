# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Main execution flow for agents
      #
      # Handles the core execution logic including caching, streaming,
      # client building, and parameter validation.
      module Execution
        # Executes the agent and returns the processed response
        #
        # Handles caching, dry-run mode, and delegates to uncached_call
        # for actual LLM execution.
        #
        # @yield [chunk] Yields chunks when streaming is enabled
        # @yieldparam chunk [RubyLLM::Chunk] A streaming chunk with content
        # @return [Object] The processed LLM response
        def call(&block)
          # Resolve tenant configuration before execution
          resolve_tenant_context!

          return dry_run_response if @options[:dry_run]
          return uncached_call(&block) if @options[:skip_cache] || !self.class.cache_enabled?

          cache_key = agent_cache_key

          # Check for cache hit BEFORE fetch to record it
          if cache_store.exist?(cache_key)
            started_at = Time.current
            cached_result = cache_store.read(cache_key)
            record_cache_hit_execution(cache_key, cached_result, started_at) if cached_result
            return cached_result
          end

          # Cache miss - execute and store
          cache_store.fetch(cache_key, expires_in: self.class.cache_ttl) do
            uncached_call(&block)
          end
        end

        # Resolves tenant context from the :tenant option
        #
        # The tenant option can be:
        # - String: Just the tenant_id (uses resolver or DB for config)
        # - Hash: Full config { id:, name:, daily_limit:, daily_token_limit:, ... }
        #
        # @return [void]
        def resolve_tenant_context!
          tenant_option = @options[:tenant]
          return unless tenant_option

          if tenant_option.is_a?(Hash)
            # Full config passed - extract id and store config
            @tenant_id = tenant_option[:id]&.to_s
            @tenant_config = tenant_option.except(:id)
          else
            # Just tenant_id passed
            @tenant_id = tenant_option.to_s
            @tenant_config = nil
          end
        end

        # Returns the resolved tenant ID
        #
        # @return [String, nil] The tenant identifier
        def resolved_tenant_id
          return @tenant_id if defined?(@tenant_id) && @tenant_id.present?

          config = RubyLLM::Agents.configuration
          return nil unless config.multi_tenancy_enabled?

          config.current_tenant_id
        end

        # Returns the runtime tenant config (if passed via :tenant option)
        #
        # @return [Hash, nil] Runtime tenant configuration
        def runtime_tenant_config
          @tenant_config if defined?(@tenant_config)
        end

        # Executes the agent without caching
        #
        # Routes to reliability-enabled execution if configured, otherwise
        # uses simple single-attempt execution.
        #
        # @yield [chunk] Yields chunks when streaming is enabled
        # @return [Object] The processed response
        def uncached_call(&block)
          if reliability_enabled?
            execute_with_reliability(&block)
          else
            instrument_execution { execute_single_attempt(&block) }
          end
        end

        # Executes a single LLM attempt with timeout
        #
        # @param model_override [String, nil] Optional model to use instead of default
        # @yield [chunk] Yields chunks when streaming is enabled
        # @return [Result] A Result object with processed content and metadata
        def execute_single_attempt(model_override: nil, &block)
          current_client = model_override ? build_client_with_model(model_override) : client
          @execution_started_at ||= Time.current
          reset_accumulated_tool_calls!

          Timeout.timeout(self.class.timeout) do
            if streaming_enabled? && block_given?
              execute_with_streaming(current_client, &block)
            else
              response = current_client.ask(user_prompt, **ask_options)
              extract_tool_calls_from_client(current_client)
              capture_response(response)
              build_result(process_response(response), response)
            end
          end
        end

        # Executes an LLM request with streaming enabled
        #
        # Yields chunks to the provided block as they arrive and tracks
        # time to first token for latency analysis.
        #
        # @param current_client [RubyLLM::Chat] The configured client
        # @yield [chunk] Yields each chunk as it arrives
        # @yieldparam chunk [RubyLLM::Chunk] A streaming chunk
        # @return [Result] A Result object with processed content and metadata
        def execute_with_streaming(current_client, &block)
          first_chunk_at = nil

          response = current_client.ask(user_prompt, **ask_options) do |chunk|
            first_chunk_at ||= Time.current
            yield chunk if block_given?
          end

          if first_chunk_at && @execution_started_at
            @time_to_first_token_ms = ((first_chunk_at - @execution_started_at) * 1000).to_i
          end

          extract_tool_calls_from_client(current_client)
          capture_response(response)
          build_result(process_response(response), response)
        end

        # Returns prompt info without making an API call (debug mode)
        #
        # @return [Result] A Result with dry run configuration info
        def dry_run_response
          Result.new(
            content: {
              dry_run: true,
              agent: self.class.name,
              model: model,
              temperature: temperature,
              timeout: self.class.timeout,
              system_prompt: system_prompt,
              user_prompt: user_prompt,
              attachments: @options[:with],
              schema: schema&.class&.name,
              streaming: self.class.streaming,
              tools: resolved_tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s }
            },
            model_id: model,
            temperature: temperature,
            streaming: self.class.streaming
          )
        end

        # Resolves tools for this execution
        #
        # Checks for instance method override first (for dynamic tools),
        # then falls back to class-level DSL configuration. This allows
        # agents to define tools dynamically based on runtime context.
        #
        # @return [Array<Class>] Tool classes to use
        def resolved_tools
          # Check if instance defines tools method (not inherited from class singleton)
          if self.class.instance_methods(false).include?(:tools)
            tools
          else
            self.class.tools
          end
        end

        # Resolves messages for this execution
        #
        # Priority order:
        # 1. @override_messages (set via with_messages)
        # 2. :messages option passed at call time
        # 3. messages template method defined in subclass
        #
        # @return [Array<Hash>] Messages to apply to conversation
        def resolved_messages
          return @override_messages if @override_messages&.any?
          return @options[:messages] if @options[:messages]&.any?

          messages
        end

        # Returns the consolidated reliability configuration for this agent instance
        #
        # @return [Hash] Reliability config with :retries, :fallback_models, :total_timeout, :circuit_breaker
        def reliability_config
          default_retries = RubyLLM::Agents.configuration.default_retries
          {
            retries: self.class.retries || default_retries,
            fallback_models: self.class.fallback_models,
            total_timeout: self.class.total_timeout,
            circuit_breaker: self.class.circuit_breaker_config
          }
        end

        # Returns whether any reliability features are enabled for this agent
        #
        # @return [Boolean] true if retries, fallbacks, or circuit breaker is configured
        def reliability_enabled?
          config = reliability_config
          (config[:retries]&.dig(:max) || 0) > 0 ||
            config[:fallback_models]&.any? ||
            config[:circuit_breaker].present?
        end

        # Returns whether streaming is enabled for this execution
        #
        # Checks both class-level DSL setting and instance-level override
        # (set by the stream class method).
        #
        # @return [Boolean] true if streaming is enabled
        def streaming_enabled?
          @force_streaming || self.class.streaming
        end

        # Returns options to pass to the ask method
        #
        # Currently supports :with for attachments (images, PDFs, etc.)
        #
        # @return [Hash] Options for the ask call
        def ask_options
          opts = {}
          opts[:with] = @options[:with] if @options[:with]
          opts
        end

        # Validates that all required parameters are present and types match
        #
        # @raise [ArgumentError] If required parameters are missing or types don't match
        # @return [void]
        def validate_required_params!
          self.class.params.each do |name, config|
            value = @options[name] || @options[name.to_s]
            has_value = @options.key?(name) || @options.key?(name.to_s)

            # Check required
            if config[:required] && !has_value
              raise ArgumentError, "#{self.class} missing required param: #{name}"
            end

            # Check type if specified and value is present (not nil)
            if config[:type] && has_value && !value.nil?
              unless value.is_a?(config[:type])
                raise ArgumentError,
                  "#{self.class} expected #{config[:type]} for :#{name}, got #{value.class}"
              end
            end
          end
        end

        # Builds and configures the RubyLLM client
        #
        # @return [RubyLLM::Chat] Configured chat client
        def build_client
          # Apply database-backed API configuration if available
          apply_api_configuration!

          client = RubyLLM.chat
            .with_model(model)
            .with_temperature(temperature)
          client = client.with_instructions(system_prompt) if system_prompt
          client = client.with_schema(schema) if schema
          client = client.with_tools(*resolved_tools) if resolved_tools.any?
          client = apply_messages(client, resolved_messages) if resolved_messages.any?
          client
        end

        # Applies database-backed API configuration to RubyLLM
        #
        # Resolution priority: per-tenant DB > global DB > RubyLLM.configure
        # Only applies if the api_configurations table exists.
        #
        # @return [void]
        def apply_api_configuration!
          return unless api_configuration_available?

          resolved_config = ApiConfiguration.resolve(tenant_id: resolved_tenant_id)
          resolved_config.apply_to_ruby_llm!
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents] Failed to apply API config: #{e.message}")
        end

        # Checks if API configuration table is available
        #
        # @return [Boolean] true if table exists and is accessible
        def api_configuration_available?
          return @api_config_available if defined?(@api_config_available)

          @api_config_available = begin
            ApiConfiguration.table_exists?
          rescue StandardError
            false
          end
        end

        # Builds a client with a specific model
        #
        # @param model_id [String] The model identifier
        # @return [RubyLLM::Chat] Configured chat client
        def build_client_with_model(model_id)
          # Apply database-backed API configuration if available
          apply_api_configuration!

          client = RubyLLM.chat
            .with_model(model_id)
            .with_temperature(temperature)
          client = client.with_instructions(system_prompt) if system_prompt
          client = client.with_schema(schema) if schema
          client = client.with_tools(*resolved_tools) if resolved_tools.any?
          client = apply_messages(client, resolved_messages) if resolved_messages.any?
          client
        end

        # Applies conversation history to the client
        #
        # @param client [RubyLLM::Chat] The chat client
        # @param msgs [Array<Hash>] Messages with :role and :content keys
        # @return [RubyLLM::Chat] Client with messages applied
        def apply_messages(client, msgs)
          msgs.each do |message|
            client.add_message(role: message[:role].to_sym, content: message[:content])
          end
          client
        end

        # Builds a client with pre-populated conversation history
        #
        # @deprecated Use resolved_messages and apply_messages instead.
        #   Override the messages template method or pass messages: option to call.
        # @param messages [Array<Hash>] Messages with :role and :content keys
        # @return [RubyLLM::Chat] Client with messages added
        # @example
        #   build_client_with_messages([
        #     { role: "user", content: "Hello" },
        #     { role: "assistant", content: "Hi there!" }
        #   ])
        def build_client_with_messages(messages)
          apply_messages(build_client, messages)
        end
      end
    end
  end
end
