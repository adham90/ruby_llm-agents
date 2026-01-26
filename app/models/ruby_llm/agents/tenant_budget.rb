# frozen_string_literal: true

module RubyLLM
  module Agents
    # @deprecated Use {Tenant} instead. This class will be removed in a future major version.
    #
    # TenantBudget is now an alias to Tenant for backward compatibility.
    # All functionality has been moved to the Tenant model with organized concerns.
    #
    # @example Migration path
    #   # Old usage (still works)
    #   TenantBudget.for_tenant("acme_corp")
    #   TenantBudget.create!(tenant_id: "acme", daily_limit: 100)
    #
    #   # New usage (preferred)
    #   Tenant.for("acme_corp")
    #   Tenant.create!(tenant_id: "acme", daily_limit: 100)
    #
    # @see Tenant
    TenantBudget = Tenant
  end
end
