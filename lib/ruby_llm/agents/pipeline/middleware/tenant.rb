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
            ensure_tenant_record!(context)
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
              # No explicit tenant - fall back to configured tenant_resolver
              resolved_value = RubyLLM::Agents.configuration.current_tenant_id

              if resolved_value.respond_to?(:llm_tenant_id)
                context.tenant_id = resolved_value.llm_tenant_id&.to_s
                context.tenant_object = resolved_value
                context.tenant_config = extract_tenant_config(resolved_value)
              else
                context.tenant_id = resolved_value&.to_s
                context.tenant_object = nil
                context.tenant_config = nil
              end

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

          # Ensures a Tenant record exists in the database for the resolved tenant.
          #
          # When a host model (e.g., Organization) with LLMTenant is passed as
          # tenant: to an agent, the after_create callback only fires for new records.
          # Pre-existing records won't have a Tenant row yet. This method auto-creates
          # it on first use so budget tracking and the dashboard work correctly.
          #
          # @param context [Context] The execution context
          def ensure_tenant_record!(context)
            return unless context.tenant_id.present?
            return unless tenant_table_exists?

            tenant_object = context.tenant_object

            # Only auto-create when the tenant object uses the LLMTenant concern
            if tenant_object.respond_to?(:llm_tenant_id) && tenant_object.is_a?(::ActiveRecord::Base)
              ensure_tenant_for_model!(tenant_object)
            else
              # For hash-based or string tenants, ensure a minimal record exists
              find_or_create_tenant!(context.tenant_id)
            end
          rescue => e
            # Don't fail the execution if tenant record creation fails
            log_tenant_warning("ensure tenant record", e)
          end

          # Creates a Tenant record linked to the host model if one doesn't exist
          #
          # @param tenant_object [ActiveRecord::Base] The host model with LLMTenant
          def ensure_tenant_for_model!(tenant_object)
            # Check polymorphic link first, then tenant_id
            existing = RubyLLM::Agents::Tenant.find_by(tenant_record: tenant_object) ||
              RubyLLM::Agents::Tenant.find_by(tenant_id: tenant_object.llm_tenant_id)
            return if existing

            options = tenant_object.class.try(:llm_tenant_options) || {}
            limits = options[:limits] || {}
            name_method = options[:name] || :to_s

            RubyLLM::Agents::Tenant.create!(
              tenant_id: tenant_object.llm_tenant_id,
              name: tenant_object.send(name_method).to_s,
              tenant_record: tenant_object,
              daily_limit: limits[:daily_cost],
              monthly_limit: limits[:monthly_cost],
              daily_token_limit: limits[:daily_tokens],
              monthly_token_limit: limits[:monthly_tokens],
              daily_execution_limit: limits[:daily_executions],
              monthly_execution_limit: limits[:monthly_executions],
              enforcement: options[:enforcement]&.to_s || "soft",
              inherit_global_defaults: options.fetch(:inherit_global, true)
            )
          rescue ActiveRecord::RecordNotUnique
            # Race condition: another thread created the record — safe to ignore
          end

          # Finds or creates a tenant record, handling race conditions
          #
          # @param tenant_id [String] The tenant identifier
          def find_or_create_tenant!(tenant_id)
            RubyLLM::Agents::Tenant.find_or_create_by!(tenant_id: tenant_id)
          rescue ActiveRecord::RecordNotUnique
            # Another thread/process created the record — just find it
            RubyLLM::Agents::Tenant.find_by!(tenant_id: tenant_id)
          end

          # Checks if the tenants table exists (memoized)
          #
          # @return [Boolean]
          def tenant_table_exists?
            return @tenant_table_exists if defined?(@tenant_table_exists)

            @tenant_table_exists = ::ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenants)
          rescue => e
            debug("Failed to check tenant table existence: #{e.message}")
            @tenant_table_exists = false
          end

          # Logs a warning without failing the execution
          #
          # @param action [String] What was being attempted
          # @param error [StandardError] The error
          def log_tenant_warning(action, error)
            return unless defined?(Rails) && Rails.respond_to?(:logger)

            Rails.logger.warn(
              "[RubyLLM::Agents] Failed to #{action}: #{error.message}"
            )
          end

          # Applies API configuration to RubyLLM based on resolved tenant
          #
          # @param context [Context] The execution context
          def apply_api_configuration!(context)
            # Apply keys from tenant object's llm_api_keys method if present
            apply_tenant_object_api_keys!(context)
          end

          # Stores tenant API keys on the context for thread-safe per-request use.
          #
          # Instead of mutating the global RubyLLM configuration (which is not
          # thread-safe), keys are stored on the context. The Pipeline::Context#llm
          # method creates a scoped RubyLLM::Context with these keys when needed.
          #
          # @param context [Context] The execution context
          def apply_tenant_object_api_keys!(context)
            tenant_object = context.tenant_object
            return unless tenant_object.respond_to?(:llm_api_keys)

            api_keys = tenant_object.llm_api_keys
            return if api_keys.blank?

            context[:tenant_api_keys] = api_keys
          rescue => e
            # Log but don't fail if API key extraction fails
            warn_api_key_error("tenant object", e)
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
          rescue => e
            debug("Failed to extract tenant config: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
