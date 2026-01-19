# frozen_string_literal: true

# Migration to add tenant_id column to executions for multi-tenancy support
#
# This migration adds a tenant_id column to track which tenant each execution
# belongs to, enabling:
# - Filtering executions by tenant
# - Tenant-scoped analytics and reporting
# - Per-tenant budget tracking and circuit breakers
#
# Run with: rails db:migrate
class AddTenantIdToRubyLLMAgentsExecutions < ActiveRecord::Migration[8.1]
  def change
    # Add tenant_id column (nullable for backward compatibility)
    add_column :ruby_llm_agents_executions, :tenant_id, :string

    # Add indexes for efficient tenant-scoped queries
    add_index :ruby_llm_agents_executions, :tenant_id
    add_index :ruby_llm_agents_executions, [:tenant_id, :created_at]
    add_index :ruby_llm_agents_executions, [:tenant_id, :agent_type]
    add_index :ruby_llm_agents_executions, [:tenant_id, :status]
  end
end
