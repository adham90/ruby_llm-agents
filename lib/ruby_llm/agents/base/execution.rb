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
          return dry_run_response if @options[:dry_run]
          return uncached_call(&block) if @options[:skip_cache] || !self.class.cache_enabled?

          # Note: Cached responses don't stream (already complete)
          cache_store.fetch(cache_key, expires_in: self.class.cache_ttl) do
            uncached_call(&block)
          end
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
            if self.class.streaming && block_given?
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
              tools: self.class.tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s }
            },
            model_id: model,
            temperature: temperature,
            streaming: self.class.streaming
          )
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

        # Validates that all required parameters are present
        #
        # @raise [ArgumentError] If required parameters are missing
        # @return [void]
        def validate_required_params!
          required = self.class.params.select { |_, v| v[:required] }.keys
          missing = required.reject { |p| @options.key?(p) || @options.key?(p.to_s) }
          raise ArgumentError, "#{self.class} missing required params: #{missing.join(', ')}" if missing.any?
        end

        # Builds and configures the RubyLLM client
        #
        # @return [RubyLLM::Chat] Configured chat client
        def build_client
          client = RubyLLM.chat
            .with_model(model)
            .with_temperature(temperature)
          client = client.with_instructions(system_prompt) if system_prompt
          client = client.with_schema(schema) if schema
          client = client.with_tools(*self.class.tools) if self.class.tools.any?
          client
        end

        # Builds a client with a specific model
        #
        # @param model_id [String] The model identifier
        # @return [RubyLLM::Chat] Configured chat client
        def build_client_with_model(model_id)
          client = RubyLLM.chat
            .with_model(model_id)
            .with_temperature(temperature)
          client = client.with_instructions(system_prompt) if system_prompt
          client = client.with_schema(schema) if schema
          client = client.with_tools(*self.class.tools) if self.class.tools.any?
          client
        end

        # Builds a client with pre-populated conversation history
        #
        # Useful for multi-turn conversations or providing context.
        #
        # @param messages [Array<Hash>] Messages with :role and :content keys
        # @return [RubyLLM::Chat] Client with messages added
        # @example
        #   build_client_with_messages([
        #     { role: "user", content: "Hello" },
        #     { role: "assistant", content: "Hi there!" }
        #   ])
        def build_client_with_messages(messages)
          messages.reduce(build_client) do |client, message|
            client.with_message(message[:role], message[:content])
          end
        end
      end
    end
  end
end
