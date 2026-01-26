# Tenant Model Refactor Plan

## Overview

Refactor `TenantBudget` into a unified `Tenant` model that serves as the central entity for all tenant-related functionality. Use concerns to organize the model's logic into cohesive, maintainable modules.

---

## Goals

1. **Single source of truth** - One `Tenant` model for all tenant data
2. **Concern-based organization** - Separate concerns for budget, usage tracking, API config, etc.
3. **Cleaner architecture** - Reduce scattered logic across multiple models
4. **Extensibility** - Easy to add new tenant features (rate limits, feature flags, etc.)
5. **Backward compatibility** - Existing `TenantBudget` usage continues to work via alias

---

## Current State

```
TenantBudget (table: ruby_llm_agents_tenant_budgets)
├── tenant_id (string)
├── name
├── budget limits (daily_limit, monthly_limit, etc.)
├── enforcement
├── polymorphic tenant_record
└── per_agent limits

ApiConfiguration (table: ruby_llm_agents_api_configurations)
├── scope_type, scope_id (for tenant scoping)
├── API keys
└── connection settings

LLMTenant (concern)
├── Included in user's model (Organization, Account)
├── Adds llm_executions, llm_budget associations
└── Instance methods (llm_cost, llm_within_budget?, etc.)

Execution (table: ruby_llm_agents_executions)
├── tenant_id
├── tenant_record (polymorphic)
└── usage data
```

**Problems:**
- Tenant logic scattered across TenantBudget, LLMTenant concern, BudgetTracker
- TenantBudget is really a Tenant with budget config
- Adding new tenant features requires touching multiple files
- No clear single entity representing a tenant in the gem

---

## Target State

```
Tenant (table: ruby_llm_agents_tenants)
├── Core identity
│   ├── tenant_id (string, unique)
│   ├── name
│   └── tenant_record (polymorphic to user's model)
│
├── Budgetable concern
│   ├── daily_limit, monthly_limit
│   ├── daily_token_limit, monthly_token_limit
│   ├── daily_execution_limit, monthly_execution_limit
│   ├── per_agent_daily, per_agent_monthly
│   ├── enforcement
│   └── inherit_global_defaults
│
├── Trackable concern
│   ├── has_many :executions
│   ├── cost methods (cost_today, cost_this_month)
│   ├── token methods (tokens_today, tokens_this_month)
│   └── execution count methods
│
├── Configurable concern (future)
│   ├── has_one :api_configuration
│   └── API key accessors
│
└── Limitable concern (future)
    ├── rate_limit_per_minute
    ├── rate_limit_per_hour
    └── feature_flags (JSON)

LLMTenant (concern for user's model)
├── Simplified - delegates to Tenant
├── has_one :llm_tenant (the gem's Tenant model)
└── Convenience methods that delegate

TenantBudget = Tenant (alias for backward compatibility)
```

---

## File Structure

```
app/models/ruby_llm/agents/
├── tenant.rb                           # Main Tenant model
├── tenant/
│   ├── budgetable.rb                   # Budget limits and enforcement
│   ├── trackable.rb                    # Usage tracking (cost, tokens, executions)
│   ├── configurable.rb                 # API configuration (future)
│   └── limitable.rb                    # Rate limits, feature flags (future)
├── tenant_budget.rb                    # DEPRECATED: alias to Tenant
└── llm_tenant.rb                       # Concern for user's models (updated)

lib/ruby_llm/agents/
└── budget_tracker.rb                   # Updated to use Tenant
```

---

## Tenant Model with Concerns

### Main Model

