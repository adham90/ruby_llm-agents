# frozen_string_literal: true

# Migration to add execution-based limits to the tenant_budgets table
#
# Supports global execution limits (daily/monthly) across all models.
class AddExecutionLimitsToRubyLLMAgentsTenantBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :ruby_llm_agents_tenant_budgets, :daily_execution_limit, :bigint
    add_column :ruby_llm_agents_tenant_budgets, :monthly_execution_limit, :bigint
  end
end
