# frozen_string_literal: true

# Migration to create the tenant_budgets table for multi-tenancy support
#
# This table stores per-tenant budget configuration, allowing different
# tenants to have their own budget limits and enforcement modes.
#
# Features:
# - Per-tenant daily and monthly budget limits
# - Per-agent budget limits within a tenant
# - Configurable enforcement mode (none, soft, hard)
# - Option to inherit global defaults for unset limits
#
# Run with: rails db:migrate
class CreateRubyLLMAgentsTenantBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :ruby_llm_agents_tenant_budgets do |t|
      # Unique identifier for the tenant (e.g., organization ID, workspace ID)
      t.string :tenant_id, null: false

      # Global budget limits for this tenant
      t.decimal :daily_limit, precision: 12, scale: 6
      t.decimal :monthly_limit, precision: 12, scale: 6

      # Per-agent budget limits (JSON hash)
      # Format: { "AgentName" => limit_value }
      t.json :per_agent_daily, null: false, default: {}
      t.json :per_agent_monthly, null: false, default: {}

      # Enforcement mode for this tenant: "none", "soft", or "hard"
      # - none: no enforcement, only tracking
      # - soft: log warnings when limits exceeded
      # - hard: block execution when limits exceeded
      t.string :enforcement, default: 'soft'

      # Whether to inherit from global config for unset limits
      t.boolean :inherit_global_defaults, default: true

      t.timestamps
    end

    # Ensure unique tenant IDs
    add_index :ruby_llm_agents_tenant_budgets, :tenant_id, unique: true
  end
end