**File:** `app/models/ruby_llm/agents/tenant.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    # Central model for tenant management in multi-tenant LLM applications.
    #
    # Encapsulates all tenant-related functionality:
    # - Budget limits and enforcement
    # - Usage tracking (cost, tokens, executions)
    # - API configuration (future)
    # - Rate limiting (future)
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
    class Tenant < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_tenants"

      # Include concerns for organized functionality
      include Tenant::Budgetable
      include Tenant::Trackable
      # include Tenant::Configurable  # Future
      # include Tenant::Limitable     # Future

      # Polymorphic association to user's tenant model (optional)
      belongs_to :tenant_record, polymorphic: true, optional: true

      # Validations
      validates :tenant_id, presence: true, uniqueness: true

      # Scopes
      scope :active, -> { where(active: true) }
      scope :with_enforcement, ->(mode) { where(enforcement: mode) }

      # Find or initialize tenant for given record or ID
      #
      # @param tenant [String, ActiveRecord::Base] Tenant ID or model with llm_tenant_id
      # @return [Tenant, nil]
      def self.for(tenant)
        return nil if tenant.blank?

        if tenant.is_a?(::ActiveRecord::Base)
          find_by(tenant_record: tenant) ||
            find_by(tenant_id: tenant.try(:llm_tenant_id) || tenant.id.to_s)
        elsif tenant.respond_to?(:llm_tenant_id)
          find_by(tenant_id: tenant.llm_tenant_id)
        else
          find_by(tenant_id: tenant.to_s)
        end
      end

      # Find or create tenant
      #
      # @param tenant_id [String] Unique tenant identifier
      # @param attributes [Hash] Additional attributes
      # @return [Tenant]
      def self.for!(tenant_id, **attributes)
        find_or_create_by!(tenant_id: tenant_id) do |tenant|
          tenant.assign_attributes(attributes)
        end
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
    end
  end
end
```

---

### Budgetable Concern

