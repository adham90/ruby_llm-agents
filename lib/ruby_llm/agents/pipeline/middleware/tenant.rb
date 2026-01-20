# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Resolves tenant context from options.
        #
        # This middleware extracts tenant information from the context options
        # and sets the tenant_id, tenant_object, and tenant_config on the context.
        #
        # Supports three formats:
        # - Object with llm_tenant_id method (recommended for ActiveRecord models)
        # - Hash with :id key (simple/legacy format)
        # - nil (no tenant - single-tenant mode)
        #
        # @example With ActiveRecord model
        #   # Model uses llm_tenant DSL
        #   class Organization < ApplicationRecord
        #     include RubyLLM::Agents::LLMTenant
        #     llm_tenant
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
          # Process tenant resolution
          #
          # @param context [Context] The execution context
          # @return [Context] The context with tenant fields populated
          def call(context)
            resolve_tenant!(context)
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
              # Hash format: { id: "tenant_id", ... }
              context.tenant_id = tenant_value[:id]&.to_s
              context.tenant_object = nil
              context.tenant_config = tenant_value.except(:id)

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
