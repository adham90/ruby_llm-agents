# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Checks budget limits before execution and records spend after.
        #
        # This middleware integrates with the BudgetTracker to:
        # - Check if budget limits are exceeded before execution
        # - Record spend after successful execution
        #
        # Budget checking is skipped if:
        # - Budgets are disabled globally in configuration
        # - The result was served from cache (no API call was made)
        #
        # @example With budget enforcement
        #   # In config/initializers/ruby_llm_agents.rb
        #   RubyLLM::Agents.configure do |config|
        #     config.budgets_enabled = true
        #   end
        #
        #   # Budget will be checked before execution
        #   MyAgent.call(query: "test", tenant: { id: "org_123" })
        #
        class Budget < Base
          # Process budget checking and spend recording
          #
          # @param context [Context] The execution context
          # @return [Context] The context after budget processing
          # @raise [BudgetExceededError] If budget is exceeded with hard enforcement
          def call(context)
            return @app.call(context) unless budgets_enabled?

            # Check budget before execution
            check_budget!(context)

            # Execute the chain
            @app.call(context)

            # Record spend after successful execution (if not cached)
            record_spend!(context) if context.success? && !context.cached?

            context
          end

          private

          # Returns whether budgets are enabled globally
          #
          # @return [Boolean]
          def budgets_enabled?
            global_config.budgets_enabled?
          rescue StandardError
            false
          end

          # Checks budget before execution
          #
          # For tenants, checks budget via counter columns on the tenant model.
          # For non-tenant usage, falls back to BudgetTracker (cache-based).
          #
          # @param context [Context] The execution context
          # @raise [BudgetExceededError] If budget exceeded with hard enforcement
          def check_budget!(context)
            if context.tenant_id.present?
              tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: context.tenant_id)
              if tenant
                tenant.check_budget!(context.agent_class&.name)
                return
              end
            end

            # Fallback to cache-based checking (non-tenant or no tenant record)
            BudgetTracker.check_budget!(
              context.agent_class&.name,
              tenant_id: context.tenant_id
            )
          rescue RubyLLM::Agents::Reliability::BudgetExceededError
            raise
          rescue StandardError => e
            error("Budget check failed: #{e.message}")
          end

          # Records spend after execution
          #
          # For tenants, uses atomic SQL increment via tenant.record_execution!.
          # For non-tenant usage, falls back to BudgetTracker (cache-based).
          #
          # @param context [Context] The execution context
          def record_spend!(context)
            if context.tenant_id.present?
              tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: context.tenant_id)
              if tenant
                tenant.record_execution!(
                  cost: context.total_cost || 0,
                  tokens: context.total_tokens || 0,
                  error: context.error?
                )
                return
              end
            end

            # Fallback for non-tenant usage
            return unless context.total_cost&.positive?

            BudgetTracker.record_spend!(
              context.agent_class&.name,
              context.total_cost,
              tenant_id: context.tenant_id
            )

            if context.total_tokens&.positive?
              BudgetTracker.record_tokens!(
                context.agent_class&.name,
                context.total_tokens,
                tenant_id: context.tenant_id
              )
            end
          rescue StandardError => e
            error("Failed to record spend: #{e.message}")
          end
        end
      end
    end
  end
end