**File:** `app/models/ruby_llm/agents/tenant/budgetable.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Handles budget limits and enforcement for tenants.
      #
      # Supports three types of limits:
      # - Cost limits (USD): daily_limit, monthly_limit
      # - Token limits: daily_token_limit, monthly_token_limit
      # - Execution limits: daily_execution_limit, monthly_execution_limit
      #
      # Enforcement modes:
      # - :none - No enforcement, tracking only
      # - :soft - Log warnings when limits exceeded
      # - :hard - Block execution when limits exceeded
      #
      module Budgetable
        extend ActiveSupport::Concern

        ENFORCEMENT_MODES = %w[none soft hard].freeze

        included do
          # Validations
          validates :enforcement, inclusion: { in: ENFORCEMENT_MODES }, allow_nil: true
          validates :daily_limit, :monthly_limit,
                    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
          validates :daily_token_limit, :monthly_token_limit,
                    numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
          validates :daily_execution_limit, :monthly_execution_limit,
                    numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true

          # Scopes
          scope :with_budgets, -> { where.not(daily_limit: nil).or(where.not(monthly_limit: nil)) }
          scope :hard_enforcement, -> { where(enforcement: "hard") }
        end

        # Effective limits (considering inheritance)

        def effective_daily_limit
          daily_limit.presence || (inherit_global_defaults && global_config&.dig(:global_daily))
        end

        def effective_monthly_limit
          monthly_limit.presence || (inherit_global_defaults && global_config&.dig(:global_monthly))
        end

        def effective_daily_token_limit
          daily_token_limit.presence || (inherit_global_defaults && global_config&.dig(:global_daily_tokens))
        end

        def effective_monthly_token_limit
          monthly_token_limit.presence || (inherit_global_defaults && global_config&.dig(:global_monthly_tokens))
        end

        def effective_daily_execution_limit
          daily_execution_limit.presence || (inherit_global_defaults && global_config&.dig(:global_daily_executions))
        end

        def effective_monthly_execution_limit
          monthly_execution_limit.presence || (inherit_global_defaults && global_config&.dig(:global_monthly_executions))
        end

        def effective_enforcement
          return enforcement.to_sym if enforcement.present?
          return :soft unless inherit_global_defaults

          RubyLLM::Agents.configuration.budget_enforcement
        end

        def effective_per_agent_daily(agent_type)
          limit = per_agent_daily&.dig(agent_type)
          return limit if limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:per_agent_daily, agent_type)
        end

        def effective_per_agent_monthly(agent_type)
          limit = per_agent_monthly&.dig(agent_type)
          return limit if limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:per_agent_monthly, agent_type)
        end

        # Budget status checks

        def budgets_enabled?
          effective_enforcement != :none
        end

        def hard_enforcement?
          effective_enforcement == :hard
        end

        def soft_enforcement?
          effective_enforcement == :soft
        end

        # Check if within budget for a specific type
        #
        # @param type [Symbol] :daily_cost, :monthly_cost, :daily_tokens, etc.
        # @return [Boolean]
        def within_budget?(type: :daily_cost)
          status = budget_status
          return true unless status[:enabled]

          key = budget_status_key(type)
          (status.dig(key, :percentage_used) || 0) < 100
        end

        # Get remaining budget for a specific type
        #
        # @param type [Symbol] :daily_cost, :monthly_cost, :daily_tokens, etc.
        # @return [Numeric, nil]
        def remaining_budget(type: :daily_cost)
          status = budget_status
          key = budget_status_key(type)
          status.dig(key, :remaining)
        end

        # Check budget and raise if exceeded (for hard enforcement)
        #
        # @param agent_type [String] The agent class name
        # @raise [BudgetExceededError] If hard enforcement and over budget
        def check_budget!(agent_type = nil)
          BudgetTracker.check_budget!(agent_type || "Unknown", tenant_id: tenant_id)
        end

        # Get full budget status
        #
        # @return [Hash]
        def budget_status
          BudgetTracker.status(tenant_id: tenant_id)
        end

        # Convert to config hash for BudgetTracker
        #
        # @return [Hash]
        def to_budget_config
          {
            enabled: budgets_enabled?,
            enforcement: effective_enforcement,
            global_daily: effective_daily_limit,
            global_monthly: effective_monthly_limit,
            per_agent_daily: merged_per_agent_daily,
            per_agent_monthly: merged_per_agent_monthly,
            global_daily_tokens: effective_daily_token_limit,
            global_monthly_tokens: effective_monthly_token_limit,
            global_daily_executions: effective_daily_execution_limit,
            global_monthly_executions: effective_monthly_execution_limit
          }
        end

        private

        def global_config
          RubyLLM::Agents.configuration.budgets
        end

        def merged_per_agent_daily
          return per_agent_daily || {} unless inherit_global_defaults

          (global_config&.dig(:per_agent_daily) || {}).merge(per_agent_daily || {})
        end

        def merged_per_agent_monthly
          return per_agent_monthly || {} unless inherit_global_defaults

          (global_config&.dig(:per_agent_monthly) || {}).merge(per_agent_monthly || {})
        end

        def budget_status_key(type)
          case type
          when :daily_cost then :global_daily
          when :monthly_cost then :global_monthly
          when :daily_tokens then :global_daily_tokens
          when :monthly_tokens then :global_monthly_tokens
          when :daily_executions then :global_daily_executions
          when :monthly_executions then :global_monthly_executions
          else :global_daily
          end
        end
      end
    end
  end
end
```

---

### Trackable Concern

