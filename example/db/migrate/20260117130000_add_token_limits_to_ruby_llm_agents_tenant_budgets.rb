# frozen_string_literal: true

# Migration to add global token-based limits to the tenant_budgets table
#
# Supports global token limits (daily/monthly) across all models.
class AddTokenLimitsToRubyLLMAgentsTenantBudgets < ActiveRecord::Migration[8.1]
  def change
    # Global token limits (across all models)
    add_column :ruby_llm_agents_tenant_budgets, :daily_token_limit, :bigint
    add_column :ruby_llm_agents_tenant_budgets, :monthly_token_limit, :bigint
  end
end
