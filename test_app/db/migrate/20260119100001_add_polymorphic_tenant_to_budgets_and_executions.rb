# frozen_string_literal: true

# Add polymorphic tenant_record columns to support the LLMTenant concern
#
# This enables models to be declared as LLM tenants using:
#   class Organization < ApplicationRecord
#     include RubyLLM::Agents::LLMTenant
#     llm_tenant id: :slug, ...
#   end
#
# The polymorphic association allows any model to be a tenant.
class AddPolymorphicTenantToBudgetsAndExecutions < ActiveRecord::Migration[7.1]
  def change
    # Add polymorphic columns to tenant_budgets
    add_reference :ruby_llm_agents_tenant_budgets, :tenant_record, polymorphic: true, index: true

    # Add polymorphic columns to executions (for has_many association)
    add_reference :ruby_llm_agents_executions, :tenant_record, polymorphic: true, index: true
  end
end
