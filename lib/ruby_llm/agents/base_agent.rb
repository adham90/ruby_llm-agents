# frozen_string_literal: true

require_relative "dsl"
require_relative "pipeline"
require_relative "infrastructure/cache_helper"

module RubyLLM
  module Agents
    # Base class for all agents using the middleware pipeline architecture.
    #
    # BaseAgent provides a unified foundation for building LLM-powered agents
    # with configurable middleware for caching, reliability, instrumentation,
    # budgeting, and multi-tenancy.
    #
    # @example Creating an agent
    #   class SearchAgent < RubyLLM::Agents::BaseAgent
    #     model "gpt-4o"
    #     description "Searches for relevant documents"
    #     timeout 30
    #
    #     cache_for 1.hour
    #
    #     reliability do
    #       retries max: 3, backoff: :exponential
    #       fallback_models "gpt-4o-mini"
    #     end
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
    #   SearchAgent.call(query: "red dress", dry_run: true)
    #   SearchAgent.call(query: "red dress", skip_cache: true)
    #
    class BaseAgent
      extend DSL::Base
      extend DSL::Reliability
      extend DSL::Caching
      include CacheHelper

      class << self
        # Factory method to instantiate and execute an agent
        #
        # @param kwargs [Hash] Named parameters for the agent
        # @option kwargs [Boolean] :dry_run Return prompt info without API call
        # @option kwargs [Boolean] :skip_cache Bypass caching even if enabled
        # @option kwargs [Hash, Object] :tenant Tenant context for multi-tenancy
        # @option kwargs [String, Array<String>] :with Attachments (files, URLs)
        # @yield [chunk] Yields chunks when streaming is enabled
        # @return [Object] The processed response from the agent
        def call(**kwargs, &block)
          new(**kwargs).call(&block)
        end

        # Streams agent execution, yielding chunks as they arrive
        #
        # @param kwargs [Hash] Agent parameters
        # @yield [chunk] Yields each chunk as it arrives
        # @return [Result] The final result after streaming completes
        # @raise [ArgumentError] If no block is provided
        def stream(**kwargs, &block)
          raise ArgumentError, "Block required for streaming" unless block_given?

          instance = new(**kwargs)
          instance.instance_variable_set(:@force_streaming, true)
          instance.call(&block)
        end

        # Returns the agent type for this class
        #
        # Used by middleware to determine which tracking/budget config to use.
        # Subclasses should override this method.
        #
        # @return [Symbol] The agent type (:conversation, :embedding, :image, etc.)
        def agent_type
          :conversation
        end

        # @!group Parameter DSL

        # Defines a parameter for the agent
        #
        # Creates an accessor method for the parameter that retrieves values
        # from the options hash, falling back to the default value.
        #
        # @param name [Symbol] The parameter name
        # @param required [Boolean] Whether the parameter is required
        # @param default [Object, nil] Default value if not provided
        # @param type [Class, nil] Optional type for validation
        # @return [void]
        def param(name, required: false, default: nil, type: nil)
          @params ||= {}
          @params[name] = { required: required, default: default, type: type }
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

        # @!group Streaming DSL

        # Enables or returns streaming mode for this agent
        #
        # @param value [Boolean, nil] Whether to enable streaming
        # @return [Boolean] The current streaming setting
        def streaming(value = nil)
          @streaming = value unless value.nil?
          return @streaming unless @streaming.nil?

          superclass.respond_to?(:streaming) ? superclass.streaming : default_streaming
        end

        # @!endgroup

        # @!group Tools DSL

        # Sets or returns the tools available to this agent
        #
        # @param tool_classes [Array<Class>] Tool classes to make available
        # @return [Array<Class>] The current tools
        def tools(tool_classes = nil)
          @tools = Array(tool_classes) if tool_classes
          @tools || (superclass.respond_to?(:tools) ? superclass.tools : [])
        end

        # @!endgroup

        # @!group Temperature DSL

        # Sets or returns the temperature for LLM responses
        #
        # @param value [Float, nil] Temperature value (0.0-2.0)
        # @return [Float] The current temperature setting
        def temperature(value = nil)
          @temperature = value if value
          @temperature || (superclass.respond_to?(:temperature) ? superclass.temperature : default_temperature)
        end

        # @!endgroup

        # @!group Thinking DSL

        # Configures extended thinking/reasoning for this agent
        #
        # @param effort [Symbol, nil] Thinking depth (:none, :low, :medium, :high)
        # @param budget [Integer, nil] Token budget for thinking
        # @return [Hash, nil] The current thinking configuration
        def thinking(effort: nil, budget: nil)
          if effort || budget
            @thinking_config = {}
            @thinking_config[:effort] = effort if effort
            @thinking_config[:budget] = budget if budget
          end
          thinking_config
        end

        # Returns the thinking configuration
        #
        # Falls back to global configuration default if not set at class level.
        #
        # @return [Hash, nil] The thinking configuration
        def thinking_config
          return @thinking_config if @thinking_config
          return superclass.thinking_config if superclass.respond_to?(:thinking_config) && superclass.thinking_config

          # Fall back to global configuration default
          RubyLLM::Agents.configuration.default_thinking
        rescue StandardError
          nil
        end

        # @!endgroup

        private

        def default_streaming
          RubyLLM::Agents.configuration.default_streaming
        rescue StandardError
          false
        end

        def default_temperature
          RubyLLM::Agents.configuration.default_temperature
        rescue StandardError
          0.7
        end
      end

      # @!attribute [r] model
      #   @return [String] The LLM model being used
      # @!attribute [r] temperature
      #   @return [Float] The temperature setting
      # @!attribute [r] client
      #   @return [RubyLLM::Chat] The configured RubyLLM client
      # @!attribute [r] tracked_tool_calls
      #   @return [Array<Hash>] Tool calls tracked during execution with results, timing, and status
      attr_reader :model, :temperature, :client, :tracked_tool_calls

      # Creates a new agent instance
      #
      # @param model [String] Override the class-level model setting
      # @param temperature [Float] Override the class-level temperature
      # @param options [Hash] Agent parameters defined via the param DSL
      def initialize(model: self.class.model, temperature: self.class.temperature, **options)
        @model = model
        @temperature = temperature
        @options = options
        @tracked_tool_calls = []
        @pending_tool_call = nil
        validate_required_params!
      end

      # Executes the agent through the middleware pipeline
      #
      # @yield [chunk] Yields chunks when streaming is enabled
      # @return [Object] The processed response
      def call(&block)
        return dry_run_response if @options[:dry_run]

        context = build_context(&block)
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # @!group Template Methods (override in subclasses)

      # User prompt to send to the LLM
      #
      # If a class-level `prompt` DSL is defined (string template or block),
      # it will be used. Otherwise, subclasses must implement this method.
      #
      # @return [String] The user prompt
      def user_prompt
        prompt_config = self.class.prompt_config
        return resolve_prompt_from_config(prompt_config) if prompt_config

        raise NotImplementedError, "#{self.class} must implement #user_prompt or use the prompt DSL"
      end

      # System prompt for LLM instructions
      #
      # If a class-level `system` DSL is defined, it will be used.
      # Otherwise returns nil.
      #
      # @return [String, nil] System instructions, or nil for none
      def system_prompt
        system_config = self.class.system_config
        return resolve_prompt_from_config(system_config) if system_config

        nil
      end

      # Response schema for structured output
      #
      # Delegates to the class-level schema DSL by default.
      # Override in subclass instances to customize per-instance.
      #
      # @return [RubyLLM::Schema, nil] Schema definition, or nil for free-form
      def schema
        self.class.schema
      end

      # Conversation history for multi-turn conversations
      #
      # @return [Array<Hash>] Array of messages with :role and :content keys
      def messages
        []
      end

      # Post-processes the LLM response
      #
      # @param response [RubyLLM::Message] The raw response from the LLM
      # @return [Object] The processed result
      def process_response(response)
        content = response.content
        return content unless content.is_a?(Hash)

        content.transform_keys(&:to_sym)
      end

      # @!endgroup

      # Generates the cache key for this agent invocation
      #
      # Cache keys are content-based, using a hash of the prompts and parameters.
      # This automatically invalidates caches when prompts change.
      #
      # @return [String] Cache key in format "ruby_llm_agent/ClassName/hash"
      def agent_cache_key
        ["ruby_llm_agent", self.class.name, cache_key_hash].join("/")
      end

      # Generates a hash of the cache key data
      #
      # @return [String] SHA256 hex digest of the cache key data
      def cache_key_hash
        Digest::SHA256.hexdigest(cache_key_data.to_json)
      end

      # Returns data to include in cache key generation
      #
      # @return [Hash] Data to hash for cache key
      def cache_key_data
        excludes = self.class.cache_key_excludes || %i[skip_cache dry_run with]
        base_data = @options.except(*excludes)

        # Include model and other relevant config
        base_data.merge(
          model: model,
          system_prompt: system_prompt,
          user_prompt: user_prompt
        )
      end

      # Resolves thinking configuration
      #
      # Public for testing and introspection.
      #
      # @return [Hash, nil] Thinking configuration
      def resolved_thinking
        # Check for :none effort which means disabled
        if @options.key?(:thinking)
          thinking_option = @options[:thinking]
          return nil if thinking_option == false
          return nil if thinking_option.is_a?(Hash) && thinking_option[:effort] == :none
          return thinking_option if thinking_option.is_a?(Hash)
        end

        self.class.thinking_config
      end

      protected

      # Returns the options hash
      #
      # @return [Hash] The options passed to the agent
      attr_reader :options

      private

      # Builds the pipeline context for execution
      #
      # @yield [chunk] Block for streaming
      # @return [Pipeline::Context] The context object
      def build_context(&block)
        Pipeline::Context.new(
          input: user_prompt,
          agent_class: self.class,
          agent_instance: self,
          model: model,
          tenant: resolve_tenant,
          skip_cache: @options[:skip_cache],
          stream_block: (block if streaming_enabled?),
          options: execution_options
        )
      end

      # Returns options for the LLM execution
      #
      # @return [Hash] Execution options
      def execution_options
        {
          temperature: temperature,
          system_prompt: system_prompt,
          schema: schema,
          messages: resolved_messages,
          tools: resolved_tools,
          thinking: resolved_thinking,
          attachments: @options[:with],
          timeout: self.class.timeout
        }.compact
      end

      # Resolves the tenant from options
      #
      # @return [Hash, nil] Resolved tenant info
      def resolve_tenant
        tenant_value = @options[:tenant]
        return nil unless tenant_value

        if tenant_value.is_a?(Hash)
          tenant_value
        elsif tenant_value.respond_to?(:llm_tenant_id)
          { id: tenant_value.llm_tenant_id, object: tenant_value }
        else
          raise ArgumentError, "tenant must be a Hash or respond to :llm_tenant_id"
        end
      end

      # Resolves tools for this execution
      #
      # @return [Array<Class>] Tool classes to use
      def resolved_tools
        if self.class.instance_methods(false).include?(:tools)
          tools
        else
          self.class.tools
        end
      end

      # Resolves messages for this execution
      #
      # @return [Array<Hash>] Messages to apply
      def resolved_messages
        return @options[:messages] if @options[:messages]&.any?

        messages
      end

      # Returns whether streaming is enabled
      #
      # @return [Boolean]
      def streaming_enabled?
        @force_streaming || self.class.streaming
      end

      # Returns prompt info without making an API call
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
            tools: resolved_tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
            cache_enabled: self.class.cache_enabled?,
            reliability_config: self.class.reliability_config
          },
          model_id: model,
          temperature: temperature,
          streaming: self.class.streaming
        )
      end

      # Validates that all required parameters are present
      #
      # @raise [ArgumentError] If required parameters are missing
      def validate_required_params!
        self.class.params.each do |name, config|
          value = @options[name] || @options[name.to_s]
          has_value = @options.key?(name) || @options.key?(name.to_s)

          if config[:required] && !has_value
            raise ArgumentError, "#{self.class} missing required param: #{name}"
          end

          if config[:type] && has_value && !value.nil? && !value.is_a?(config[:type])
            raise ArgumentError,
                  "#{self.class} expected #{config[:type]} for :#{name}, got #{value.class}"
          end
        end
      end

      # Resolves a prompt from DSL configuration (template string or block)
      #
      # For string templates, interpolates {placeholder} with parameter values.
      # For blocks, evaluates in the instance context.
      #
      # @param config [String, Proc] The prompt configuration
      # @return [String] The resolved prompt
      def resolve_prompt_from_config(config)
        case config
        when String
          interpolate_template(config)
        when Proc
          instance_eval(&config)
        else
          config.to_s
        end
      end

      # Interpolates {placeholder} patterns in a template string
      #
      # @param template [String] Template with {placeholder} syntax
      # @return [String] Interpolated string
      def interpolate_template(template)
        template.gsub(/\{(\w+)\}/) do
          param_name = ::Regexp.last_match(1).to_sym
          value = send(param_name) if respond_to?(param_name)
          value.to_s
        end
      end

      # Execute the core LLM call
      #
      # This is called by the Pipeline::Executor after all middleware
      # has been applied. Override this method in specialized agent types
      # (embedder, image generator, etc.) to customize the execution.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the result
      def execute(context)
        client = build_client(context)
        response = execute_llm_call(client, context)
        capture_response(response, context)
        result = build_result(process_response(response), response, context)
        context.output = result
      end

      # Builds and configures the RubyLLM client
      #
      # @param context [Pipeline::Context, nil] Optional execution context for model overrides
      # @return [RubyLLM::Chat] Configured chat client
      def build_client(context = nil)
        effective_model = context&.model || model
        client = RubyLLM.chat
                        .with_model(effective_model)
                        .with_temperature(temperature)

        client = client.with_instructions(system_prompt) if system_prompt
        client = client.with_schema(schema) if schema
        client = client.with_tools(*resolved_tools) if resolved_tools.any?
        client = setup_tool_tracking(client) if resolved_tools.any?
        client = apply_messages(client, resolved_messages) if resolved_messages.any?
        client = client.with_thinking(**resolved_thinking) if resolved_thinking

        client
      end

      # Executes the LLM call
      #
      # @param client [RubyLLM::Chat] The configured client
      # @param context [Pipeline::Context] The execution context
      # @return [RubyLLM::Message] The response
      def execute_llm_call(client, context)
        timeout = self.class.timeout
        ask_opts = {}
        ask_opts[:with] = @options[:with] if @options[:with]

        Timeout.timeout(timeout) do
          if streaming_enabled? && context.stream_block
            execute_with_streaming(client, context, ask_opts)
          else
            client.ask(user_prompt, **ask_opts)
          end
        end
      end

      # Executes with streaming enabled
      #
      # @param client [RubyLLM::Chat] The client
      # @param context [Pipeline::Context] The context
      # @param ask_opts [Hash] Options for the ask call
      # @return [RubyLLM::Message] The response
      def execute_with_streaming(client, context, ask_opts)
        first_chunk_at = nil
        started_at = context.started_at || Time.current

        response = client.ask(user_prompt, **ask_opts) do |chunk|
          first_chunk_at ||= Time.current
          context.stream_block.call(chunk)
        end

        if first_chunk_at
          context.time_to_first_token_ms = ((first_chunk_at - started_at) * 1000).to_i
        end

        response
      end

      # Captures response metadata to the context
      #
      # @param response [RubyLLM::Message] The response
      # @param context [Pipeline::Context] The context
      def capture_response(response, context)
        context.input_tokens = response.input_tokens
        context.output_tokens = response.output_tokens
        context.model_used = response.model_id || model
        # finish_reason may not be available on all RubyLLM::Message versions
        context.finish_reason = response.respond_to?(:finish_reason) ? response.finish_reason : nil

        # Store tracked tool calls in context for instrumentation
        context[:tool_calls] = @tracked_tool_calls if @tracked_tool_calls.any?

        calculate_costs(response, context) if context.input_tokens
      end

      # Calculates costs for the response
      #
      # @param response [RubyLLM::Message] The response
      # @param context [Pipeline::Context] The context
      def calculate_costs(response, context)
        model_info = find_model_info(response.model_id || model)
        return unless model_info

        input_tokens = context.input_tokens || 0
        output_tokens = context.output_tokens || 0

        input_price = model_info.pricing&.text_tokens&.input || 0
        output_price = model_info.pricing&.text_tokens&.output || 0

        context.input_cost = (input_tokens / 1_000_000.0) * input_price
        context.output_cost = (output_tokens / 1_000_000.0) * output_price
        context.total_cost = (context.input_cost + context.output_cost).round(6)
      end

      # Finds model pricing info
      #
      # @param model_id [String] The model ID
      # @return [Hash, nil] Model info with pricing
      def find_model_info(model_id)
        return nil unless defined?(RubyLLM::Models)

        RubyLLM::Models.find(model_id)
      rescue StandardError
        nil
      end

      # Builds a Result object from the response
      #
      # @param content [Object] The processed content
      # @param response [RubyLLM::Message] The raw response
      # @param context [Pipeline::Context] The context
      # @return [Result] The result object
      def build_result(content, response, context)
        Result.new(
          content: content,
          input_tokens: context.input_tokens,
          output_tokens: context.output_tokens,
          input_cost: context.input_cost,
          output_cost: context.output_cost,
          total_cost: context.total_cost,
          model_id: model,
          chosen_model_id: context.model_used || model,
          temperature: temperature,
          started_at: context.started_at,
          completed_at: context.completed_at,
          duration_ms: context.duration_ms,
          time_to_first_token_ms: context.time_to_first_token_ms,
          finish_reason: context.finish_reason,
          streaming: streaming_enabled?,
          attempts_count: context.attempts_made || 1
        )
      end

      # Extracts thinking data from a response for inclusion in Result
      #
      # @param response [Object] The response object
      # @return [Hash] Hash with thinking_text, thinking_signature, thinking_tokens
      def result_thinking_data(response)
        return {} unless response.respond_to?(:thinking) && response.thinking

        thinking = response.thinking

        data = {}
        data[:thinking_text] = extract_thinking_value(thinking, :text)
        data[:thinking_signature] = extract_thinking_value(thinking, :signature)
        data[:thinking_tokens] = extract_thinking_value(thinking, :tokens)

        data.compact
      end

      # Safely extracts thinking data without raising errors
      #
      # @param response [Object] The response object
      # @return [Hash] Hash with thinking data or empty hash
      def safe_extract_thinking_data(response)
        result_thinking_data(response)
      rescue StandardError
        {}
      end

      # Extracts a value from thinking object (supports both hash and object access)
      #
      # @param thinking [Hash, Object] The thinking object
      # @param key [Symbol] The key to extract
      # @return [Object, nil] The value or nil
      def extract_thinking_value(thinking, key)
        if thinking.respond_to?(key)
          thinking.send(key)
        elsif thinking.respond_to?(:[])
          thinking[key]
        end
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

      # Sets up tool call tracking callbacks on the client
      #
      # @param client [RubyLLM::Chat] The chat client
      # @return [RubyLLM::Chat] Client with tracking callbacks
      def setup_tool_tracking(client)
        client
          .on_tool_call { |tool_call| start_tracking_tool_call(tool_call) }
          .on_tool_result { |result| complete_tool_call_tracking(result) }
      end

      # Starts tracking a tool call
      #
      # @param tool_call [Object] The tool call object from RubyLLM
      def start_tracking_tool_call(tool_call)
        @pending_tool_call = {
          id: extract_tool_call_value(tool_call, :id),
          name: extract_tool_call_value(tool_call, :name),
          arguments: extract_tool_call_value(tool_call, :arguments) || {},
          called_at: Time.current.iso8601(3),
          started_at: Time.current
        }
      end

      # Completes tracking for the pending tool call with result
      #
      # @param result [Object] The tool result (string, hash, or object)
      def complete_tool_call_tracking(result)
        return unless @pending_tool_call

        completed_at = Time.current
        started_at = @pending_tool_call.delete(:started_at)
        duration_ms = started_at ? ((completed_at - started_at) * 1000).to_i : nil

        result_data = extract_tool_result(result)

        tracked_call = @pending_tool_call.merge(
          result: truncate_tool_result(result_data[:content]),
          status: result_data[:status],
          error_message: result_data[:error_message],
          duration_ms: duration_ms,
          completed_at: completed_at.iso8601(3)
        )

        @tracked_tool_calls << tracked_call
        @pending_tool_call = nil
      end

      # Extracts result data from various tool result formats
      #
      # @param result [Object] The tool result
      # @return [Hash] Hash with :content, :status, :error_message keys
      def extract_tool_result(result)
        content = nil
        status = "success"
        error_message = nil

        if result.is_a?(Exception)
          content = result.message
          status = "error"
          error_message = "#{result.class}: #{result.message}"
        elsif result.respond_to?(:error?) && result.error?
          content = result.respond_to?(:content) ? result.content : result.to_s
          status = "error"
          error_message = result.respond_to?(:error_message) ? result.error_message : content
        elsif result.respond_to?(:content)
          content = result.content
        elsif result.is_a?(Hash)
          content = result[:content] || result["content"] || result.to_json
          if result[:error] || result["error"]
            status = "error"
            error_message = result[:error] || result["error"]
          end
        else
          content = result.to_s
        end

        { content: content, status: status, error_message: error_message }
      end

      # Truncates tool result if it exceeds the configured max length
      #
      # @param result [String, Object] The result to truncate
      # @return [String] The truncated result
      def truncate_tool_result(result)
        return nil if result.nil?

        result_str = result.is_a?(String) ? result : result.to_json
        max_length = tool_result_max_length

        return result_str if result_str.length <= max_length

        result_str[0, max_length - 15] + "... [truncated]"
      end

      # Returns the configured max length for tool results
      #
      # @return [Integer] Max length
      def tool_result_max_length
        RubyLLM::Agents.configuration.tool_result_max_length || 10_000
      rescue StandardError
        10_000
      end

      # Extracts a value from a tool call object (supports both hash and object access)
      #
      # @param tool_call [Hash, Object] The tool call
      # @param key [Symbol] The key to extract
      # @return [Object, nil] The value or nil
      def extract_tool_call_value(tool_call, key)
        if tool_call.respond_to?(key)
          tool_call.send(key)
        elsif tool_call.respond_to?(:[])
          tool_call[key] || tool_call[key.to_s]
        end
      end
    end
  end
end