**File:** `app/models/ruby_llm/agents/tenant/trackable.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Tracks LLM usage for a tenant including costs, tokens, and execution counts.
      #
      # Provides methods for querying usage data with various time periods:
      # - :today, :yesterday, :this_week, :this_month
      # - Custom date ranges
      #
      module Trackable
        extend ActiveSupport::Concern

        included do
          has_many :executions,
                   class_name: "RubyLLM::Agents::Execution",
                   primary_key: :tenant_id,
                   foreign_key: :tenant_id,
                   inverse_of: false
        end

        # Cost queries

        def cost(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.sum(:total_cost) || 0
        end

        def cost_today
          cost(period: :today)
        end

        def cost_yesterday
          cost(period: :yesterday)
        end

        def cost_this_week
          cost(period: :this_week)
        end

        def cost_this_month
          cost(period: :this_month)
        end

        # Token queries

        def tokens(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.sum(:total_tokens) || 0
        end

        def tokens_today
          tokens(period: :today)
        end

        def tokens_yesterday
          tokens(period: :yesterday)
        end

        def tokens_this_week
          tokens(period: :this_week)
        end

        def tokens_this_month
          tokens(period: :this_month)
        end

        # Execution count queries

        def execution_count(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.count
        end

        def executions_today
          execution_count(period: :today)
        end

        def executions_yesterday
          execution_count(period: :yesterday)
        end

        def executions_this_week
          execution_count(period: :this_week)
        end

        def executions_this_month
          execution_count(period: :this_month)
        end

        # Usage summary

        def usage_summary(period: :this_month)
          {
            tenant_id: tenant_id,
            name: display_name,
            period: period,
            cost: cost(period: period),
            tokens: tokens(period: period),
            executions: execution_count(period: period)
          }
        end

        # Usage by agent type
        #
        # @param period [Symbol, Range] Time period
        # @return [Hash] { "AgentName" => { cost: X, tokens: Y, count: Z } }
        def usage_by_agent(period: :this_month)
          scope = executions
          scope = apply_period_scope(scope, period) if period

          scope.group(:agent_type).pluck(
            :agent_type,
            Arel.sql("SUM(total_cost)"),
            Arel.sql("SUM(total_tokens)"),
            Arel.sql("COUNT(*)")
          ).to_h do |agent_type, cost, tokens, count|
            [agent_type, { cost: cost || 0, tokens: tokens || 0, count: count }]
          end
        end

        # Usage by model
        #
        # @param period [Symbol, Range] Time period
        # @return [Hash] { "model-id" => { cost: X, tokens: Y, count: Z } }
        def usage_by_model(period: :this_month)
          scope = executions
          scope = apply_period_scope(scope, period) if period

          scope.group(:model_id).pluck(
            :model_id,
            Arel.sql("SUM(total_cost)"),
            Arel.sql("SUM(total_tokens)"),
            Arel.sql("COUNT(*)")
          ).to_h do |model_id, cost, tokens, count|
            [model_id, { cost: cost || 0, tokens: tokens || 0, count: count }]
          end
        end

        private

        def apply_period_scope(scope, period)
          case period
          when :today then scope.where(created_at: Time.current.all_day)
          when :yesterday then scope.where(created_at: 1.day.ago.all_day)
          when :this_week then scope.where(created_at: Time.current.all_week)
          when :this_month then scope.where(created_at: Time.current.all_month)
          when :last_month then scope.where(created_at: 1.month.ago.all_month)
          when Range then scope.where(created_at: period)
          else scope
          end
        end
      end
    end
  end
end
```

---

### Configurable Concern (Future)

**File:** `app/models/ruby_llm/agents/tenant/configurable.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Manages API configuration for a tenant.
      # Allows tenants to have their own API keys and settings.
      #
      # Future implementation - links to ApiConfiguration model.
      #
      module Configurable
        extend ActiveSupport::Concern

        included do
          has_one :api_configuration,
                  class_name: "RubyLLM::Agents::ApiConfiguration",
                  foreign_key: :scope_id,
                  primary_key: :tenant_id,
                  dependent: :destroy
        end

        # Get API key for provider
        #
        # @param provider [Symbol] :openai, :anthropic, etc.
        # @return [String, nil]
        def api_key_for(provider)
          api_configuration&.send("#{provider}_api_key")
        end

        # Check if tenant has custom API keys
        #
        # @return [Boolean]
        def has_custom_api_keys?
          api_configuration.present?
        end

        # Get effective configuration (tenant or global fallback)
        #
        # @return [ApiConfiguration, nil]
        def effective_api_configuration
          api_configuration || ApiConfiguration.global
        end
      end
    end
  end
end
```

