# Tenant DSL Implementation Plan

## Overview

Add a declarative DSL that allows Rails models to declare themselves as LLM tenants with automatic budget management and usage tracking, reducing boilerplate and improving developer experience.

---

## Goals

1. **Single unified macro** - `llm_tenant` for all tenant functionality
2. **Automatic budget creation** - Optional via `budget: true` or `limits: {...}`
3. **Object-based tenants** - Tenant must be an object, not a string
4. **Agent integration** - Agents accept `tenant:` param, support `def tenant` override
5. **Rails conventions** - Familiar patterns with Rails-y option naming
6. **Backward compatible** - Existing `tenant_id` string usage still works internally

---

## Naming Convention

| Macro | Purpose |
|-------|---------|
| `llm_tenant` | Declares model as an LLM tenant (tracking + optional budget) |

**Method prefix:** `llm_` (e.g., `llm_budget`, `llm_cost_today`, `llm_within_budget?`)

**Options use Rails-y naming:**
- `key:` - Method for tenant ID (not `tenant_id_method:`)
- `budget:` - Auto-create budget (not `auto_create_budget:`)
- `limits:` - Default limits hash (not `default_limits:`)
- `enforcement:` - Budget enforcement mode

---

## Current State

```ruby
# Manual creation
TenantBudget.create!(
  tenant_id: "acme_corp",
  daily_limit: 100.0,
  monthly_limit: 1000.0,
  enforcement: "hard"
)

# Manual lookup
budget = TenantBudget.for_tenant("acme_corp")

# Manual context passing (string-based)
ChatAgent.call(prompt, tenant_id: "acme_corp")
```

---

## Target State

### Model Declaration

```ruby
class Organization < ApplicationRecord
  # Minimal - tracking only, no auto budget
  llm_tenant

  # With custom key
  llm_tenant key: :slug

  # Auto-create budget with global defaults
  llm_tenant key: :slug, budget: true

  # Auto-create budget with specific limits
  llm_tenant key: :slug, limits: { daily_cost: 100, monthly_cost: 1000 }

  # Full configuration
  llm_tenant(
    key: :slug,
    limits: { daily_cost: 100, monthly_cost: 1000, daily_tokens: 1_000_000 },
    enforcement: :hard
  )
end
```

### Instance Methods

```ruby
org.llm_tenant_id           # => "acme-corp" (from slug)
org.llm_budget              # => TenantBudget instance
org.llm_cost_today          # => 12.34
org.llm_tokens_this_month   # => 150000
org.llm_within_budget?      # => true
org.llm_remaining_budget    # => 87.66
org.llm_executions          # => ActiveRecord::Relation

# Block configuration
org.llm_configure_budget do |budget|
  budget.daily_limit = 50.0
  budget.enforcement = "hard"
end
```

### Agent Integration

```ruby
# Pass tenant object directly
ChatAgent.call("Hello", tenant: current_organization)

# Tenant must be an object with llm_tenant_id
ChatAgent.call("Hello", tenant: current_user.organization)

# Dynamic resolution in agent
class ConversationAgent < RubyLLM::Agent
  model "gpt-4"

  # Override tenant resolution
  def tenant
    params[:conversation].organization
  end
end

ConversationAgent.call("Continue", conversation: @conversation)
```

---

## Implementation Tasks

### Phase 1: Core DSL Module

#### 1.1 Create LLMTenant Concern

**File:** `lib/ruby_llm/agents/llm_tenant.rb`

```ruby
module RubyLLM
  module Agents
    module LLMTenant
      extend ActiveSupport::Concern

      included do
        # Executions tracked for this tenant
        has_many :llm_executions,
                 class_name: "RubyLLM::Agents::Execution",
                 as: :tenant_record,
                 dependent: :nullify

        # Budget association (optional)
        has_one :llm_budget,
                class_name: "RubyLLM::Agents::TenantBudget",
                as: :tenant_record,
                dependent: :destroy

        # Store options at class level
        class_attribute :llm_tenant_options, default: {}
      end

      class_methods do
        def llm_tenant(key: :id, budget: false, limits: nil, enforcement: nil, **options)
          self.llm_tenant_options = {
            key: key,
            budget: budget || limits.present?,
            limits: normalize_limits(limits),
            enforcement: enforcement,
            **options
          }

          # Auto-create budget callback
          if llm_tenant_options[:budget]
            after_create :create_default_llm_budget
          end
        end

        private

        def normalize_limits(limits)
          return {} if limits.blank?

          {
            daily_cost: limits[:daily_cost],
            monthly_cost: limits[:monthly_cost],
            daily_tokens: limits[:daily_tokens],
            monthly_tokens: limits[:monthly_tokens]
          }.compact
        end
      end

      # Instance methods
      def llm_tenant_id
        key_method = self.class.llm_tenant_options[:key] || :id
        send(key_method).to_s
      end

      # ... more instance methods
    end
  end
end
```

