# frozen_string_literal: true

# RubyLLM::Agents::Base - Base class for LLM-powered agents
#
# == Creating an Agent
#
#   class SearchAgent < ApplicationAgent
#     model "gemini-2.0-flash"
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
#       query
#     end
#
#     def schema
#       @schema ||= RubyLLM::Schema.create do
#         string :result
#       end
#     end
#   end
#
# == Calling an Agent
#
#   SearchAgent.call(query: "red dress")
#   SearchAgent.call(query: "red dress", dry_run: true)    # Debug prompts
#   SearchAgent.call(query: "red dress", skip_cache: true) # Bypass cache
#
# == Configuration DSL
#
#   model "gemini-2.0-flash"  # LLM model (default from config)
#   temperature 0.0           # Randomness 0.0-1.0 (default from config)
#   version "1.0"             # Version for cache invalidation
#   timeout 30                # Seconds before timeout (default from config)
#   cache 1.hour              # Enable caching with TTL (default: disabled)
#
# == Parameter DSL
#
#   param :name                     # Optional parameter
#   param :query, required: true    # Required - raises ArgumentError if missing
#   param :limit, default: 10       # Optional with default value
#
# == Template Methods (override in subclasses)
#
#   user_prompt   - Required. The prompt sent to the LLM.
#   system_prompt - Optional. System instructions for the LLM.
#   schema        - Optional. RubyLLM::Schema for structured output.
#   process_response(response) - Optional. Post-process the LLM response.
#   cache_key_data - Optional. Override to customize cache key generation.
#
module RubyLLM
  module Agents
    class Base
      include Instrumentation

      # Default constants (can be overridden by configuration)
      VERSION     = "1.0".freeze
      CACHE_TTL   = 1.hour

      # ==========================================================================
      # Class Methods (DSL)
      # ==========================================================================

      class << self
        # Factory method - instantiates and calls the agent
        def call(*args, **kwargs)
          new(*args, **kwargs).call
        end

        # ------------------------------------------------------------------------
        # Configuration DSL
        # ------------------------------------------------------------------------

        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_model)
        end

        def temperature(value = nil)
          @temperature = value if value
          @temperature || inherited_or_default(:temperature, RubyLLM::Agents.configuration.default_temperature)
        end

        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, VERSION)
        end

        def timeout(value = nil)
          @timeout = value if value
          @timeout || inherited_or_default(:timeout, RubyLLM::Agents.configuration.default_timeout)
        end

        # ------------------------------------------------------------------------
        # Parameter DSL
        # ------------------------------------------------------------------------

        def param(name, required: false, default: nil)
          @params ||= {}
          @params[name] = { required: required, default: default }
          define_method(name) do
            @options[name] || @options[name.to_s] || self.class.params.dig(name, :default)
          end
        end

        def params
          parent = superclass.respond_to?(:params) ? superclass.params : {}
          parent.merge(@params || {})
        end

        # ------------------------------------------------------------------------
        # Caching DSL
        # ------------------------------------------------------------------------

        def cache(ttl = CACHE_TTL)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        def cache_enabled?
          @cache_enabled || false
        end

        def cache_ttl
          @cache_ttl || CACHE_TTL
        end

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end
      end

      # ==========================================================================
      # Instance Methods
      # ==========================================================================

      attr_reader :model, :temperature, :client

      def initialize(model: self.class.model, temperature: self.class.temperature, **options)
        @model = model
        @temperature = temperature
        @options = options
        validate_required_params!
        @client = build_client
      end

      # Main entry point
      def call
        return dry_run_response if @options[:dry_run]
        return uncached_call if @options[:skip_cache] || !self.class.cache_enabled?

        cache_store.fetch(cache_key, expires_in: self.class.cache_ttl) do
          uncached_call
        end
      end

      # --------------------------------------------------------------------------
      # Template Methods (override in subclasses)
      # --------------------------------------------------------------------------

      def user_prompt
        raise NotImplementedError, "#{self.class} must implement #user_prompt"
      end

      def system_prompt
        nil
      end

      def schema
        nil
      end

      def process_response(response)
        content = response.content
        return content unless content.is_a?(Hash)
        content.transform_keys(&:to_sym)
      end

      # Debug mode - returns prompt info without API call
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

      # ==========================================================================
      # Private Methods
      # ==========================================================================

      private

      def uncached_call
        instrument_execution do
          Timeout.timeout(self.class.timeout) do
            response = client.ask(user_prompt)
            process_response(capture_response(response))
          end
        end
      end

      # --------------------------------------------------------------------------
      # Caching
      # --------------------------------------------------------------------------

      def cache_store
        RubyLLM::Agents.configuration.cache_store
      end

      def cache_key
        ["ruby_llm_agent", self.class.name, self.class.version, cache_key_hash].join("/")
      end

      def cache_key_hash
        Digest::SHA256.hexdigest(cache_key_data.to_json)
      end

      # Override to customize what's included in cache key
      def cache_key_data
        @options.except(:skip_cache, :dry_run)
      end

      # --------------------------------------------------------------------------
      # Validation
      # --------------------------------------------------------------------------

      def validate_required_params!
        required = self.class.params.select { |_, v| v[:required] }.keys
        missing = required.reject { |p| @options.key?(p) || @options.key?(p.to_s) }
        raise ArgumentError, "#{self.class} missing required params: #{missing.join(', ')}" if missing.any?
      end

      # --------------------------------------------------------------------------
      # Client Building
      # --------------------------------------------------------------------------

      def build_client
        client = RubyLLM.chat
          .with_model(model)
          .with_temperature(temperature)
        client = client.with_instructions(system_prompt) if system_prompt
        client = client.with_schema(schema) if schema
        client
      end

      # Helper for subclasses that need conversation history
      def build_client_with_messages(messages)
        messages.reduce(build_client) do |client, message|
          client.with_message(message[:role], message[:content])
        end
      end
    end
  end
end
