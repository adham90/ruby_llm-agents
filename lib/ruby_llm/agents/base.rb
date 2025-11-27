# frozen_string_literal: true

module RubyLLM
  module Agents
    # Base class for LLM-powered agents
    #
    # Provides a DSL for configuring and executing agents that interact with
    # large language models. Includes built-in support for caching, timeouts,
    # structured output, and execution tracking.
    #
    # @example Creating an agent
    #   class SearchAgent < ApplicationAgent
    #     model "gpt-4o"
    #     temperature 0.0
    #     version "1.0"
    #     timeout 30
    #     cache 1.hour
    #
    #     param :query, required: true
    #     param :limit, default: 10
    #
    #     def system_prompt
    #       "You are a search assistant..."
    #     end
    #
    #     def user_prompt
    #       "Search for: #{query}"
    #     end
    #   end
    #
    # @example Calling an agent
    #   SearchAgent.call(query: "red dress")
    #   SearchAgent.call(query: "red dress", dry_run: true)    # Debug mode
    #   SearchAgent.call(query: "red dress", skip_cache: true) # Bypass cache
    #
    # @see RubyLLM::Agents::Instrumentation
    # @api public
    class Base
      include Instrumentation

      # @!visibility private
      VERSION = "1.0".freeze
      # @!visibility private
      CACHE_TTL = 1.hour

      class << self
        # Factory method to instantiate and execute an agent
        #
        # @param args [Array] Positional arguments (reserved for future use)
        # @param kwargs [Hash] Named parameters for the agent
        # @option kwargs [Boolean] :dry_run Return prompt info without API call
        # @option kwargs [Boolean] :skip_cache Bypass caching even if enabled
        # @option kwargs [String, Array<String>] :with Attachments (files, URLs) to send with the prompt
        # @yield [chunk] Yields chunks when streaming is enabled
        # @yieldparam chunk [RubyLLM::Chunk] A streaming chunk with content
        # @return [Object] The processed response from the agent
        #
        # @example Basic usage
        #   SearchAgent.call(query: "red dress")
        #
        # @example Debug mode
        #   SearchAgent.call(query: "red dress", dry_run: true)
        #
        # @example Streaming mode
        #   ChatAgent.call(message: "Hello") do |chunk|
        #     print chunk.content
        #   end
        #
        # @example With attachments
        #   VisionAgent.call(query: "Describe this image", with: "photo.jpg")
        #   VisionAgent.call(query: "Compare these", with: ["a.png", "b.png"])
        def call(*args, **kwargs, &block)
          new(*args, **kwargs).call(&block)
        end

        # @!group Configuration DSL

        # Sets or returns the LLM model for this agent class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "gpt-4o"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_model)
        end

        # Sets or returns the temperature for LLM responses
        #
        # @param value [Float, nil] Temperature value (0.0-2.0)
        # @return [Float] The current temperature setting
        # @example
        #   temperature 0.7
        def temperature(value = nil)
          @temperature = value if value
          @temperature || inherited_or_default(:temperature, RubyLLM::Agents.configuration.default_temperature)
        end

        # Sets or returns the version string for cache invalidation
        #
        # @param value [String, nil] Version string
        # @return [String] The current version
        # @example
        #   version "2.0"
        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, VERSION)
        end

        # Sets or returns the timeout in seconds for LLM requests
        #
        # @param value [Integer, nil] Timeout in seconds
        # @return [Integer] The current timeout setting
        # @example
        #   timeout 30
        def timeout(value = nil)
          @timeout = value if value
          @timeout || inherited_or_default(:timeout, RubyLLM::Agents.configuration.default_timeout)
        end

        # @!endgroup

        # @!group Reliability DSL

        # Configures retry behavior for this agent
        #
        # @param max [Integer] Maximum number of retry attempts (default: 0)
        # @param backoff [Symbol] Backoff strategy (:constant or :exponential)
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay between retries
        # @param on [Array<Class>] Error classes to retry on (extends defaults)
        # @return [Hash] The current retry configuration
        # @example
        #   retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [Timeout::Error]
        def retries(max: nil, backoff: nil, base: nil, max_delay: nil, on: nil)
          if max || backoff || base || max_delay || on
            @retries_config ||= RubyLLM::Agents.configuration.default_retries.dup
            @retries_config[:max] = max if max
            @retries_config[:backoff] = backoff if backoff
            @retries_config[:base] = base if base
            @retries_config[:max_delay] = max_delay if max_delay
            @retries_config[:on] = on if on
          end
          @retries_config || inherited_or_default(:retries_config, RubyLLM::Agents.configuration.default_retries)
        end

        # Returns the retry configuration for this agent
        #
        # @return [Hash, nil] The retry configuration
        def retries_config
          @retries_config || (superclass.respond_to?(:retries_config) ? superclass.retries_config : nil)
        end

        # Sets or returns fallback models to try when primary model fails
        #
        # @param models [Array<String>, nil] Model identifiers to use as fallbacks
        # @return [Array<String>] The current fallback models
        # @example
        #   fallback_models ["gpt-4o-mini", "gpt-4o"]
        def fallback_models(models = nil)
          @fallback_models = models if models
          @fallback_models || inherited_or_default(:fallback_models, RubyLLM::Agents.configuration.default_fallback_models)
        end

        # Sets or returns the total timeout for all retry/fallback attempts
        #
        # @param seconds [Integer, nil] Total timeout in seconds
        # @return [Integer, nil] The current total timeout
        # @example
        #   total_timeout 20
        def total_timeout(seconds = nil)
          @total_timeout = seconds if seconds
          @total_timeout || inherited_or_default(:total_timeout, RubyLLM::Agents.configuration.default_total_timeout)
        end

        # Configures circuit breaker for this agent
        #
        # @param errors [Integer] Number of errors to trigger open state
        # @param within [Integer] Rolling window in seconds
        # @param cooldown [Integer] Cooldown period in seconds when open
        # @return [Hash, nil] The current circuit breaker configuration
        # @example
        #   circuit_breaker errors: 10, within: 60, cooldown: 300
        def circuit_breaker(errors: nil, within: nil, cooldown: nil)
          if errors || within || cooldown
            @circuit_breaker_config ||= { errors: 10, within: 60, cooldown: 300 }
            @circuit_breaker_config[:errors] = errors if errors
            @circuit_breaker_config[:within] = within if within
            @circuit_breaker_config[:cooldown] = cooldown if cooldown
          end
          @circuit_breaker_config || (superclass.respond_to?(:circuit_breaker_config) ? superclass.circuit_breaker_config : nil)
        end

        # Returns the circuit breaker configuration for this agent
        #
        # @return [Hash, nil] The circuit breaker configuration
        def circuit_breaker_config
          @circuit_breaker_config || (superclass.respond_to?(:circuit_breaker_config) ? superclass.circuit_breaker_config : nil)
        end

        # @!endgroup

        # @!group Parameter DSL

        # Defines a parameter for the agent
        #
        # Creates an accessor method for the parameter that retrieves values
        # from the options hash, falling back to the default value.
        #
        # @param name [Symbol] The parameter name
        # @param required [Boolean] Whether the parameter is required
        # @param default [Object, nil] Default value if not provided
        # @return [void]
        # @example
        #   param :query, required: true
        #   param :limit, default: 10
        def param(name, required: false, default: nil)
          @params ||= {}
          @params[name] = { required: required, default: default }
          define_method(name) do
            @options[name] || @options[name.to_s] || self.class.params.dig(name, :default)
          end
        end

        # Returns all defined parameters including inherited ones
        #
        # @return [Hash{Symbol => Hash}] Parameter definitions
        def params
          parent = superclass.respond_to?(:params) ? superclass.params : {}
          parent.merge(@params || {})
        end

        # @!endgroup

        # @!group Caching DSL

        # Enables caching for this agent with optional TTL
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache 1.hour
        def cache(ttl = CACHE_TTL)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this agent
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          @cache_enabled || false
        end

        # Returns the cache TTL for this agent
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || CACHE_TTL
        end

        # @!endgroup

        # @!group Streaming DSL

        # Enables or returns streaming mode for this agent
        #
        # When streaming is enabled and a block is passed to call,
        # chunks will be yielded to the block as they arrive.
        #
        # @param value [Boolean, nil] Whether to enable streaming
        # @return [Boolean] The current streaming setting
        # @example
        #   streaming true
        def streaming(value = nil)
          @streaming = value unless value.nil?
          return @streaming unless @streaming.nil?

          inherited_or_default(:streaming, RubyLLM::Agents.configuration.default_streaming)
        end

        # @!endgroup

        # @!group Tools DSL

        # Sets or returns the tools available to this agent
        #
        # Tools are RubyLLM::Tool classes that the model can invoke.
        # The agent will automatically execute tool calls and continue
        # until the model produces a final response.
        #
        # @param tool_classes [Array<Class>] Tool classes to make available
        # @return [Array<Class>] The current tools
        # @example Single tool
        #   tools WeatherTool
        # @example Multiple tools
        #   tools WeatherTool, SearchTool, CalculatorTool
        def tools(*tool_classes)
          if tool_classes.any?
            @tools = tool_classes.flatten
          end
          @tools || inherited_or_default(:tools, RubyLLM::Agents.configuration.default_tools)
        end

        # @!endgroup

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end
      end

      # @!attribute [r] model
      #   @return [String] The LLM model being used
      # @!attribute [r] temperature
      #   @return [Float] The temperature setting
      # @!attribute [r] client
      #   @return [RubyLLM::Chat] The configured RubyLLM client
      # @!attribute [r] time_to_first_token_ms
      #   @return [Integer, nil] Time to first token in milliseconds (streaming only)
      # @!attribute [r] accumulated_tool_calls
      #   @return [Array<Hash>] Tool calls accumulated during execution
      attr_reader :model, :temperature, :client, :time_to_first_token_ms, :accumulated_tool_calls

      # Creates a new agent instance
      #
      # @param model [String] Override the class-level model setting
      # @param temperature [Float] Override the class-level temperature
      # @param options [Hash] Agent parameters defined via the param DSL
      # @raise [ArgumentError] If required parameters are missing
      def initialize(model: self.class.model, temperature: self.class.temperature, **options)
        @model = model
        @temperature = temperature
        @options = options
        @accumulated_tool_calls = []
        validate_required_params!
        @client = build_client
      end

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

      # @!group Template Methods (override in subclasses)

      # User prompt to send to the LLM
      #
      # @abstract Subclasses must implement this method
      # @return [String] The user prompt
      # @raise [NotImplementedError] If not overridden in subclass
      def user_prompt
        raise NotImplementedError, "#{self.class} must implement #user_prompt"
      end

      # System prompt for LLM instructions
      #
      # @return [String, nil] System instructions, or nil for none
      def system_prompt
        nil
      end

      # Response schema for structured output
      #
      # @return [RubyLLM::Schema, nil] Schema definition, or nil for free-form
      def schema
        nil
      end

      # Post-processes the LLM response
      #
      # Override to transform the response before returning to the caller.
      # Default implementation symbolizes hash keys.
      #
      # @param response [RubyLLM::Message] The raw response from the LLM
      # @return [Object] The processed result
      def process_response(response)
        content = response.content
        return content unless content.is_a?(Hash)
        content.transform_keys(&:to_sym)
      end

      # @!endgroup

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

      private

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

      # Executes the agent with retry/fallback/circuit breaker support
      #
      # @yield [chunk] Yields chunks when streaming is enabled
      # @return [Object] The processed response
      # @raise [Reliability::AllModelsExhaustedError] If all models fail
      # @raise [Reliability::BudgetExceededError] If budget limits exceeded
      # @raise [Reliability::TotalTimeoutError] If total timeout exceeded
      def execute_with_reliability(&block)
        config = reliability_config
        models_to_try = [model, *config[:fallback_models]].uniq
        total_deadline = config[:total_timeout] ? Time.current + config[:total_timeout] : nil
        started_at = Time.current

        # Pre-check budget
        BudgetTracker.check_budget!(self.class.name) if RubyLLM::Agents.configuration.budgets_enabled?

        instrument_execution_with_attempts(models_to_try: models_to_try) do |attempt_tracker|
          last_error = nil

          models_to_try.each do |current_model|
            # Check circuit breaker
            breaker = get_circuit_breaker(current_model)
            if breaker&.open?
              attempt_tracker.record_short_circuit(current_model)
              next
            end

            retries_remaining = config[:retries]&.dig(:max) || 0
            attempt_index = 0

            loop do
              # Check total timeout
              if total_deadline && Time.current > total_deadline
                elapsed = Time.current - started_at
                raise Reliability::TotalTimeoutError.new(config[:total_timeout], elapsed)
              end

              attempt = attempt_tracker.start_attempt(current_model)

              begin
                result = execute_single_attempt(model_override: current_model, &block)
                attempt_tracker.complete_attempt(attempt, success: true, response: @last_response)

                # Record success in circuit breaker
                breaker&.record_success!

                # Record budget spend
                if @last_response && RubyLLM::Agents.configuration.budgets_enabled?
                  record_attempt_cost(attempt_tracker)
                end

                # Use throw instead of return to allow instrument_execution_with_attempts
                # to properly complete the execution record before returning
                throw :execution_success, result

              rescue *retryable_errors(config) => e
                last_error = e
                attempt_tracker.complete_attempt(attempt, success: false, error: e)
                breaker&.record_failure!

                if retries_remaining > 0 && !past_deadline?(total_deadline)
                  retries_remaining -= 1
                  attempt_index += 1
                  retries_config = config[:retries] || {}
                  delay = Reliability.calculate_backoff(
                    strategy: retries_config[:backoff] || :exponential,
                    base: retries_config[:base] || 0.4,
                    max_delay: retries_config[:max_delay] || 3.0,
                    attempt: attempt_index
                  )
                  sleep(delay)
                else
                  break # Move to next model
                end

              rescue StandardError => e
                # Non-retryable error - record and move to next model
                last_error = e
                attempt_tracker.complete_attempt(attempt, success: false, error: e)
                breaker&.record_failure!
                break
              end
            end
          end

          # All models exhausted
          raise Reliability::AllModelsExhaustedError.new(models_to_try, last_error)
        end
      end

      # Returns the list of retryable error classes
      #
      # @param config [Hash] Reliability configuration
      # @return [Array<Class>] Error classes to retry on
      def retryable_errors(config)
        custom_errors = config[:retries]&.dig(:on) || []
        Reliability.default_retryable_errors + custom_errors
      end

      # Checks if the total deadline has passed
      #
      # @param deadline [Time, nil] The deadline
      # @return [Boolean] true if past deadline
      def past_deadline?(deadline)
        deadline && Time.current > deadline
      end

      # Gets or creates a circuit breaker for a model
      #
      # @param model_id [String] The model identifier
      # @return [CircuitBreaker, nil] The circuit breaker or nil if not configured
      def get_circuit_breaker(model_id)
        config = reliability_config[:circuit_breaker]
        return nil unless config

        CircuitBreaker.from_config(self.class.name, model_id, config)
      end

      # Records cost from an attempt to the budget tracker
      #
      # @param attempt_tracker [AttemptTracker] The attempt tracker
      # @return [void]
      def record_attempt_cost(attempt_tracker)
        successful = attempt_tracker.successful_attempt
        return unless successful

        # Calculate cost for this execution
        # Note: Full cost calculation happens in instrumentation, but we
        # record the spend here for budget tracking
        model_info = resolve_model_info(successful[:model_id])
        return unless model_info&.pricing

        input_tokens = successful[:input_tokens] || 0
        output_tokens = successful[:output_tokens] || 0

        input_price = model_info.pricing.text_tokens&.input || 0
        output_price = model_info.pricing.text_tokens&.output || 0

        total_cost = (input_tokens / 1_000_000.0 * input_price) +
                     (output_tokens / 1_000_000.0 * output_price)

        BudgetTracker.record_spend!(self.class.name, total_cost)
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Failed to record budget spend: #{e.message}")
      end

      # Resolves model info for cost calculation
      #
      # @param model_id [String] The model identifier
      # @return [Object, nil] Model info or nil
      def resolve_model_info(model_id)
        RubyLLM::Models.resolve(model_id)
      rescue StandardError
        nil
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

      # Returns the configured cache store
      #
      # @return [ActiveSupport::Cache::Store] The cache store
      def cache_store
        RubyLLM::Agents.configuration.cache_store
      end

      # Generates the full cache key for this agent invocation
      #
      # @return [String] Cache key in format "ruby_llm_agent/ClassName/version/hash"
      def cache_key
        ["ruby_llm_agent", self.class.name, self.class.version, cache_key_hash].join("/")
      end

      # Generates a hash of the cache key data
      #
      # @return [String] SHA256 hex digest of the cache key data
      def cache_key_hash
        Digest::SHA256.hexdigest(cache_key_data.to_json)
      end

      # Returns data to include in cache key generation
      #
      # Override to customize what parameters affect cache invalidation.
      #
      # @return [Hash] Data to hash for cache key
      def cache_key_data
        @options.except(:skip_cache, :dry_run, :with)
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

      # @!group Result Building

      # Builds a Result object from processed content and response metadata
      #
      # @param content [Hash, String] The processed response content
      # @param response [RubyLLM::Message] The raw LLM response
      # @return [Result] A Result object with full execution metadata
      def build_result(content, response)
        completed_at = Time.current
        input_tokens = result_response_value(response, :input_tokens)
        output_tokens = result_response_value(response, :output_tokens)
        response_model_id = result_response_value(response, :model_id)

        Result.new(
          content: content,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cached_tokens: result_response_value(response, :cached_tokens, 0),
          cache_creation_tokens: result_response_value(response, :cache_creation_tokens, 0),
          model_id: model,
          chosen_model_id: response_model_id || model,
          temperature: temperature,
          started_at: @execution_started_at,
          completed_at: completed_at,
          duration_ms: result_duration_ms(completed_at),
          time_to_first_token_ms: @time_to_first_token_ms,
          finish_reason: result_finish_reason(response),
          streaming: self.class.streaming,
          input_cost: result_input_cost(input_tokens, response_model_id),
          output_cost: result_output_cost(output_tokens, response_model_id),
          total_cost: result_total_cost(input_tokens, output_tokens, response_model_id),
          tool_calls: @accumulated_tool_calls,
          tool_calls_count: @accumulated_tool_calls.size
        )
      end

      # Safely extracts a value from the response object
      #
      # @param response [Object] The response object
      # @param method [Symbol] The method to call
      # @param default [Object] Default value if method doesn't exist
      # @return [Object] The extracted value or default
      def result_response_value(response, method, default = nil)
        return default unless response.respond_to?(method)
        response.send(method) || default
      end

      # Calculates execution duration in milliseconds
      #
      # @param completed_at [Time] When execution completed
      # @return [Integer, nil] Duration in ms or nil
      def result_duration_ms(completed_at)
        return nil unless @execution_started_at
        ((completed_at - @execution_started_at) * 1000).to_i
      end

      # Extracts finish reason from response
      #
      # @param response [Object] The response object
      # @return [String, nil] Normalized finish reason
      def result_finish_reason(response)
        reason = result_response_value(response, :finish_reason) ||
                 result_response_value(response, :stop_reason)
        return nil unless reason

        # Normalize to standard values
        case reason.to_s.downcase
        when "stop", "end_turn" then "stop"
        when "length", "max_tokens" then "length"
        when "content_filter", "safety" then "content_filter"
        when "tool_calls", "tool_use" then "tool_calls"
        else "other"
        end
      end

      # Calculates input cost from tokens
      #
      # @param input_tokens [Integer, nil] Number of input tokens
      # @param response_model_id [String, nil] Model that responded
      # @return [Float, nil] Input cost in USD
      def result_input_cost(input_tokens, response_model_id)
        return nil unless input_tokens
        model_info = result_model_info(response_model_id)
        return nil unless model_info&.pricing
        price = model_info.pricing.text_tokens&.input || 0
        (input_tokens / 1_000_000.0 * price).round(6)
      end

      # Calculates output cost from tokens
      #
      # @param output_tokens [Integer, nil] Number of output tokens
      # @param response_model_id [String, nil] Model that responded
      # @return [Float, nil] Output cost in USD
      def result_output_cost(output_tokens, response_model_id)
        return nil unless output_tokens
        model_info = result_model_info(response_model_id)
        return nil unless model_info&.pricing
        price = model_info.pricing.text_tokens&.output || 0
        (output_tokens / 1_000_000.0 * price).round(6)
      end

      # Calculates total cost from tokens
      #
      # @param input_tokens [Integer, nil] Number of input tokens
      # @param output_tokens [Integer, nil] Number of output tokens
      # @param response_model_id [String, nil] Model that responded
      # @return [Float, nil] Total cost in USD
      def result_total_cost(input_tokens, output_tokens, response_model_id)
        input_cost = result_input_cost(input_tokens, response_model_id)
        output_cost = result_output_cost(output_tokens, response_model_id)
        return nil unless input_cost || output_cost
        ((input_cost || 0) + (output_cost || 0)).round(6)
      end

      # Resolves model info for cost calculation
      #
      # @param response_model_id [String, nil] Model ID from response
      # @return [Object, nil] Model info or nil
      def result_model_info(response_model_id)
        lookup_id = response_model_id || model
        return nil unless lookup_id
        model_obj, _provider = RubyLLM::Models.resolve(lookup_id)
        model_obj
      rescue StandardError
        nil
      end

      # @!endgroup

      # @!group Tool Call Tracking

      # Resets accumulated tool calls for a new execution
      #
      # @return [void]
      def reset_accumulated_tool_calls!
        @accumulated_tool_calls = []
      end

      # Extracts tool calls from all assistant messages in the conversation
      #
      # RubyLLM handles tool call loops internally. After ask() completes,
      # the conversation history contains all intermediate assistant messages
      # that had tool_calls. This method extracts those tool calls.
      #
      # @param client [RubyLLM::Chat] The chat client with conversation history
      # @return [void]
      def extract_tool_calls_from_client(client)
        return unless client.respond_to?(:messages)

        client.messages.each do |message|
          next unless message.role == :assistant
          next unless message.respond_to?(:tool_calls) && message.tool_calls.present?

          message.tool_calls.each_value do |tool_call|
            @accumulated_tool_calls << serialize_tool_call(tool_call)
          end
        end
      end

      # Serializes a single tool call to a hash
      #
      # @param tool_call [Object] The tool call object
      # @return [Hash] Serialized tool call
      def serialize_tool_call(tool_call)
        if tool_call.respond_to?(:to_h)
          tool_call.to_h.transform_keys(&:to_s)
        else
          {
            "id" => tool_call.id,
            "name" => tool_call.name,
            "arguments" => tool_call.arguments
          }
        end
      end

      # @!endgroup
    end
  end
end