#### 1.2 Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` | Symbol | `:id` | Method to call for tenant_id string |
| `budget` | Boolean | `false` | Auto-create TenantBudget on model creation |
| `limits` | Hash | `nil` | Default budget limits (implies `budget: true`) |
| `enforcement` | Symbol | `:soft` | Budget enforcement: `:none`, `:soft`, `:hard` |
| `name_method` | Symbol | `:to_s` | Method for budget display name |
| `inherit_global` | Boolean | `true` | Inherit from global config when limit not set |

#### 1.3 Limits Hash Structure

```ruby
limits: {
  daily_cost: 100.0,         # daily_limit column (USD)
  monthly_cost: 1000.0,      # monthly_limit column (USD)
  daily_tokens: 1_000_000,   # daily_token_limit column
  monthly_tokens: 10_000_000 # monthly_token_limit column
}
```

---

### Phase 2: Agent Tenant Integration

#### 2.1 Agent Base Class Updates

**File:** `lib/ruby_llm/agents/agent.rb` (relevant section)

```ruby
module RubyLLM
  class Agent
    # Default tenant param - can be overridden
    def resolved_tenant
      # Check if agent defines custom tenant method
      if self.class.method_defined?(:tenant) && method(:tenant).owner != RubyLLM::Agent
        tenant_value = tenant
      else
        tenant_value = params[:tenant]
      end

      return nil if tenant_value.nil?

      # Must be an object with llm_tenant_id
      unless tenant_value.respond_to?(:llm_tenant_id)
        raise ArgumentError, "tenant must respond to :llm_tenant_id (use llm_tenant in your model)"
      end

      tenant_value
    end

    # Get tenant_id string for internal use
    def resolved_tenant_id
      resolved_tenant&.llm_tenant_id
    end
  end
end
```

#### 2.2 Usage Examples

```ruby
# Pass tenant directly
ChatAgent.call("Hello", tenant: current_organization)

# Tenant is optional
ChatAgent.call("Hello")  # Works, no tenant tracking

# Custom tenant resolution in agent
class ProjectAgent < RubyLLM::Agent
  model "gpt-4"

  def tenant
    # Resolve from project's organization
    Project.find(params[:project_id]).organization
  end
end

ProjectAgent.call("Analyze", project_id: 123)

# Validation - must be object
ChatAgent.call("Hello", tenant: "string")  # Raises ArgumentError
```

---

### Phase 3: TenantBudget Model Updates

#### 3.1 Add Polymorphic Association

**Migration:** `add_tenant_record_to_tenant_budgets.rb`

```ruby
class AddTenantRecordToTenantBudgets < ActiveRecord::Migration[7.0]
  def change
    add_reference :ruby_llm_agents_tenant_budgets, :tenant_record,
                  polymorphic: true,
                  index: true,
                  null: true
  end
end
```

#### 3.2 Update TenantBudget Model

```ruby
class TenantBudget < ::ActiveRecord::Base
  # Add polymorphic association
  belongs_to :tenant_record, polymorphic: true, optional: true

  # Enhanced for_tenant that accepts object or string
  def self.for_tenant(tenant)
    if tenant.respond_to?(:llm_tenant_id)
      find_by(tenant_record: tenant) || find_by(tenant_id: tenant.llm_tenant_id)
    else
      find_by(tenant_id: tenant.to_s)
    end
  end
end
```

---

### Phase 4: Instance Methods

#### 4.1 Tracking Methods

