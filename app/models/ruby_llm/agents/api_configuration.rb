# frozen_string_literal: true

module RubyLLM
  module Agents
    # Database-backed API configuration for LLM providers
    #
    # Stores API keys (encrypted at rest) and configuration options that can be
    # managed via the dashboard UI. Supports both global settings and per-tenant
    # overrides.
    #
    # Resolution priority: per-tenant DB > global DB > config file (RubyLLM.configure)
    #
    # @!attribute [rw] scope_type
    #   @return [String] Either 'global' or 'tenant'
    # @!attribute [rw] scope_id
    #   @return [String, nil] Tenant ID when scope_type='tenant'
    #
    # @example Setting global API keys
    #   config = ApiConfiguration.global
    #   config.update!(
    #     openai_api_key: "sk-...",
    #     anthropic_api_key: "sk-ant-..."
    #   )
    #
    # @example Setting tenant-specific configuration
    #   tenant_config = ApiConfiguration.for_tenant!("acme_corp")
    #   tenant_config.update!(
    #     anthropic_api_key: "sk-ant-tenant-specific...",
    #     default_model: "claude-sonnet-4-20250514"
    #   )
    #
    # @example Resolving configuration for a tenant
    #   resolved = ApiConfiguration.resolve(tenant_id: "acme_corp")
    #   resolved.apply_to_ruby_llm!  # Apply to RubyLLM.configuration
    #
    # @see ResolvedConfig
    # @api public
    class ApiConfiguration < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_api_configurations"

      # Valid scope types
      SCOPE_TYPES = %w[global tenant].freeze

      # All API key attributes that should be encrypted
      API_KEY_ATTRIBUTES = %i[
        openai_api_key
        anthropic_api_key
        gemini_api_key
        deepseek_api_key
        mistral_api_key
        perplexity_api_key
        openrouter_api_key
        gpustack_api_key
        xai_api_key
        ollama_api_key
        bedrock_api_key
        bedrock_secret_key
        bedrock_session_token
        vertexai_credentials
      ].freeze

      # All endpoint attributes
      ENDPOINT_ATTRIBUTES = %i[
        openai_api_base
        gemini_api_base
        ollama_api_base
        gpustack_api_base
        xai_api_base
      ].freeze

      # All default model attributes
      MODEL_ATTRIBUTES = %i[
        default_model
        default_embedding_model
        default_image_model
        default_moderation_model
      ].freeze

      # Connection settings attributes
      CONNECTION_ATTRIBUTES = %i[
        request_timeout
        max_retries
        retry_interval
        retry_backoff_factor
        retry_interval_randomness
        http_proxy
      ].freeze

      # All configurable attributes (excluding API keys)
      NON_KEY_ATTRIBUTES = (
        ENDPOINT_ATTRIBUTES +
        MODEL_ATTRIBUTES +
        CONNECTION_ATTRIBUTES +
        %i[
          openai_organization_id
          openai_project_id
          bedrock_region
          vertexai_project_id
          vertexai_location
        ]
      ).freeze

      # Encrypt all API keys using Rails encrypted attributes
      # Requires Rails encryption to be configured (rails credentials:edit)
      API_KEY_ATTRIBUTES.each do |key_attr|
        encrypts key_attr, deterministic: false
      end

      # Validations
      validates :scope_type, presence: true, inclusion: { in: SCOPE_TYPES }
      validates :scope_id, uniqueness: { scope: :scope_type }, allow_nil: true
      validate :validate_scope_consistency

      # Scopes
      scope :global_config, -> { where(scope_type: "global", scope_id: nil) }
      scope :for_scope, ->(type, id) { where(scope_type: type, scope_id: id) }
      scope :tenant_configs, -> { where(scope_type: "tenant") }

      # Provider configuration mappings for display
      PROVIDERS = {
        openai: {
          name: "OpenAI",
          key_attr: :openai_api_key,
          base_attr: :openai_api_base,
          extra_attrs: [:openai_organization_id, :openai_project_id],
          capabilities: ["Chat", "Embeddings", "Images", "Moderation"]
        },
        anthropic: {
          name: "Anthropic",
          key_attr: :anthropic_api_key,
          capabilities: ["Chat"]
        },
        gemini: {
          name: "Google Gemini",
          key_attr: :gemini_api_key,
          base_attr: :gemini_api_base,
          capabilities: ["Chat", "Embeddings", "Images"]
        },
        deepseek: {
          name: "DeepSeek",
          key_attr: :deepseek_api_key,
          capabilities: ["Chat"]
        },
        mistral: {
          name: "Mistral",
          key_attr: :mistral_api_key,
          capabilities: ["Chat", "Embeddings"]
        },
        perplexity: {
          name: "Perplexity",
          key_attr: :perplexity_api_key,
          capabilities: ["Chat"]
        },
        openrouter: {
          name: "OpenRouter",
          key_attr: :openrouter_api_key,
          capabilities: ["Chat"]
        },
        gpustack: {
          name: "GPUStack",
          key_attr: :gpustack_api_key,
          base_attr: :gpustack_api_base,
          capabilities: ["Chat"]
        },
        xai: {
          name: "xAI",
          key_attr: :xai_api_key,
          base_attr: :xai_api_base,
          capabilities: ["Chat"]
        },
        ollama: {
          name: "Ollama",
          key_attr: :ollama_api_key,
          base_attr: :ollama_api_base,
          capabilities: ["Chat", "Embeddings"]
        },
        bedrock: {
          name: "AWS Bedrock",
          key_attr: :bedrock_api_key,
          extra_attrs: [:bedrock_secret_key, :bedrock_session_token, :bedrock_region],
          capabilities: ["Chat", "Embeddings"]
        },
        vertexai: {
          name: "Google Vertex AI",
          key_attr: :vertexai_credentials,
          extra_attrs: [:vertexai_project_id, :vertexai_location],
          capabilities: ["Chat", "Embeddings"]
        }
      }.freeze

      class << self
        # Finds or creates the global configuration
        #
        # @return [ApiConfiguration] The global configuration record
        def global
          global_config.first_or_create!
        end

        # Finds a tenant-specific configuration
        #
        # @param tenant_id [String] The tenant identifier
        # @return [ApiConfiguration, nil] The tenant configuration or nil
        def for_tenant(tenant_id)
          return nil if tenant_id.blank?

          for_scope("tenant", tenant_id).first
        end

        # Finds or creates a tenant-specific configuration
        #
        # @param tenant_id [String] The tenant identifier
        # @return [ApiConfiguration] The tenant configuration record
        def for_tenant!(tenant_id)
          raise ArgumentError, "tenant_id cannot be blank" if tenant_id.blank?

          for_scope("tenant", tenant_id).first_or_create!(
            scope_type: "tenant",
            scope_id: tenant_id
          )
        end

        # Resolves the effective configuration for a given tenant
        #
        # Creates a ResolvedConfig that combines tenant config > global DB > RubyLLM config
        #
        # @param tenant_id [String, nil] Optional tenant identifier
        # @return [ResolvedConfig] The resolved configuration
        def resolve(tenant_id: nil)
          tenant_config = tenant_id.present? ? for_tenant(tenant_id) : nil
          global = global_config.first

          RubyLLM::Agents::ResolvedConfig.new(
            tenant_config: tenant_config,
            global_config: global,
            ruby_llm_config: ruby_llm_current_config
          )
        end

        # Attempts to get the current RubyLLM configuration object
        #
        # RubyLLM doesn't expose a .configuration accessor, so we try
        # to access it via the internal config object if available.
        #
        # @return [Object, nil] The RubyLLM config object or nil
        def ruby_llm_current_config
          return nil unless defined?(::RubyLLM)

          # RubyLLM stores config in an internal object
          # We'll return nil since we can't access it directly
          # The database configuration takes priority anyway
          nil
        rescue StandardError
          nil
        end

        # Checks if the table exists (for graceful degradation)
        #
        # @return [Boolean]
        def table_exists?
          connection.table_exists?(table_name)
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
          false
        end
      end

      # Checks if a specific attribute has a value set
      #
      # @param attr_name [Symbol, String] The attribute name
      # @return [Boolean]
      def has_value?(attr_name)
        value = send(attr_name)
        value.present?
      rescue NoMethodError
        false
      end

      # Returns a masked version of an API key for display
      #
      # @param attr_name [Symbol, String] The API key attribute name
      # @return [String, nil] Masked key like "sk-ab****wxyz" or nil
      def masked_key(attr_name)
        value = send(attr_name)
        return nil if value.blank?

        mask_string(value)
      end

      # Returns the source of this configuration
      #
      # @return [String] "global" or "tenant:ID"
      def source_label
        scope_type == "global" ? "Global" : "Tenant: #{scope_id}"
      end

      # Converts this configuration to a hash suitable for RubyLLM
      #
      # @return [Hash] Configuration hash with non-nil values
      def to_ruby_llm_config
        {}.tap do |config|
          # API keys
          config[:openai_api_key] = openai_api_key if openai_api_key.present?
          config[:anthropic_api_key] = anthropic_api_key if anthropic_api_key.present?
          config[:gemini_api_key] = gemini_api_key if gemini_api_key.present?
          config[:deepseek_api_key] = deepseek_api_key if deepseek_api_key.present?
          config[:mistral_api_key] = mistral_api_key if mistral_api_key.present?
          config[:perplexity_api_key] = perplexity_api_key if perplexity_api_key.present?
          config[:openrouter_api_key] = openrouter_api_key if openrouter_api_key.present?
          config[:gpustack_api_key] = gpustack_api_key if gpustack_api_key.present?
          config[:xai_api_key] = xai_api_key if xai_api_key.present?
          config[:ollama_api_key] = ollama_api_key if ollama_api_key.present?

          # Bedrock
          config[:bedrock_api_key] = bedrock_api_key if bedrock_api_key.present?
          config[:bedrock_secret_key] = bedrock_secret_key if bedrock_secret_key.present?
          config[:bedrock_session_token] = bedrock_session_token if bedrock_session_token.present?
          config[:bedrock_region] = bedrock_region if bedrock_region.present?

          # Vertex AI
          config[:vertexai_credentials] = vertexai_credentials if vertexai_credentials.present?
          config[:vertexai_project_id] = vertexai_project_id if vertexai_project_id.present?
          config[:vertexai_location] = vertexai_location if vertexai_location.present?

          # Endpoints
          config[:openai_api_base] = openai_api_base if openai_api_base.present?
          config[:gemini_api_base] = gemini_api_base if gemini_api_base.present?
          config[:ollama_api_base] = ollama_api_base if ollama_api_base.present?
          config[:gpustack_api_base] = gpustack_api_base if gpustack_api_base.present?
          config[:xai_api_base] = xai_api_base if xai_api_base.present?

          # OpenAI options
          config[:openai_organization_id] = openai_organization_id if openai_organization_id.present?
          config[:openai_project_id] = openai_project_id if openai_project_id.present?

          # Default models
          config[:default_model] = default_model if default_model.present?
          config[:default_embedding_model] = default_embedding_model if default_embedding_model.present?
          config[:default_image_model] = default_image_model if default_image_model.present?
          config[:default_moderation_model] = default_moderation_model if default_moderation_model.present?

          # Connection settings
          config[:request_timeout] = request_timeout if request_timeout.present?
          config[:max_retries] = max_retries if max_retries.present?
          config[:retry_interval] = retry_interval if retry_interval.present?
          config[:retry_backoff_factor] = retry_backoff_factor if retry_backoff_factor.present?
          config[:retry_interval_randomness] = retry_interval_randomness if retry_interval_randomness.present?
          config[:http_proxy] = http_proxy if http_proxy.present?
        end
      end

      # Returns provider status information for display
      #
      # @return [Array<Hash>] Array of provider status hashes
      def provider_statuses
        PROVIDERS.map do |key, info|
          key_value = send(info[:key_attr])
          {
            key: key,
            name: info[:name],
            configured: key_value.present?,
            masked_key: key_value.present? ? mask_string(key_value) : nil,
            capabilities: info[:capabilities],
            has_base_url: info[:base_attr].present? && send(info[:base_attr]).present?
          }
        end
      end

      private

      # Validates scope consistency
      def validate_scope_consistency
        if scope_type == "global" && scope_id.present?
          errors.add(:scope_id, "must be nil for global scope")
        elsif scope_type == "tenant" && scope_id.blank?
          errors.add(:scope_id, "must be present for tenant scope")
        end
      end

      # Masks a string for display (shows first 2 and last 4 chars)
      #
      # @param value [String] The string to mask
      # @return [String] Masked string
      def mask_string(value)
        return nil if value.blank?
        return "****" if value.length <= 8

        "#{value[0..1]}****#{value[-4..]}"
      end
    end
  end
end
