# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Resolves tenant context from options and applies API configuration.
        #
        # This middleware extracts tenant information from the context options,
        # sets the tenant_id, tenant_object, and tenant_config on the context,
        # and applies any tenant-specific API keys to RubyLLM.
        #
        # Supports three formats:
        # - Object with llm_tenant_id method (recommended for ActiveRecord models)
        # - Hash with :id key (simple/legacy format)
        # - nil (no tenant - single-tenant mode)
        #
        # API keys are configured via:
        # - RubyLLM.configuration (set via initializer or environment variables)
        # - Tenant object's llm_api_keys method (for per-tenant overrides)
        #
        # @example With ActiveRecord model
        #   # Model uses llm_tenant DSL
        #   class Organization < ApplicationRecord
        #     include RubyLLM::Agents::LLMTenant
        #     llm_tenant id: :slug, api_keys: { openai: :openai_key }
        #   end
        #
        #   # Pass tenant to agent
        #   MyAgent.call(query: "test", tenant: organization)
        #
        # @example With hash
        #   MyAgent.call(query: "test", tenant: { id: "org_123" })
        #
        # @example Without tenant
        #   MyAgent.call(query: "test")  # Single-tenant mode
        #
        class Tenant < Base
          # Process tenant resolution and API key application
          #
          # @param context [Context] The execution context
          # @return [Context] The context with tenant fields populated
          def call(context)
            resolve_tenant!(context)
            apply_api_configuration!(context)
            @app.call(context)
          end

          private

          # Resolves tenant context from options
          #
          # @param context [Context] The execution context
          # @raise [ArgumentError] If tenant format is invalid
          def resolve_tenant!(context)
            tenant_value = context.options[:tenant]

            case tenant_value
            when nil
              # No tenant - single-tenant mode
              context.tenant_id = nil
              context.tenant_object = nil
              context.tenant_config = nil

            when Hash
              # Hash format: { id: "tenant_id", object: tenant, ... }
              # The :object key is set by BaseAgent.resolve_tenant when tenant object
              # is passed via tenant: param
              context.tenant_id = tenant_value[:id]&.to_s
              context.tenant_object = tenant_value[:object]
              context.tenant_config = tenant_value.except(:id, :object)

            else
              # Object with llm_tenant_id method
              if tenant_value.respond_to?(:llm_tenant_id)
                context.tenant_id = tenant_value.llm_tenant_id&.to_s
                context.tenant_object = tenant_value
                context.tenant_config = extract_tenant_config(tenant_value)
              else
                raise ArgumentError,
                      "tenant must respond to :llm_tenant_id (use llm_tenant DSL), " \
                      "or be a Hash with :id key, got #{tenant_value.class}"
              end
            end
          end

          # Applies API configuration to RubyLLM based on resolved tenant
          #
          # @param context [Context] The execution context
          def apply_api_configuration!(context)
            # Apply keys from tenant object's llm_api_keys method if present
            apply_tenant_object_api_keys!(context)
          end

          # Applies API keys from tenant object's llm_api_keys method
          #
          # @param context [Context] The execution context
          def apply_tenant_object_api_keys!(context)
            tenant_object = context.tenant_object
            return unless tenant_object.respond_to?(:llm_api_keys)

            api_keys = tenant_object.llm_api_keys
            return if api_keys.blank?

            apply_api_keys_to_ruby_llm(api_keys)
          rescue StandardError => e
            # Log but don't fail if API key extraction fails
            warn_api_key_error("tenant object", e)
          end

          # Applies a hash of API keys to RubyLLM configuration
          #
          # @param api_keys [Hash] Hash of provider => key mappings
          def apply_api_keys_to_ruby_llm(api_keys)
            RubyLLM.configure do |config|
              api_keys.each do |provider, key|
                next if key.blank?

                setter = api_key_setter_for(provider)
                config.public_send(setter, key) if config.respond_to?(setter)
              end
            end
          end

          # Returns the setter method name for a provider's API key
          #
          # @param provider [Symbol, String] Provider name (e.g., :openai, :anthropic)
          # @return [String] Setter method name (e.g., "openai_api_key=")
          def api_key_setter_for(provider)
            "#{provider}_api_key="
          end

          # Logs a warning about API key resolution failure
          #
          # @param source [String] Source that failed
          # @param error [StandardError] The error
          def warn_api_key_error(source, error)
            return unless defined?(Rails) && Rails.respond_to?(:logger)

            Rails.logger.warn(
              "[RubyLLM::Agents] Failed to resolve API keys from #{source}: #{error.message}"
            )
          end

          # Extracts additional configuration from tenant object
          #
          # @param tenant [Object] The tenant object
          # @return [Hash, nil] Additional configuration or nil
          def extract_tenant_config(tenant)
            return nil unless tenant.respond_to?(:llm_config)

            tenant.llm_config
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
