# frozen_string_literal: true

# Migration to add tenant name to the tenant_budgets table
#
# This allows storing a human-readable name alongside the tenant_id,
# making it easier to display tenant information in dashboards and reports.
class AddNameToRubyLLMAgentsTenantBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :ruby_llm_agents_tenant_budgets, :name, :string

    # Add index for name lookups and searching
    add_index :ruby_llm_agents_tenant_budgets, :name
  end
end