---

### Limitable Concern (Future)

**File:** `app/models/ruby_llm/agents/tenant/limitable.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Rate limiting and feature flags for tenants.
      #
      # Future implementation for:
      # - Rate limiting (requests per minute/hour)
      # - Feature flags (enable/disable features per tenant)
      # - Model restrictions (allowed/blocked models)
      #
      module Limitable
        extend ActiveSupport::Concern

        included do
          # Future columns:
          # - rate_limit_per_minute
          # - rate_limit_per_hour
          # - feature_flags (JSON)
          # - allowed_models (JSON array)
          # - blocked_models (JSON array)
        end

        # Check if tenant can make a request (rate limiting)
        #
        # @return [Boolean]
        def can_make_request?
          # Future implementation
          true
        end

        # Check if feature is enabled for tenant
        #
        # @param feature [Symbol] Feature name
        # @return [Boolean]
        def feature_enabled?(feature)
          # Future implementation
          true
        end

        # Check if model is allowed for tenant
        #
        # @param model_id [String] Model identifier
        # @return [Boolean]
        def model_allowed?(model_id)
          # Future implementation
          true
        end
      end
    end
  end
end
```

---

## Migration

**File:** `db/migrate/XXXXXX_rename_tenant_budgets_to_tenants.rb`

```ruby
class RenameTenantBudgetsToTenants < ActiveRecord::Migration[7.0]
  def change
    # Rename table
    rename_table :ruby_llm_agents_tenant_budgets, :ruby_llm_agents_tenants

    # Add new columns for future features
    add_column :ruby_llm_agents_tenants, :active, :boolean, default: true
    add_column :ruby_llm_agents_tenants, :metadata, :json, default: {}

    # Future columns (commented for now)
    # add_column :ruby_llm_agents_tenants, :rate_limit_per_minute, :integer
    # add_column :ruby_llm_agents_tenants, :rate_limit_per_hour, :integer
    # add_column :ruby_llm_agents_tenants, :feature_flags, :json, default: {}
    # add_column :ruby_llm_agents_tenants, :allowed_models, :json, default: []
    # add_column :ruby_llm_agents_tenants, :blocked_models, :json, default: []

    # Update index names
    rename_index :ruby_llm_agents_tenants,
                 "index_tenant_budgets_on_tenant_record",
                 "index_tenants_on_tenant_record"
  end
end
```

---

## Backward Compatibility

**File:** `app/models/ruby_llm/agents/tenant_budget.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    # DEPRECATED: Use RubyLLM::Agents::Tenant instead.
    #
    # This class is an alias for backward compatibility.
    # It will be removed in a future major version.
    #
    # @deprecated Use {Tenant} instead
    TenantBudget = Tenant

    # Keep class methods working
    class << TenantBudget
      def for_tenant(tenant)
        Tenant.for(tenant)
      end

      def for_tenant!(tenant_id, **attributes)
        Tenant.for!(tenant_id, **attributes)
      end
    end
  end
end
```

---

## Updated LLMTenant Concern

