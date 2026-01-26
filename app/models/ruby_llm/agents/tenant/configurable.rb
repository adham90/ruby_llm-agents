# frozen_string_literal: true

require "active_support/concern"

module RubyLLM
  module Agents
    class Tenant
      # Manages API configuration for a tenant.
      #
      # Links to the ApiConfiguration model to provide per-tenant API keys
      # and settings. Supports inheritance from global configuration when
      # tenant-specific settings are not defined.
      #
      # @example Accessing tenant API keys
      #   tenant = Tenant.for("acme_corp")
      #   tenant.api_key_for(:openai)  # => "sk-..."
      #   tenant.has_custom_api_keys?  # => true
      #
      # @example Getting effective configuration
      #   config = tenant.effective_api_configuration
      #   config.apply_to_ruby_llm!
      #
      # @see ApiConfiguration
      # @api public
      module Configurable
        extend ActiveSupport::Concern

        included do
          # Link to tenant-specific API configuration
          has_one :api_configuration,
                  -> { where(scope_type: "tenant") },
                  class_name: "RubyLLM::Agents::ApiConfiguration",
                  foreign_key: :scope_id,
                  primary_key: :tenant_id,
                  dependent: :destroy
        end

        # Get API key for a specific provider
        #
        # @param provider [Symbol] Provider name (:openai, :anthropic, :gemini, etc.)
        # @return [String, nil] The API key or nil if not configured
        #
        # @example
        #   tenant.api_key_for(:openai)     # => "sk-abc123..."
        #   tenant.api_key_for(:anthropic)  # => "sk-ant-xyz..."
        def api_key_for(provider)
          attr_name = "#{provider}_api_key"
          api_configuration&.send(attr_name) if api_configuration&.respond_to?(attr_name)
        end

        # Check if tenant has custom API keys configured
        #
        # @return [Boolean] true if tenant has an ApiConfiguration record
        def has_custom_api_keys?
          api_configuration.present?
        end

        # Get effective API configuration for this tenant
        #
        # Returns the resolved configuration that combines tenant-specific
        # settings with global defaults.
        #
        # @return [ResolvedConfig] The resolved configuration
        #
        # @example
        #   config = tenant.effective_api_configuration
        #   config.openai_api_key  # Tenant's key or global fallback
        def effective_api_configuration
          ApiConfiguration.resolve(tenant_id: tenant_id)
        end

        # Get or create the API configuration for this tenant
        #
        # @return [ApiConfiguration] The tenant's API configuration record
        def api_configuration!
          api_configuration || create_api_configuration!(
            scope_type: "tenant",
            scope_id: tenant_id
          )
        end

        # Configure API settings for this tenant
        #
        # @yield [config] Block to configure the API settings
        # @yieldparam config [ApiConfiguration] The configuration to modify
        # @return [ApiConfiguration] The saved configuration
        #
        # @example
        #   tenant.configure_api do |config|
        #     config.openai_api_key = "sk-..."
        #     config.default_model = "gpt-4o"
        #   end
        def configure_api(&block)
          config = api_configuration!
          yield(config) if block_given?
          config.save!
          config
        end

        # Check if a specific provider is configured for this tenant
        #
        # @param provider [Symbol] Provider name
        # @return [Boolean] true if the provider has an API key set
        def provider_configured?(provider)
          api_key_for(provider).present?
        end

        # Get all configured providers for this tenant
        #
        # @return [Array<Symbol>] List of configured provider symbols
        def configured_providers
          return [] unless api_configuration

          ApiConfiguration::PROVIDERS.keys.select do |provider|
            provider_configured?(provider)
          end
        end

        # Get the default model for this tenant
        #
        # @return [String, nil] The default model or nil
        def default_model
          api_configuration&.default_model
        end

        # Get the default embedding model for this tenant
        #
        # @return [String, nil] The default embedding model or nil
        def default_embedding_model
          api_configuration&.default_embedding_model
        end
      end
    end
  end
end
