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
        # @return [Object] The processed response from the agent
        #
        # @example Basic usage
        #   SearchAgent.call(query: "red dress")
        #
        # @example Debug mode
        #   SearchAgent.call(query: "red dress", dry_run: true)
        def call(*args, **kwargs)
          new(*args, **kwargs).call
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
      attr_reader :model, :temperature, :client

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
        validate_required_params!
        @client = build_client
      end

      # Executes the agent and returns the processed response
      #
      # Handles caching, dry-run mode, and delegates to uncached_call
      # for actual LLM execution.
      #
      # @return [Object] The processed LLM response
      def call
        return dry_run_response if @options[:dry_run]
        return uncached_call if @options[:skip_cache] || !self.class.cache_enabled?

        cache_store.fetch(cache_key, expires_in: self.class.cache_ttl) do
          uncached_call
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

      # Returns prompt info without making an API call (debug mode)
      #
      # @return [Hash] Agent configuration and prompt info
      def dry_run_response
        {
          dry_run: true,
          agent: self.class.name,
          model: model,
          temperature: temperature,
          timeout: self.class.timeout,
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          schema: schema&.class&.name
        }
      end

      private

      # Executes the agent without caching
      #
      # Wraps execution in instrumentation and timeout handling.
      #
      # @return [Object] The processed response
      def uncached_call
        instrument_execution do
          Timeout.timeout(self.class.timeout) do
            response = client.ask(user_prompt)
            process_response(capture_response(response))
          end
        end
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
        @options.except(:skip_cache, :dry_run)
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
