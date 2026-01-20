# frozen_string_literal: true

module RubyLLM
  module Agents
    # Resolves API configuration with priority chain
    #
    # Resolution order:
    # 1. Tenant-specific database config (if tenant_id provided)
    # 2. Global database config
    # 3. RubyLLM.configuration (set via initializer or environment)
    #
    # This class provides a unified interface for accessing configuration
    # values regardless of their source, and can apply the resolved
    # configuration to RubyLLM.
    #
    # @example Basic resolution
    #   resolved = ResolvedConfig.new(
    #     tenant_config: ApiConfiguration.for_tenant("acme"),
    #     global_config: ApiConfiguration.global,
    #     ruby_llm_config: RubyLLM.configuration
    #   )
    #
    #   resolved.openai_api_key     # => Returns from highest priority source
    #   resolved.source_for(:openai_api_key)  # => "tenant:acme"
    #
    # @example Applying to RubyLLM
    #   resolved.apply_to_ruby_llm!  # Applies all resolved values
    #
    # @see ApiConfiguration
    # @api public
    class ResolvedConfig
      # Returns all resolvable attributes (API keys + settings)
      # Lazy-loaded to avoid circular dependency with ApiConfiguration
      #
      # @return [Array<Symbol>]
      def self.resolvable_attributes
        @resolvable_attributes ||= (
          ApiConfiguration::API_KEY_ATTRIBUTES +
          ApiConfiguration::NON_KEY_ATTRIBUTES
        ).freeze
      end

      # @return [ApiConfiguration, nil] Tenant-specific configuration
      attr_reader :tenant_config

      # @return [ApiConfiguration, nil] Global database configuration
      attr_reader :global_config

      # @return [Object] RubyLLM configuration object
      attr_reader :ruby_llm_config

      # Creates a new resolved configuration
      #
      # @param tenant_config [ApiConfiguration, nil] Tenant-specific config
      # @param global_config [ApiConfiguration, nil] Global database config
      # @param ruby_llm_config [Object] RubyLLM.configuration
      def initialize(tenant_config:, global_config:, ruby_llm_config:)
        @tenant_config = tenant_config
        @global_config = global_config
        @ruby_llm_config = ruby_llm_config
        @resolved_cache = {}
      end

      # Resolves a specific attribute value using the priority chain
      #
      # @param attr_name [Symbol, String] The attribute name
      # @return [Object, nil] The resolved value
      def resolve(attr_name)
        attr_sym = attr_name.to_sym
        return @resolved_cache[attr_sym] if @resolved_cache.key?(attr_sym)

        @resolved_cache[attr_sym] = resolve_attribute(attr_sym)
      end

      # Returns the source of a resolved attribute value
      #
      # @param attr_name [Symbol, String] The attribute name
      # @return [String] Source label: "tenant:ID", "global_db", "ruby_llm_config", or "not_set"
      def source_for(attr_name)
        attr_sym = attr_name.to_sym

        # Check tenant config first (if present and inherits or has value)
        if tenant_config&.has_value?(attr_sym)
          return "tenant:#{tenant_config.scope_id}"
        end

        # Check global DB config (only if tenant inherits or no tenant)
        if should_check_global?(attr_sym) && global_config&.has_value?(attr_sym)
          return "global_db"
        end

        # Check RubyLLM config
        if ruby_llm_value_present?(attr_sym)
          return "ruby_llm_config"
        end

        "not_set"
      end

      # Returns all resolved values as a hash
      #
      # @return [Hash] All resolved configuration values
      def to_hash
        self.class.resolvable_attributes.each_with_object({}) do |attr, hash|
          value = resolve(attr)
          hash[attr] = value if value.present?
        end
      end

      # Returns a hash suitable for RubyLLM configuration
      #
      # Only includes values that differ from or override the current
      # RubyLLM configuration.
      #
      # @return [Hash] Configuration hash for RubyLLM
      def to_ruby_llm_options
        to_hash.slice(*ruby_llm_configurable_attributes)
      end

      # Applies the resolved configuration to RubyLLM
      #
      # This temporarily overrides RubyLLM.configuration with the
      # resolved values. Useful for per-request configuration.
      #
      # @return [void]
      def apply_to_ruby_llm!
        options = to_ruby_llm_options
        return if options.empty?

        RubyLLM.configure do |config|
          options.each do |key, value|
            setter = "#{key}="
            config.public_send(setter, value) if config.respond_to?(setter)
          end
        end
      end

      # Dynamic accessor for resolvable attributes
      # Uses method_missing to provide accessors without eager loading constants
      #
      # @param method_name [Symbol] The method being called
      # @param args [Array] Method arguments
      # @return [Object] The resolved value for the attribute
      def method_missing(method_name, *args)
        if self.class.resolvable_attributes.include?(method_name)
          resolve(method_name)
        else
          super
        end
      end

      # Indicates which dynamic methods are supported
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] True if the method is a resolvable attribute
      def respond_to_missing?(method_name, include_private = false)
        self.class.resolvable_attributes.include?(method_name) || super
      end

      # Returns provider status with source information
      #
      # @return [Array<Hash>] Provider status with source info
      def provider_statuses_with_source
        ApiConfiguration::PROVIDERS.map do |key, info|
          key_attr = info[:key_attr]
          value = resolve(key_attr)

          {
            key: key,
            name: info[:name],
            configured: value.present?,
            masked_key: value.present? ? mask_string(value) : nil,
            source: source_for(key_attr),
            capabilities: info[:capabilities]
          }
        end
      end

      # Checks if any database configuration exists
      #
      # @return [Boolean]
      def has_db_config?
        tenant_config.present? || global_config.present?
      end

      # Returns summary of configuration sources
      #
      # @return [Hash] Summary with counts per source
      def source_summary
        summary = Hash.new(0)

        self.class.resolvable_attributes.each do |attr|
          source = source_for(attr)
          summary[source] += 1 if resolve(attr).present?
        end

        summary
      end

      # Public method to get raw RubyLLM config value for an attribute
      # This returns the value from RubyLLM.configuration (initializer/ENV)
      # regardless of any database overrides.
      #
      # @param attr_name [Symbol, String] The attribute name
      # @return [Object, nil] The RubyLLM config value
      def ruby_llm_value_for(attr_name)
        ruby_llm_value(attr_name.to_sym)
      end

      # Masks a string for display (public wrapper)
      #
      # @param value [String] The string to mask
      # @return [String] Masked string
      def mask_string(value)
        return nil if value.blank?
        return "****" if value.length <= 8

        "#{value[0..1]}****#{value[-4..]}"
      end

      private

      # Resolves a single attribute using the priority chain
      #
      # @param attr_sym [Symbol] The attribute name
      # @return [Object, nil] The resolved value
      def resolve_attribute(attr_sym)
        # 1. Check tenant config
        if tenant_config&.has_value?(attr_sym)
          return tenant_config.send(attr_sym)
        end

        # 2. Check global DB config (if tenant allows inheritance or no tenant)
        if should_check_global?(attr_sym)
          if global_config&.has_value?(attr_sym)
            return global_config.send(attr_sym)
          end
        end

        # 3. Fall back to RubyLLM config
        ruby_llm_value(attr_sym)
      end

      # Determines if we should check global config
      #
      # @param attr_sym [Symbol] The attribute name
      # @return [Boolean]
      def should_check_global?(attr_sym)
        return true unless tenant_config

        # If tenant has inherit_global_defaults enabled, check global
        tenant_config.inherit_global_defaults != false
      end

      # Gets a value from RubyLLM configuration
      #
      # @param attr_sym [Symbol] The attribute name
      # @return [Object, nil]
      def ruby_llm_value(attr_sym)
        return nil unless ruby_llm_config

        # Map our attribute names to RubyLLM config method names
        method_name = ruby_llm_config_mapping(attr_sym)
        return nil unless method_name

        if ruby_llm_config.respond_to?(method_name)
          ruby_llm_config.send(method_name)
        end
      rescue StandardError
        nil
      end

      # Checks if a RubyLLM config value is present
      #
      # @param attr_sym [Symbol] The attribute name
      # @return [Boolean]
      def ruby_llm_value_present?(attr_sym)
        value = ruby_llm_value(attr_sym)
        value.present?
      end

      # Maps our attribute names to RubyLLM configuration method names
      #
      # @param attr_sym [Symbol] Our attribute name
      # @return [Symbol, nil] RubyLLM config method name
      def ruby_llm_config_mapping(attr_sym)
        # Most attributes map directly
        mapping = {
          openai_api_key: :openai_api_key,
          anthropic_api_key: :anthropic_api_key,
          gemini_api_key: :gemini_api_key,
          deepseek_api_key: :deepseek_api_key,
          mistral_api_key: :mistral_api_key,
          perplexity_api_key: :perplexity_api_key,
          openrouter_api_key: :openrouter_api_key,
          gpustack_api_key: :gpustack_api_key,
          xai_api_key: :xai_api_key,
          ollama_api_key: :ollama_api_key,
          bedrock_api_key: :bedrock_api_key,
          bedrock_secret_key: :bedrock_secret_key,
          bedrock_session_token: :bedrock_session_token,
          bedrock_region: :bedrock_region,
          vertexai_credentials: :vertexai_credentials,
          vertexai_project_id: :vertexai_project_id,
          vertexai_location: :vertexai_location,
          openai_api_base: :openai_api_base,
          gemini_api_base: :gemini_api_base,
          ollama_api_base: :ollama_api_base,
          gpustack_api_base: :gpustack_api_base,
          xai_api_base: :xai_api_base,
          openai_organization_id: :openai_organization_id,
          openai_project_id: :openai_project_id,
          default_model: :default_model,
          default_embedding_model: :default_embedding_model,
          default_image_model: :default_image_model,
          default_moderation_model: :default_moderation_model,
          request_timeout: :request_timeout,
          max_retries: :max_retries,
          retry_interval: :retry_interval,
          retry_backoff_factor: :retry_backoff_factor,
          retry_interval_randomness: :retry_interval_randomness,
          http_proxy: :http_proxy
        }

        mapping[attr_sym]
      end

      # Returns attributes that can be set on RubyLLM configuration
      #
      # @return [Array<Symbol>]
      def ruby_llm_configurable_attributes
        ApiConfiguration::API_KEY_ATTRIBUTES +
          ApiConfiguration::ENDPOINT_ATTRIBUTES +
          ApiConfiguration::MODEL_ATTRIBUTES +
          ApiConfiguration::CONNECTION_ATTRIBUTES +
          %i[
            openai_organization_id
            openai_project_id
            bedrock_region
            vertexai_project_id
            vertexai_location
          ]
      end

    end
  end
end
