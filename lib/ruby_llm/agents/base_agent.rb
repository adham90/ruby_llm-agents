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
      extend DSL::Queryable
      extend DSL::Knowledge
      extend DSL::Attachments
      include DSL::Knowledge::InstanceMethods
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

        # Executes the agent with a freeform message as the user prompt
        #
        # Designed for conversational agents that define a persona (system +
        # optional assistant prefill) but accept freeform input at runtime.
        # Also works on template agents as an escape hatch to bypass the
        # user template.
        #
        # @param message [String] The user message to send
        # @param with [String, Array<String>, nil] Attachments (files, URLs)
        # @param kwargs [Hash] Additional options (model:, temperature:, etc.)
        # @yield [chunk] Yields chunks when streaming
        # @return [Result] The processed response
        #
        # @example Basic usage
        #   RubyExpert.ask("What is metaprogramming?")
        #
        # @example With streaming
        #   RubyExpert.ask("Explain closures") { |chunk| print chunk.content }
        #
        # @example With attachments
        #   RubyExpert.ask("What's in this image?", with: "photo.jpg")
        #
        def ask(message, with: nil, **kwargs, &block)
          opts = kwargs.merge(_ask_message: message)
          opts[:with] = with if with

          if block
            stream(**opts, &block)
          else
            call(**opts)
          end
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

        # Declares previous class names for this agent
        #
        # When an agent is renamed, old execution records still reference the
        # previous class name. Declaring aliases allows scopes, analytics, and
        # budget checks to automatically include records from all previous names.
        #
        # @param names [Array<String>] Previous class names
        # @return [Array<String>] All declared aliases
        #
        # @example
        #   class SupportBot < ApplicationAgent
        #     aliases "CustomerSupportAgent", "HelpDeskAgent"
        #   end
        def aliases(*names)
          if names.any?
            @agent_aliases = names.map(&:to_s)
          end
          @agent_aliases || []
        end

        # Returns all known names for this agent (current + aliases)
        #
        # @return [Array<String>] Current name followed by any aliases
        def all_agent_names
          [name, *aliases].compact.uniq
        end

        # Returns a summary of the agent's DSL configuration
        #
        # Useful for debugging in the Rails console to see how an agent
        # is configured without instantiating it.
        #
        # @return [Hash] Agent configuration summary
        # @example
        #   MyAgent.config_summary
        def config_summary
          {
            agent_type: agent_type,
            model: model,
            temperature: temperature,
            timeout: timeout,
            streaming: streaming,
            system_prompt: system_config,
            user_prompt: user_config,
            assistant_prompt: assistant_config,
            description: description,
            schema: schema&.respond_to?(:name) ? schema.name : schema&.class&.name,
            tools: tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
            parameters: params.transform_values { |v| v.slice(:type, :required, :default, :desc) },
            thinking: thinking_config,
            cache_prompts: cache_prompts || nil,
            caching: caching_config,
            reliability: reliability_configured? ? reliability_config : nil
          }.compact
        end

        # @!group Custom Middleware DSL

        # Registers a custom middleware for this agent class
        #
        # @param middleware_class [Class] Must inherit from Pipeline::Middleware::Base
        # @param before [Class, nil] Insert before this built-in middleware
        # @param after [Class, nil] Insert after this built-in middleware
        # @return [void]
        def use_middleware(middleware_class, before: nil, after: nil)
          @agent_middleware ||= []
          @agent_middleware << {klass: middleware_class, before: before, after: after}
        end

        # Returns custom middleware registered on this agent (including inherited)
        #
        # @return [Array<Hash>] Middleware entries with :klass, :before, :after keys
        def agent_middleware
          @agent_middleware || (superclass.respond_to?(:agent_middleware) ? superclass.agent_middleware : []) || []
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
        # @param type [Class, nil] Optional type for validation
        # @return [void]
        def param(name, required: false, default: nil, type: nil, desc: nil, description: nil)
          @params ||= {}
          @params[name] = {required: required, default: default, type: type, desc: desc || description}
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
        # @param overridable [Boolean, nil] When true, this field can be changed from the dashboard
        # @return [Boolean] The current streaming setting
        def streaming(value = nil, overridable: nil)
          @streaming = value unless value.nil?
          register_overridable(:streaming) if overridable
          base = if @streaming.nil?
            superclass.respond_to?(:streaming) ? superclass.streaming : default_streaming
          else
            @streaming
          end

          apply_override(:streaming, base)
        end

        # @!endgroup

        # @!group Tools DSL

        # Sets or returns the tools available to this agent
        #
        # @param tool_classes [Class, Array<Class>] Tool classes to make available
        # @return [Array<Class>] The current tools
        def tools(*tool_classes)
          @tools = tool_classes.flatten if tool_classes.any?
          @tools || (superclass.respond_to?(:tools) ? superclass.tools : [])
        end

        # @!endgroup

        # @!group Temperature DSL

        # Sets or returns the temperature for LLM responses
        #
        # @param value [Float, nil] Temperature value (0.0-2.0)
        # @param overridable [Boolean, nil] When true, this field can be changed from the dashboard
        # @return [Float] The current temperature setting
        def temperature(value = nil, overridable: nil)
          @temperature = value if value
          register_overridable(:temperature) if overridable
          base = @temperature || (superclass.respond_to?(:temperature) ? superclass.temperature : default_temperature)

          apply_override(:temperature, base)
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
        rescue
          nil
        end

        # @!endgroup

        private

        def default_streaming
          RubyLLM::Agents.configuration.default_streaming
        rescue
          false
        end

        def default_temperature
          RubyLLM::Agents.configuration.default_temperature
        rescue
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
        # Merge tracker defaults (shared options like tenant) — explicit opts win
        tracker = Thread.current[:ruby_llm_agents_tracker]
        if tracker
          options = tracker.defaults.merge(options)
          @_track_request_id = tracker.request_id
          @_track_tags = tracker.tags
        end

        @ask_message = options.delete(:_ask_message)
        @parent_execution_id = options.delete(:_parent_execution_id)
        @root_execution_id = options.delete(:_root_execution_id)
        @model = model
        @temperature = temperature
        @options = options
        @tracked_tool_calls = []
        @pending_tool_call = nil
        validate_required_params! unless @ask_message
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
      # Resolution order:
      # 1. Subclass method override (standard Ruby dispatch — this method is never called)
      # 2. .ask(message) runtime message — bypasses template
      # 3. Class-level `user` / `prompt` template — interpolated with {placeholders}
      # 4. Inherited from superclass
      # 5. NotImplementedError
      #
      # @return [String] The user prompt
      def user_prompt
        return @ask_message if @ask_message

        config = self.class.user_config
        return resolve_prompt_from_config(config) if config

        raise NotImplementedError, "#{self.class} must implement #user_prompt, use the `user` DSL, or call with .ask(message)"
      end

      # System prompt for LLM instructions
      #
      # If a class-level `system` DSL is defined, it will be used.
      # Knowledge entries declared via `knows` are auto-appended.
      #
      # @return [String, nil] System instructions, or nil for none
      def system_prompt
        system_config = self.class.system_config
        base = system_config ? resolve_prompt_from_config(system_config) : nil

        knowledge = compiled_knowledge
        if knowledge.present?
          base ? "#{base}\n\n#{knowledge}" : knowledge
        else
          base
        end
      end

      # Assistant prefill to prime the model's response
      #
      # If a class-level `assistant` DSL is defined, it will be used.
      # Otherwise returns nil (no prefill).
      #
      # @return [String, nil] The assistant prefill, or nil for none
      def assistant_prompt
        config = self.class.assistant_config
        return resolve_prompt_from_config(config) if config

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

        content.deep_symbolize_keys
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
          user_prompt: user_prompt,
          assistant_prompt: assistant_prompt
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
          stream_events: @options[:stream_events] == true,
          parent_execution_id: @parent_execution_id,
          root_execution_id: @root_execution_id,
          debug: @options[:debug],
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
          assistant_prefill: assistant_prompt,
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
          {id: tenant_value.llm_tenant_id, object: tenant_value}
        else
          raise ArgumentError, "tenant must be a Hash or respond to :llm_tenant_id"
        end
      end

      # Returns the description for a tool class
      #
      # @param tool [Class] A tool class
      # @return [String] The tool's description
      def tool_description_for(tool)
        if tool.respond_to?(:description) && tool.description
          tool.description
        elsif tool.is_a?(Class) && tool < RubyLLM::Tool
          tool.new.respond_to?(:description) ? tool.new.description : tool.name.to_s
        else
          tool.name.to_s
        end
      end

      # Resolves tools for this execution
      #
      # @return [Array<Class>] Tool classes to use
      # @raise [ArgumentError] If duplicate tool names are detected
      def resolved_tools
        all_tools = if self.class.method_defined?(:tools, false)
          tools
        else
          self.class.tools
        end

        detect_duplicate_tool_names!(all_tools)
        all_tools
      end

      # Raises if two tools resolve to the same name.
      #
      # @param tools [Array] Resolved tool classes or instances
      # @raise [ArgumentError] On duplicate names
      def detect_duplicate_tool_names!(tools)
        names = tools.map { |t| tool_name_for(t) }
        duplicates = names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
        raise ArgumentError, "Duplicate tool names: #{duplicates.join(", ")}" if duplicates.any?
      end

      # Extracts a tool name from a tool class or instance.
      #
      # @param tool [Class, Object] A tool class or instance
      # @return [String] The tool name
      def tool_name_for(tool)
        return tool.tool_name if tool.respond_to?(:tool_name)

        if tool.is_a?(Class) && tool < RubyLLM::Tool
          tool.new.name
        elsif tool.is_a?(Class)
          tool.name.to_s
        elsif tool.respond_to?(:name)
          tool.name.to_s
        else
          tool.to_s
        end
      end

      # Resolves messages for this execution
      #
      # Includes conversation history and assistant prefill if defined.
      # The assistant prefill is appended as the last message so it appears
      # after the user prompt in the conversation.
      #
      # @return [Array<Hash>] Messages to apply
      def resolved_messages
        msgs = @options[:messages]&.any? ? @options[:messages] : messages
        msgs.dup
      end

      # Returns the assistant prefill message if defined
      #
      # Called after the user prompt is sent to inject the prefill.
      #
      # @return [Hash, nil] The assistant prefill message hash, or nil
      def resolved_assistant_prefill
        prefill = assistant_prompt
        return nil if prefill.nil? || (prefill.is_a?(String) && prefill.empty?)

        {role: :assistant, content: prefill}
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
            assistant_prompt: assistant_prompt,
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

      # Resolves a prompt from DSL configuration (template string)
      #
      # Interpolates {placeholder} patterns with parameter values.
      #
      # @param config [String] The prompt template
      # @return [String] The resolved prompt
      def resolve_prompt_from_config(config)
        interpolate_template(config)
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
        @context = context
        client = build_client(context)

        # Make context available to Tool instances during tool execution
        previous_context = Thread.current[:ruby_llm_agents_caller_context]
        Thread.current[:ruby_llm_agents_caller_context] = context

        response = execute_llm_call(client, context)
        capture_response(response, context)
        result = build_result(process_response(response), response, context)
        context.output = result
      rescue RubyLLM::Agents::CancelledError
        context.output = Result.new(content: nil, cancelled: true)
      rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError => e
        raise_with_setup_hint(e, context)
      rescue RubyLLM::ModelNotFoundError => e
        raise_with_model_hint(e, context)
      ensure
        Thread.current[:ruby_llm_agents_caller_context] = previous_context
      end

      # Builds and configures the RubyLLM client
      #
      # @param context [Pipeline::Context, nil] Optional execution context for model overrides
      # @return [RubyLLM::Chat] Configured chat client
      def build_client(context = nil)
        effective_model = context&.model || model
        chat_opts = {model: effective_model}

        # Use scoped RubyLLM::Context for thread-safe per-tenant API keys.
        # RubyLLM::Context#chat creates a Chat with the scoped config,
        # so we call .chat on the context instead of RubyLLM.chat.
        llm_ctx = context&.llm
        client = if llm_ctx.is_a?(RubyLLM::Context)
          llm_ctx.chat(**chat_opts)
        else
          RubyLLM.chat(**chat_opts)
        end
        client = client.with_temperature(temperature)

        use_prompt_caching = self.class.cache_prompts && anthropic_model?(effective_model)

        if system_prompt
          sys_content = if use_prompt_caching
            RubyLLM::Providers::Anthropic::Content.new(system_prompt, cache: true)
          else
            system_prompt
          end
          client = client.with_instructions(sys_content)
        end

        client = client.with_schema(schema) if schema
        client = client.with_tools(*resolved_tools) if resolved_tools.any?
        apply_tool_prompt_caching(client) if use_prompt_caching && resolved_tools.any?
        client = setup_tool_tracking(client) if resolved_tools.any?
        client = apply_messages(client, resolved_messages) if resolved_messages.any?
        client = client.with_thinking(**resolved_thinking) if resolved_thinking

        client
      end

      # Executes the LLM call
      #
      # When an assistant prefill is defined, messages are added manually
      # (user, then assistant) before calling complete, so the model
      # continues from the prefill. Otherwise, uses the standard .ask flow.
      #
      # @param client [RubyLLM::Chat] The configured client
      # @param context [Pipeline::Context] The execution context
      # @return [RubyLLM::Message] The response
      def execute_llm_call(client, context)
        timeout = self.class.timeout
        prefill = resolved_assistant_prefill

        Timeout.timeout(timeout) do
          if prefill
            execute_with_prefill(client, context, prefill)
          elsif streaming_enabled? && context.stream_block
            execute_with_streaming(client, context)
          else
            ask_opts = {}
            ask_opts[:with] = @options[:with] if @options[:with]
            client.ask(user_prompt, **ask_opts)
          end
        end
      end

      # Executes with assistant prefill
      #
      # Manually adds the user message and assistant prefill, then calls
      # complete so the model continues from the prefill text.
      #
      # @param client [RubyLLM::Chat] The client
      # @param context [Pipeline::Context] The context
      # @param prefill [Hash] The assistant prefill message ({role:, content:})
      # @return [RubyLLM::Message] The response
      def execute_with_prefill(client, context, prefill)
        # Add user message — use .ask for attachment support, then add prefill
        # We use add_message + complete instead of .ask so we can insert the
        # assistant prefill between user and completion
        client.add_message(role: :user, content: user_prompt)
        client.add_message(**prefill)

        if streaming_enabled? && context.stream_block
          first_chunk_at = nil
          started_at = context.started_at || Time.current

          response = client.complete do |chunk|
            first_chunk_at ||= Time.current
            if context.stream_events?
              context.stream_block.call(StreamEvent.new(:chunk, {content: chunk.content}))
            else
              context.stream_block.call(chunk)
            end
          end

          if first_chunk_at
            context.time_to_first_token_ms = ((first_chunk_at - started_at) * 1000).to_i
          end

          response
        else
          client.complete
        end
      end

      # Executes with streaming enabled
      #
      # @param client [RubyLLM::Chat] The client
      # @param context [Pipeline::Context] The context
      # @return [RubyLLM::Message] The response
      def execute_with_streaming(client, context)
        first_chunk_at = nil
        started_at = context.started_at || Time.current
        ask_opts = {}
        ask_opts[:with] = @options[:with] if @options[:with]

        response = client.ask(user_prompt, **ask_opts) do |chunk|
          first_chunk_at ||= Time.current
          if context.stream_events?
            context.stream_block.call(StreamEvent.new(:chunk, {content: chunk.content}))
          else
            context.stream_block.call(chunk)
          end
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

        # Capture Anthropic prompt caching metrics
        if response.respond_to?(:cached_tokens) && response.cached_tokens&.positive?
          context[:cached_tokens] = response.cached_tokens
        end
        if response.respond_to?(:cache_creation_tokens) && response.cache_creation_tokens&.positive?
          context[:cache_creation_tokens] = response.cache_creation_tokens
        end

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
      rescue
        nil
      end

      # Checks whether the given model is served by Anthropic
      #
      # Looks up the model's provider in the registry, falling back to
      # model ID pattern matching when the registry is unavailable.
      #
      # @param model_id [String] The model ID
      # @return [Boolean]
      def anthropic_model?(model_id)
        info = find_model_info(model_id)
        return info.provider.to_s == "anthropic" if info&.provider

        # Fallback: match common Anthropic model ID patterns
        model_id.to_s.match?(/\Aclaude/i)
      end

      # Adds cache_control to the last tool so Anthropic caches all tool definitions
      #
      # Uses a singleton method override on the last tool instance so the
      # cache_control is merged into the API payload by RubyLLM's
      # Tools.function_for without mutating the tool class.
      #
      # @param client [RubyLLM::Chat] The chat client with tools already added
      def apply_tool_prompt_caching(client)
        last_tool = client.tools.values.last
        return unless last_tool

        last_tool.define_singleton_method(:provider_params) do
          super().merge(cache_control: {type: "ephemeral"})
        end
      end

      # Builds a Result object from the response
      #
      # @param content [Object] The processed content
      # @param response [RubyLLM::Message] The raw response
      # @param context [Pipeline::Context] The context
      # @return [Result] The result object
      def build_result(content, response, context)
        result_opts = {
          content: content,
          agent_class_name: self.class.name,
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
          attempts_count: context.attempts_made || 1,
          execution_id: context.execution_id
        }

        # Attach pipeline trace when debug mode is enabled
        result_opts[:trace] = context.trace if context.trace_enabled? && context.trace.any?

        Result.new(**result_opts)
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
      rescue
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
          .on_tool_call do |tool_call|
            start_tracking_tool_call(tool_call)
            emit_stream_event(:tool_start, tool_call_start_data(tool_call))
          end
          .on_tool_result do |result|
            end_data = tool_call_end_data(result)
            complete_tool_call_tracking(result)
            emit_stream_event(:tool_end, end_data)
          end
      end

      # Emits a StreamEvent to the caller's stream block when stream_events is enabled
      #
      # @param type [Symbol] Event type (:chunk, :tool_start, :tool_end, :error)
      # @param data [Hash] Event-specific data
      def emit_stream_event(type, data)
        return unless @context&.stream_block && @context.stream_events?

        @context.stream_block.call(StreamEvent.new(type, data))
      end

      # Builds data hash for a tool_start event
      #
      # @param tool_call [Object] The tool call object from RubyLLM
      # @return [Hash] Event data
      def tool_call_start_data(tool_call)
        {
          tool_name: extract_tool_call_value(tool_call, :name),
          input: extract_tool_call_value(tool_call, :arguments) || {}
        }.compact
      end

      # Builds data hash for a tool_end event from the pending tool call
      #
      # @param result [Object] The tool result
      # @return [Hash] Event data
      def tool_call_end_data(result)
        return {} unless @pending_tool_call

        started_at = @pending_tool_call[:started_at]
        duration_ms = started_at ? ((Time.current - started_at) * 1000).to_i : nil
        result_data = extract_tool_result(result)

        {
          tool_name: @pending_tool_call[:name],
          status: result_data[:status],
          duration_ms: duration_ms
        }.compact
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

        {content: content, status: status, error_message: error_message}
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
      rescue
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

      # Re-raises auth errors with actionable setup guidance
      def raise_with_setup_hint(error, context)
        effective_model = context&.model || model
        provider = detect_provider(effective_model)

        hint = "#{self.class.name} failed: #{error.message}\n\n" \
               "The API key for #{provider || "your provider"} is missing or invalid.\n" \
               "Fix: Set the key in config/initializers/ruby_llm_agents.rb\n" \
               "     or run: rails ruby_llm_agents:doctor"

        raise RubyLLM::Agents::ConfigurationError, hint
      end

      # Re-raises model errors with actionable guidance
      def raise_with_model_hint(error, context)
        effective_model = context&.model || model

        hint = "#{self.class.name} failed: #{error.message}\n\n" \
               "Model '#{effective_model}' was not found.\n" \
               "Fix: Check the model name or set a default in your initializer:\n" \
               "     config.default_model = \"gpt-4o\""

        raise RubyLLM::Agents::ConfigurationError, hint
      end

      # Best-effort provider detection from model name
      def detect_provider(model_id)
        return nil unless model_id

        case model_id.to_s
        when /gpt|o[1-9]|dall-e|whisper|tts/i then "OpenAI"
        when /claude/i then "Anthropic"
        when /gemini|gemma/i then "Google (Gemini)"
        when /deepseek/i then "DeepSeek"
        when /mistral|mixtral/i then "Mistral"
        end
      end
    end
  end
end
