# frozen_string_literal: true

module RubyLLM
  module Agents
    # @deprecated Use {Tenant} instead. This class will be removed in a future major version.
    #
    # TenantBudget is now an alias to Tenant for backward compatibility.
    # All functionality has been moved to the Tenant model with organized concerns.
    #
    # @example Migration path
    #   # Old usage (still works but emits deprecation warning)
    #   TenantBudget.for_tenant("acme_corp")
    #
    #   # New usage (preferred)
    #   Tenant.for("acme_corp")
    #
    # @see Tenant
    TenantBudget = Tenant

    ActiveSupport.deprecator.warn(
      "RubyLLM::Agents::TenantBudget is deprecated. Use RubyLLM::Agents::Tenant instead. " \
      "This alias will be removed in the next major version."
    )
  end
end
