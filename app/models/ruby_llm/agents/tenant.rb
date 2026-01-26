# frozen_string_literal: true

module RubyLLM
  module Agents
    # Central model for tenant management in multi-tenant LLM applications.
    #
    # Encapsulates all tenant-related functionality:
    # - Budget limits and enforcement (via Budgetable concern)
    # - Usage tracking: cost, tokens, executions (via Trackable concern)
    # - API configuration (via Configurable concern - future)
    # - Rate limiting (via Limitable concern - future)
    #
    # @example Creating a tenant
    #   Tenant.create!(
    #     tenant_id: "acme_corp",
    #     name: "Acme Corporation",
    #     daily_limit: 100.0,
    #     enforcement: "hard"
    #   )
    #
    # @example Linking to user's model
    #   Tenant.create!(
    #     tenant_id: organization.id.to_s,
    #     tenant_record: organization,
    #     daily_limit: 100.0
    #   )
    #
    # @example Finding a tenant
    #   tenant = Tenant.for(organization)
    #   tenant = Tenant.for("acme_corp")
    #
    # @see Tenant::Budgetable
    # @see Tenant::Trackable
    # @see LLMTenant
    # @api public
    class Tenant < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_tenants"

      # Include concerns for organized functionality
      include Tenant::Budgetable
      include Tenant::Trackable
      # include Tenant::Configurable  # Future
      # include Tenant::Limitable     # Future

      # Polymorphic association to user's tenant model (optional)
      # Allows linking to Organization, Account, or any ActiveRecord model
      belongs_to :tenant_record, polymorphic: true, optional: true

      # Validations
      validates :tenant_id, presence: true, uniqueness: true

      # Scopes
      scope :active, -> { where(active: true) }
      scope :inactive, -> { where(active: false) }
      scope :linked, -> { where.not(tenant_record_type: nil) }
      scope :unlinked, -> { where(tenant_record_type: nil) }

      # Find tenant for given record or ID
      #
      # Supports multiple lookup strategies:
      # 1. ActiveRecord model - looks up by polymorphic association first, then tenant_id
      # 2. Object with llm_tenant_id - looks up by tenant_id
      # 3. String - looks up by tenant_id
      #
      # @param tenant [String, ActiveRecord::Base, Object] Tenant ID, model, or object with llm_tenant_id
      # @return [Tenant, nil] The tenant record or nil if not found
      #
      # @example Find by model
      #   Tenant.for(organization)
      #
      # @example Find by string ID
      #   Tenant.for("acme_corp")
      #
      def self.for(tenant)
        return nil if tenant.blank?

        if tenant.is_a?(::ActiveRecord::Base)
          # ActiveRecord model - try polymorphic first, then tenant_id
          find_by(tenant_record: tenant) ||
            find_by(tenant_id: tenant.try(:llm_tenant_id) || tenant.id.to_s)
        elsif tenant.respond_to?(:llm_tenant_id)
          # Object with llm_tenant_id method
          find_by(tenant_id: tenant.llm_tenant_id)
        else
          # String tenant_id
          find_by(tenant_id: tenant.to_s)
        end
      end

      # Find or create tenant
      #
      # @param tenant_id [String] Unique tenant identifier
      # @param attributes [Hash] Additional attributes for creation
      # @return [Tenant]
      #
      # @example
      #   Tenant.for!("acme_corp", name: "Acme Corporation")
      #
      def self.for!(tenant_id, **attributes)
        find_or_create_by!(tenant_id: tenant_id.to_s) do |tenant|
          tenant.assign_attributes(attributes)
        end
      end

      # Backward compatible class method aliases
      class << self
        alias_method :for_tenant, :for
        alias_method :for_tenant!, :for!
      end

      # Display name (name or tenant_id fallback)
      #
      # @return [String]
      def display_name
        name.presence || tenant_id
      end

      # Check if tenant is linked to a user model
      #
      # @return [Boolean]
      def linked?
        tenant_record.present?
      end

      # Check if tenant is active
      #
      # @return [Boolean]
      def active?
        active != false
      end

      # Deactivate the tenant
      #
      # @return [Boolean]
      def deactivate!
        update!(active: false)
      end

      # Activate the tenant
      #
      # @return [Boolean]
      def activate!
        update!(active: true)
      end
    end
  end
end
