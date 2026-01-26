# frozen_string_literal: true

module RubyLLM
  module Agents
    module Budget
      # Resolves budget configuration for tenants and global settings
      #
      # Handles the resolution priority chain:
      # 1. Runtime config passed to run()
      # 2. tenant_config_resolver lambda
      # 3. TenantBudget database record
      # 4. Global configuration
      #
      # @api private
      module ConfigResolver
        class << self
          # Resolves the current tenant ID
          #
          # @param explicit_tenant_id [String, nil] Explicitly passed tenant ID
          # @return [String, nil] Resolved tenant ID or nil if multi-tenancy disabled
          def resolve_tenant_id(explicit_tenant_id)
            config = RubyLLM::Agents.configuration

            # Ignore tenant_id entirely when multi-tenancy is disabled
            return nil unless config.multi_tenancy_enabled?

            # Use explicit tenant_id if provided, otherwise use resolver
            return explicit_tenant_id if explicit_tenant_id.present?

            config.tenant_resolver&.call
          end

          # Resolves budget configuration for a tenant
          #
          # Priority order:
          # 1. runtime_config (passed to run())
          # 2. tenant_config_resolver (configured lambda)
          # 3. TenantBudget database record
          # 4. Global configuration
          #
          # @param tenant_id [String, nil] The tenant identifier
          # @param runtime_config [Hash, nil] Runtime config passed to run()
          # @return [Hash] Budget configuration
          def resolve_budget_config(tenant_id, runtime_config: nil)
            config = RubyLLM::Agents.configuration

            # Priority 1: Runtime config passed directly to run()
            if runtime_config.present?
              return normalize_budget_config(runtime_config, config)
            end

            # If multi-tenancy is disabled or no tenant, use global config
            if tenant_id.nil? || !config.multi_tenancy_enabled?
              return global_budget_config(config)
            end

            # Priority 2: tenant_config_resolver lambda
            if config.tenant_config_resolver.present?
              resolved_config = config.tenant_config_resolver.call(tenant_id)
              if resolved_config.present?
                return normalize_budget_config(resolved_config, config)
              end
            end

            # Priority 3: Look up tenant-specific budget from database
            tenant_budget = lookup_tenant_budget(tenant_id)

            if tenant_budget
              tenant_budget.to_budget_config
            else
              # Priority 4: Fall back to global config for unknown tenants
              global_budget_config(config)
            end
          end

          # Builds global budget config from configuration
          #
          # @param config [Configuration] The configuration object
          # @return [Hash] Budget configuration
          def global_budget_config(config)
            {
              enabled: config.budgets_enabled?,
              enforcement: config.budget_enforcement,
              global_daily: config.budgets&.dig(:global_daily),
              global_monthly: config.budgets&.dig(:global_monthly),
              per_agent_daily: config.budgets&.dig(:per_agent_daily),
              per_agent_monthly: config.budgets&.dig(:per_agent_monthly),
              global_daily_tokens: config.budgets&.dig(:global_daily_tokens),
              global_monthly_tokens: config.budgets&.dig(:global_monthly_tokens)
            }
          end

          # Normalizes runtime/resolver config to standard budget config format
          #
          # @param raw_config [Hash] Raw config from runtime or resolver
          # @param global_config [Configuration] Global config for fallbacks
          # @return [Hash] Normalized budget configuration
          def normalize_budget_config(raw_config, global_config)
            enforcement = raw_config[:enforcement]&.to_sym || global_config.budget_enforcement

            {
              enabled: enforcement != :none,
              enforcement: enforcement,
              # Cost/budget limits (USD)
              global_daily: raw_config[:daily_budget_limit],
              global_monthly: raw_config[:monthly_budget_limit],
              per_agent_daily: raw_config[:per_agent_daily] || {},
              per_agent_monthly: raw_config[:per_agent_monthly] || {},
              # Token limits
              global_daily_tokens: raw_config[:daily_token_limit],
              global_monthly_tokens: raw_config[:monthly_token_limit]
            }
          end

          # Safely looks up tenant budget, handling missing table
          #
          # @param tenant_id [String] The tenant identifier
          # @return [TenantBudget, nil] The tenant budget or nil
          def lookup_tenant_budget(tenant_id)
            return nil unless tenant_budget_table_exists?

            TenantBudget.for_tenant(tenant_id)
          rescue StandardError => e
            Rails.logger.warn("[RubyLLM::Agents] Failed to lookup tenant budget: #{e.message}")
            nil
          end

          # Checks if the tenants table exists (supports old and new table names)
          #
          # @return [Boolean] true if table exists
          def tenant_budget_table_exists?
            return @tenant_budget_table_exists if defined?(@tenant_budget_table_exists)

            # Check for new table name (tenants) or old table name (tenant_budgets) for backward compatibility
            @tenant_budget_table_exists = ::ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenants) ||
                                          ::ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
          rescue StandardError
            @tenant_budget_table_exists = false
          end

          # Resets the memoized tenant budget table existence check (useful for testing)
          #
          # @return [void]
          def reset_tenant_budget_table_check!
            remove_instance_variable(:@tenant_budget_table_exists) if defined?(@tenant_budget_table_exists)
          end
        end
      end
    end
  end
end