```ruby
# Returns the tenant_id string (for BudgetTracker compatibility)
def llm_tenant_id
  key_method = self.class.llm_tenant_options[:key] || :id
  send(key_method).to_s
end

# Cost queries
def llm_cost(period: nil)
  scope = llm_executions
  scope = apply_period_scope(scope, period) if period
  scope.sum(:total_cost) || 0
end

def llm_cost_today
  llm_cost(period: :today)
end

def llm_cost_this_month
  llm_cost(period: :this_month)
end

# Token queries
def llm_tokens(period: nil)
  scope = llm_executions
  scope = apply_period_scope(scope, period) if period
  scope.sum(:total_tokens) || 0
end

def llm_tokens_today
  llm_tokens(period: :today)
end

def llm_tokens_this_month
  llm_tokens(period: :this_month)
end

# Execution count
def llm_execution_count(period: nil)
  scope = llm_executions
  scope = apply_period_scope(scope, period) if period
  scope.count
end

# Summary
def llm_usage_summary(period: :this_month)
  {
    cost: llm_cost(period: period),
    tokens: llm_tokens(period: period),
    executions: llm_execution_count(period: period),
    period: period
  }
end

private

def apply_period_scope(scope, period)
  case period
  when :today then scope.where(created_at: Time.current.all_day)
  when :yesterday then scope.where(created_at: 1.day.ago.all_day)
  when :this_week then scope.where(created_at: Time.current.all_week)
  when :this_month then scope.where(created_at: Time.current.all_month)
  when Range then scope.where(created_at: period)
  else scope
  end
end
```

#### 4.2 Budget Methods

```ruby
# Returns or builds the associated TenantBudget
def llm_budget
  super || build_llm_budget(tenant_id: llm_tenant_id)
end

# Configure budget with block
def llm_configure_budget(&block)
  budget = llm_budget
  yield(budget) if block_given?
  budget.save!
  budget
end

# Quick status check
def llm_budget_status
  BudgetTracker.status(tenant_id: llm_tenant_id)
end

# Budget check
def llm_within_budget?(type: :daily)
  status = llm_budget_status
  return true unless status[:enabled]

  case type
  when :daily
    status.dig(:global_daily, :percentage_used).to_f < 100
  when :monthly
    status.dig(:global_monthly, :percentage_used).to_f < 100
  else
    true
  end
end

# Remaining budget
def llm_remaining_budget(type: :daily)
  status = llm_budget_status
  case type
  when :daily then status.dig(:global_daily, :remaining)
  when :monthly then status.dig(:global_monthly, :remaining)
  end
end

# Raise if over budget
def llm_check_budget!
  BudgetTracker.check_budget!(self.class.name, tenant_id: llm_tenant_id)
end
```

---

### Phase 5: Callbacks

#### 5.1 Auto-Create Budget

```ruby
after_create :create_default_llm_budget, if: -> {
  self.class.llm_tenant_options[:budget]
}

private

def create_default_llm_budget
  return if llm_budget.persisted?

  options = self.class.llm_tenant_options
  limits = options[:limits] || {}
  name_method = options[:name_method] || :to_s

  llm_budget.assign_attributes(
    tenant_id: llm_tenant_id,
    name: send(name_method),
    daily_limit: limits[:daily_cost],
    monthly_limit: limits[:monthly_cost],
    daily_token_limit: limits[:daily_tokens],
    monthly_token_limit: limits[:monthly_tokens],
    enforcement: options[:enforcement]&.to_s || "soft",
    inherit_global_defaults: options.fetch(:inherit_global, true)
  )

  llm_budget.tenant_record = self
  llm_budget.save!
end
```

---

### Phase 6: Testing

#### 6.1 Unit Tests

**File:** `spec/ruby_llm/agents/llm_tenant_spec.rb`

```ruby
RSpec.describe RubyLLM::Agents::LLMTenant do
  describe ".llm_tenant" do
    it "adds llm_executions association"
    it "adds llm_budget association"
    it "stores options in class attribute"

    context "with budget: true" do
      it "creates budget on model creation"
    end

    context "with limits:" do
      it "implies budget: true"
      it "applies limits to created budget"
    end
  end

  describe "#llm_tenant_id" do
    context "with default key" do
      it "returns id.to_s"
    end

    context "with custom key" do
      it "calls the specified method"
    end
  end

  describe "#llm_budget" do
    it "returns existing budget"
    it "builds new budget if none exists"
  end

  describe "#llm_within_budget?" do
    it "returns true when under limit"
    it "returns false when over limit"
    it "returns true when budgets disabled"
  end
end
```

#### 6.2 Agent Integration Tests

**File:** `spec/ruby_llm/agents/agent_tenant_spec.rb`