**File:** `app/models/ruby_llm/agents/llm_tenant.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    # Concern to include in user's tenant model (Organization, Account, etc.)
    #
    # Provides convenient access to the gem's Tenant model and its functionality.
    # Delegates most operations to the underlying Tenant record.
    #
    module LLMTenant
      extend ActiveSupport::Concern

      included do
        # Link to gem's Tenant model
        has_one :llm_tenant,
                class_name: "RubyLLM::Agents::Tenant",
                as: :tenant_record,
                dependent: :destroy

        # Direct link to executions (for convenience)
        has_many :llm_executions,
                 class_name: "RubyLLM::Agents::Execution",
                 as: :tenant_record,
                 dependent: :nullify

        class_attribute :llm_tenant_options, default: {}
      end

      class_methods do
        def llm_tenant(id: :id, name: :to_s, budget: false, limits: nil,
                       enforcement: nil, api_keys: nil, **options)
          self.llm_tenant_options = {
            id: id,
            name: name,
            budget: budget || limits.present?,
            limits: normalize_limits(limits),
            enforcement: enforcement,
            api_keys: api_keys,
            **options
          }

          after_create :create_llm_tenant_record, if: -> {
            self.class.llm_tenant_options[:budget]
          }
        end

        private

        def normalize_limits(limits)
          return {} if limits.blank?

          {
            daily_cost: limits[:daily_cost],
            monthly_cost: limits[:monthly_cost],
            daily_tokens: limits[:daily_tokens],
            monthly_tokens: limits[:monthly_tokens],
            daily_executions: limits[:daily_executions],
            monthly_executions: limits[:monthly_executions]
          }.compact
        end
      end

      # Tenant ID for this record
      def llm_tenant_id
        id_method = self.class.llm_tenant_options[:id] || :id
        send(id_method).to_s
      end

      # Get or build the Tenant record
      def llm_tenant_record
        llm_tenant || build_llm_tenant(tenant_id: llm_tenant_id)
      end

      # Delegate to Tenant: Budget methods
      delegate :within_budget?, :remaining_budget, :check_budget!, :budget_status,
               :effective_daily_limit, :effective_monthly_limit,
               :budgets_enabled?, :hard_enforcement?,
               to: :llm_tenant_record, prefix: :llm, allow_nil: true

      # Delegate to Tenant: Tracking methods
      delegate :cost, :cost_today, :cost_this_month,
               :tokens, :tokens_today, :tokens_this_month,
               :execution_count, :executions_today, :executions_this_month,
               :usage_summary, :usage_by_agent, :usage_by_model,
               to: :llm_tenant_record, prefix: :llm, allow_nil: true

      # Configure the tenant with a block
      def llm_configure(&block)
        tenant = llm_tenant_record
        yield(tenant) if block_given?
        tenant.save!
        tenant
      end

      # Backward compatible alias
      alias_method :llm_budget, :llm_tenant_record
      alias_method :llm_configure_budget, :llm_configure

      private

      def create_llm_tenant_record
        return if llm_tenant.present?

        options = self.class.llm_tenant_options
        limits = options[:limits] || {}
        name_method = options[:name] || :to_s

        build_llm_tenant(
          tenant_id: llm_tenant_id,
          name: send(name_method),
          daily_limit: limits[:daily_cost],
          monthly_limit: limits[:monthly_cost],
          daily_token_limit: limits[:daily_tokens],
          monthly_token_limit: limits[:monthly_tokens],
          daily_execution_limit: limits[:daily_executions],
          monthly_execution_limit: limits[:monthly_executions],
          enforcement: options[:enforcement]&.to_s || "soft",
          inherit_global_defaults: options.fetch(:inherit_global, true)
        )

        llm_tenant.save!
      end
    end
  end
end
```

---

## Generator Updates

**File:** `lib/generators/ruby_llm_agents/templates/create_tenants_migration.rb.tt`

```ruby
class CreateRubyLLMAgentsTenants < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :ruby_llm_agents_tenants do |t|
      # Identity
      t.string :tenant_id, null: false
      t.string :name

      # Polymorphic association to user's tenant model
      t.string :tenant_record_type
      t.string :tenant_record_id

      # Budget limits (cost in USD)
      t.decimal :daily_limit, precision: 12, scale: 6
      t.decimal :monthly_limit, precision: 12, scale: 6

      # Token limits
      t.bigint :daily_token_limit
      t.bigint :monthly_token_limit

      # Execution limits
      t.bigint :daily_execution_limit
      t.bigint :monthly_execution_limit

      # Per-agent limits
      t.json :per_agent_daily, null: false, default: {}
      t.json :per_agent_monthly, null: false, default: {}

      # Enforcement: "none", "soft", "hard"
      t.string :enforcement, default: "soft"
      t.boolean :inherit_global_defaults, default: true

      # Status
      t.boolean :active, default: true

      # Extensible metadata
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ruby_llm_agents_tenants, :tenant_id, unique: true
    add_index :ruby_llm_agents_tenants, :name
    add_index :ruby_llm_agents_tenants, :active
    add_index :ruby_llm_agents_tenants, [:tenant_record_type, :tenant_record_id],
              name: "index_tenants_on_tenant_record"
  end
end
```