```ruby
RSpec.describe "Agent tenant integration" do
  describe "#resolved_tenant" do
    it "accepts tenant: param"
    it "returns nil when no tenant passed"
    it "raises when tenant is a string"
    it "raises when tenant doesn't respond to llm_tenant_id"

    context "with custom tenant method" do
      it "uses the method override"
    end
  end
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── llm_tenant.rb                 # Main concern
├── llm_tenant/
│   ├── class_methods.rb          # llm_tenant macro
│   ├── instance_methods.rb       # llm_cost, llm_tokens, etc.
│   ├── budget_methods.rb         # llm_budget, llm_within_budget?, etc.
│   └── callbacks.rb              # after_create hooks
└── tenant_budget.rb              # Updated model (existing)

spec/ruby_llm/agents/
├── llm_tenant_spec.rb
├── agent_tenant_spec.rb
└── integration/
    └── tenant_integration_spec.rb
```

---

## Migration Path

### For New Users

```ruby
class Organization < ApplicationRecord
  # Simple - just tracking
  llm_tenant

  # With budget auto-creation
  llm_tenant budget: true

  # With limits (auto-creates budget)
  llm_tenant limits: { daily_cost: 100, monthly_cost: 1000 }
end

# Usage
ChatAgent.call("Hello", tenant: organization)
```

### For Existing Users

```ruby
# Add DSL (no breaking changes)
class Organization < ApplicationRecord
  llm_tenant key: :id  # matches existing tenant_id format
end

# Existing TenantBudget records continue to work
# Optional: run migration to link records
Organization.find_each do |org|
  budget = TenantBudget.find_by(tenant_id: org.id.to_s)
  budget&.update(tenant_record: org)
end
```

---

## API Reference (Final)

### Class Method

```ruby
llm_tenant(
  key: :id,                # Method for tenant_id string
  budget: false,           # Auto-create budget on model creation
  limits: nil,             # Default limits (implies budget: true)
  enforcement: :soft,      # :none, :soft, or :hard
  name_method: :to_s,      # Method for budget display name
  inherit_global: true     # Inherit from global config
)

# Limits hash
limits: {
  daily_cost: 100.0,       # Daily cost limit (USD)
  monthly_cost: 1000.0,    # Monthly cost limit (USD)
  daily_tokens: 1_000_000, # Daily token limit
  monthly_tokens: 10_000_000
}
```

### Instance Methods

```ruby
# Tenant ID
model.llm_tenant_id                   # => "123" (string)

# Cost queries
model.llm_cost(period: :today)        # => 12.34
model.llm_cost_today                  # => 12.34
model.llm_cost_this_month             # => 456.78

# Token queries
model.llm_tokens(period: :today)      # => 5000
model.llm_tokens_today                # => 5000
model.llm_tokens_this_month           # => 150000

# Execution queries
model.llm_executions                  # => ActiveRecord::Relation
model.llm_execution_count(period:)    # => 42

# Summary
model.llm_usage_summary               # => { cost: 12.34, tokens: 5000, ... }

# Budget management
model.llm_budget                      # => TenantBudget instance
model.llm_configure_budget { |b| }    # Configure with block
model.llm_budget_status               # => { enabled: true, ... }

# Budget checks
model.llm_within_budget?              # => true/false
model.llm_within_budget?(type: :monthly)
model.llm_remaining_budget            # => 45.67
model.llm_remaining_budget(type: :monthly)
model.llm_check_budget!               # Raises if over budget
```

### Agent Usage

```ruby
# Pass tenant object (must respond to llm_tenant_id)
ChatAgent.call("Hello", tenant: organization)

# No tenant (optional)
ChatAgent.call("Hello")

# Custom resolution in agent
class MyAgent < RubyLLM::Agent
  def tenant
    params[:user].organization
  end
end
```

---

## Open Questions

1. **Should `tenant:` be required or optional?**
   - Current plan: Optional (nil allowed)
   - Alternative: Required with explicit `tenant: nil` to skip

2. **Validation on limits?**
   - Should we validate daily < monthly?
   - Should we warn on very low limits?

3. **Execution association name?**
   - `llm_executions` or `llm_agent_executions`?

---

## Next Steps

1. [ ] Review and approve plan
2. [ ] Create migration for polymorphic association on TenantBudget
3. [ ] Create migration for polymorphic association on Execution (tenant_record)
4. [ ] Implement `LLMTenant` concern
5. [ ] Update Agent base class for `tenant:` param
6. [ ] Update `TenantBudget` model
7. [ ] Write tests
8. [ ] Update documentation
9. [ ] Add to CHANGELOG