---

## Implementation Phases

### Phase 1: Core Refactor ✅ COMPLETE
- [x] Create `Tenant` model with `Budgetable` and `Trackable` concerns
- [x] Create migration generator for new `tenants` table
- [x] Create migration for renaming existing `tenant_budgets` to `tenants`
- [x] Add `TenantBudget` alias for backward compatibility
- [x] Update `LLMTenant` concern to use new `Tenant` model

### Phase 2: Testing ✅ COMPLETE
- [x] Unit tests for `Tenant` model
- [x] Unit tests for `Budgetable` concern (`spec/models/tenant_budget_spec.rb`)
- [x] Unit tests for `Trackable` concern (`spec/models/tenant_spec.rb`)
- [x] Integration tests for `LLMTenant` concern with new `Tenant` (`spec/concerns/llm_tenant_spec.rb`)
- [x] Migration tests (upgrade path) - covered in existing tests
- [x] Backward compatibility tests (`spec/models/tenant_budget_backward_compat_spec.rb`)

### Phase 3: Documentation ✅ COMPLETE
- [x] Update README with new `Tenant` model (`wiki/Multi-Tenancy.md` updated)
- [x] Add CHANGELOG entry (added to `CHANGELOG.md` as Unreleased)
- [x] Deprecation notices for `TenantBudget` (added to Multi-Tenancy wiki)
- [x] Migration guide for existing users (`wiki/Generators.md` updated)

### Phase 4: Advanced Features ✅ COMPLETE
- [x] Implement `Configurable` concern (API keys)
- [x] Implement `Limitable` concern (rate limits, feature flags)
- [x] Add model restrictions (allowed/blocked models)
- [x] Add specs for `Configurable` (`spec/models/tenant_configurable_spec.rb`)
- [x] Add specs for `Limitable` (`spec/models/tenant_limitable_spec.rb`)
- [x] Update documentation (`wiki/Multi-Tenancy.md`)

---

## API Comparison

| Old (TenantBudget) | New (Tenant) |
|--------------------|--------------|
| `TenantBudget.for_tenant(x)` | `Tenant.for(x)` |
| `TenantBudget.for_tenant!(id)` | `Tenant.for!(id)` |
| `budget.effective_daily_limit` | `tenant.effective_daily_limit` |
| `budget.to_budget_config` | `tenant.to_budget_config` |
| N/A | `tenant.cost_today` |
| N/A | `tenant.tokens_this_month` |
| N/A | `tenant.usage_summary` |
| N/A | `tenant.usage_by_agent` |

---

## Open Questions

1. **Keep `TenantBudget` alias forever or deprecate?**
   - Recommendation: Deprecate with warning, remove in next major version

2. **Should `Tenant.for` auto-create if not found?**
   - Recommendation: No, use `Tenant.for!` for that

3. **Merge `ApiConfiguration` into `Tenant` or keep separate?**
   - Recommendation: Keep separate but link via `Configurable` concern

4. **Add `active` column for soft-delete?**
   - Recommendation: Yes, useful for disabling tenants without deleting

---

## Success Criteria

1. All existing `TenantBudget` code continues to work
2. New `Tenant` model provides cleaner API
3. Concerns are well-tested and documented
4. Migration path is smooth for existing users
5. Future extensibility is clear (Configurable, Limitable)
