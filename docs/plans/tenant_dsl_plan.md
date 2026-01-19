# Tenant DSL Implementation Plan

## Overview

Add a declarative DSL that allows Rails models to declare themselves as AI tenants with automatic budget management, reducing boilerplate and improving developer experience.

---

## Goals

1. **Declarative syntax** - `acts_as_ai_tenant` macro for models
2. **Automatic budget creation** - Optional auto-create on model creation
3. **Block configuration** - `ai_configure_budget { |b| ... }` syntax
4. **Backward compatible** - String-based `tenant_id` still works
5. **Rails conventions** - Follows familiar patterns (like `has_many`, `acts_as_*`)

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

# Manual context passing
ChatAgent.call(prompt, tenant_id: "acme_corp")
```

---

## Target State

```ruby
# Model declaration
class Organization < ApplicationRecord
  acts_as_ai_tenant(
    auto_create_budget: true,
    tenant_id_method: :slug,
    default_limits: {
      daily_cost: 100.0,
      monthly_cost: 1000.0,
      enforcement: "soft"
    }
  )
end

# Block configuration
org.ai_configure_budget do |budget|
  budget.daily_limit = 50.0
  budget.enforcement = "hard"
end

# Automatic context (with controller helpers)
ChatAgent.call(prompt, tenant_id: org.ai_tenant_id)
```

---

## Implementation Tasks

### Phase 1: Core DSL Module

#### 1.1 Create TenantDSL Concern

**File:** `lib/ruby_llm/agents/tenant_dsl.rb`

```ruby
module RubyLLM
  module Agents
    module TenantDSL
      extend ActiveSupport::Concern

      class_methods do
        def acts_as_ai_tenant(options = {})
          # Store options
          # Set up association
          # Add callbacks
          # Include instance methods
        end
      end

      module InstanceMethods
        def ai_tenant_id
        def ai_budget
        def ai_configure_budget(&block)
        def ai_budget_status
        def ai_within_budget?
      end
    end
  end
end
```

#### 1.2 Options Supported

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auto_create_budget` | Boolean | `false` | Create TenantBudget on model creation |
| `tenant_id_method` | Symbol | `:id` | Method to call for tenant_id string |
| `name_method` | Symbol | `:to_s` | Method to call for budget display name |
| `budget_association` | Symbol | `:ai_budget` | Name of the association |
| `default_limits` | Hash | `{}` | Default budget limits |
| `inherit_global` | Boolean | `true` | Inherit from global config |
| `sync_name` | Boolean | `false` | Sync name when model updates |

#### 1.3 Default Limits Hash Structure

```ruby
default_limits: {
  daily_cost: 100.0,           # daily_limit column
  monthly_cost: 1000.0,        # monthly_limit column
  daily_tokens: 1_000_000,     # daily_token_limit column
  monthly_tokens: 10_000_000,  # monthly_token_limit column
  enforcement: "soft",         # enforcement column
  per_agent_daily: {},         # per_agent_daily JSON
  per_agent_monthly: {}        # per_agent_monthly JSON
}
```

---

### Phase 2: TenantBudget Model Updates

#### 2.1 Add Polymorphic Association (Optional)

**Migration:** `add_tenant_record_to_tenant_budgets.rb`

```ruby
add_reference :ruby_llm_agents_tenant_budgets, :tenant_record,
              polymorphic: true,
              index: true,
              null: true
```

This allows:
- `tenant_budget.tenant_record` → returns Organization, Account, etc.
- Keep `tenant_id` string for backward compatibility
- Either can be used

#### 2.2 Update TenantBudget Model

**File:** `app/models/ruby_llm/agents/tenant_budget.rb`

Add:
- `belongs_to :tenant_record, polymorphic: true, optional: true`
- Update `for_tenant` to accept model or string
- Add `for_tenant!` that creates if not found
- Add helper methods for DSL

---

### Phase 3: Instance Methods

#### 3.1 Core Methods

```ruby
# Returns the tenant_id string (for BudgetTracker compatibility)
def ai_tenant_id
  # Uses tenant_id_method option or falls back to id.to_s
end

# Returns or builds the associated TenantBudget
def ai_budget
  # Returns existing or builds new (unsaved)
end

# Configure budget with block
def ai_configure_budget(&block)
  # Yields budget, saves after block
end

# Quick status check
def ai_budget_status
  # Returns BudgetTracker.status hash
end

# Budget check
def ai_within_budget?(type: :daily)
  # Returns boolean
end

# Remaining budget
def ai_remaining_budget(type: :daily)
  # Returns numeric or nil
end
```

#### 3.2 Delegation Methods

```ruby
# Delegate to ai_budget for convenience
delegate :effective_daily_limit,
         :effective_monthly_limit,
         :effective_daily_token_limit,
         :effective_monthly_token_limit,
         :budgets_enabled?,
         :effective_enforcement,
         to: :ai_budget,
         allow_nil: true
```

---

### Phase 4: Callbacks

#### 4.1 After Create Callback

```ruby
after_create :create_default_ai_budget, if: -> {
  ai_tenant_options[:auto_create_budget]
}

private

def create_default_ai_budget
  return if ai_budget.persisted?

  defaults = ai_tenant_options[:default_limits] || {}
  name_method = ai_tenant_options[:name_method] || :to_s

  ai_budget.assign_attributes(
    tenant_id: ai_tenant_id,
    name: send(name_method),  # Defaults to to_s, configurable via name_method option
    daily_limit: defaults[:daily_cost],
    monthly_limit: defaults[:monthly_cost],
    daily_token_limit: defaults[:daily_tokens],
    monthly_token_limit: defaults[:monthly_tokens],
    enforcement: defaults[:enforcement] || "soft",
    per_agent_daily: defaults[:per_agent_daily] || {},
    per_agent_monthly: defaults[:per_agent_monthly] || {},
    inherit_global_defaults: ai_tenant_options.fetch(:inherit_global, true)
  )

  ai_budget.tenant_record = self if ai_budget.respond_to?(:tenant_record=)
  ai_budget.save!
end
```

> **Note:** The `name` field defaults to the tenant model's `to_s` method. This follows Rails conventions and works with any model. Override `to_s` in your model to customize the display name.

#### 4.2 After Update Callback (Optional)

```ruby
# Sync name changes when model's display name would change
after_update :sync_ai_budget_name, if: -> {
  ai_tenant_options[:sync_name]
}

def sync_ai_budget_name
  name_method = ai_tenant_options[:name_method] || :to_s
  current_name = send(name_method)
  ai_budget&.update(name: current_name) if ai_budget&.name != current_name
end
```

> **Convention:** Models should define `to_s` for display purposes:
> ```ruby
> class Organization < ApplicationRecord
>   def to_s
>     name || "Organization ##{id}"
>   end
> end
> ```

---

### Phase 5: Plan/Tier Support (Optional Enhancement)

#### 5.1 Plan-Based Defaults

```ruby
class Organization < ApplicationRecord
  acts_as_ai_tenant(
    auto_create_budget: true,
    default_limits: -> { plan_based_limits }
  )

  belongs_to :plan

  private

  def plan_based_limits
    case plan&.name
    when "free"
      { daily_cost: 1.0, monthly_cost: 10.0, enforcement: "hard" }
    when "starter"
      { daily_cost: 10.0, monthly_cost: 100.0, enforcement: "soft" }
    when "pro"
      { daily_cost: 50.0, monthly_cost: 500.0, enforcement: "soft" }
    when "enterprise"
      { daily_cost: nil, monthly_cost: nil, enforcement: "none" }
    else
      {}
    end
  end
end
```

#### 5.2 Plan Change Hook

```ruby
# When plan changes, optionally update budget
after_update :apply_plan_limits, if: :saved_change_to_plan_id?

def apply_plan_limits
  ai_configure_budget do |budget|
    limits = plan_based_limits
    budget.daily_limit = limits[:daily_cost]
    budget.monthly_limit = limits[:monthly_cost]
    budget.enforcement = limits[:enforcement]
  end
end
```

---

### Phase 6: Testing

#### 6.1 Unit Tests

**File:** `spec/ruby_llm/agents/tenant_dsl_spec.rb`

```ruby
RSpec.describe RubyLLM::Agents::TenantDSL do
  describe ".acts_as_ai_tenant" do
    it "adds ai_budget association"
    it "stores options in class attribute"
    it "includes instance methods"
  end

  describe "#ai_tenant_id" do
    context "with default" do
      it "returns id.to_s"
    end

    context "with custom method" do
      it "calls the specified method"
    end
  end

  describe "#ai_budget" do
    it "returns existing budget"
    it "builds new budget if none exists"
  end

  describe "#ai_configure_budget" do
    it "yields budget to block"
    it "saves after block"
    it "creates if not exists"
  end

  describe "auto_create_budget" do
    it "creates budget on model creation when enabled"
    it "does not create when disabled"
    it "applies default limits"
  end
end
```

#### 6.2 Integration Tests

**File:** `spec/integration/tenant_dsl_integration_spec.rb`

```ruby
RSpec.describe "Tenant DSL Integration" do
  it "works end-to-end with agent execution"
  it "respects budget limits"
  it "tracks usage per tenant"
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── tenant_dsl.rb                 # Main DSL module
├── tenant_dsl/
│   ├── class_methods.rb          # acts_as_ai_tenant macro
│   ├── instance_methods.rb       # ai_budget, ai_configure_budget, etc.
│   └── callbacks.rb              # after_create, after_update hooks
└── tenant_budget.rb              # Updated model (existing)

spec/ruby_llm/agents/
├── tenant_dsl_spec.rb
└── tenant_dsl/
    ├── class_methods_spec.rb
    ├── instance_methods_spec.rb
    └── callbacks_spec.rb
```

---

## Migration Path

### For New Users

```ruby
# Just add to model
class Organization < ApplicationRecord
  acts_as_ai_tenant auto_create_budget: true
end

# That's it! Budget created automatically
```

### For Existing Users

```ruby
# Add DSL (no breaking changes)
class Organization < ApplicationRecord
  acts_as_ai_tenant(
    tenant_id_method: :id  # matches existing tenant_id format
  )
end

# Existing TenantBudget records continue to work
# Optional: run migration to link records
Organization.find_each do |org|
  budget = TenantBudget.find_by(tenant_id: org.id.to_s)
  budget&.update(tenant_record: org)
end
```

---

## Conventions

### Model `to_s` for Budget Name

The `TenantBudget.name` field automatically uses the tenant model's `to_s` method. This is the Rails-idiomatic way to get a human-readable representation.

```ruby
class Organization < ApplicationRecord
  acts_as_ai_tenant auto_create_budget: true

  def to_s
    name || "Org ##{id}"
  end
end

class Account < ApplicationRecord
  acts_as_ai_tenant auto_create_budget: true

  def to_s
    company_name.presence || email
  end
end

# Results
org.ai_budget.name      # => "Acme Corporation" (from org.to_s)
account.ai_budget.name  # => "john@example.com" (from account.to_s)
```

**Why `to_s` instead of `name` attribute?**
- Not all models have a `name` column
- `to_s` is a Ruby/Rails convention
- Each model controls its own display logic
- Works with composite names (e.g., `"#{first_name} #{last_name}"`)

---

## API Reference (Final)

### Class Methods

```ruby
acts_as_ai_tenant(
  auto_create_budget: false,      # Auto-create on model creation
  tenant_id_method: :id,          # Method for tenant_id string
  name_method: :to_s,             # Method for budget display name (default: to_s)
  budget_association: :ai_budget, # Association name
  inherit_global: true,           # Inherit global defaults
  sync_name: false,               # Sync name when model updates
  default_limits: {               # Default budget values
    daily_cost: nil,
    monthly_cost: nil,
    daily_tokens: nil,
    monthly_tokens: nil,
    enforcement: "soft",
    per_agent_daily: {},
    per_agent_monthly: {}
  }
)
```

### Instance Methods

```ruby
org.ai_tenant_id                  # => "123" (string for BudgetTracker)
org.ai_budget                     # => TenantBudget instance
org.ai_configure_budget { |b| }   # Configure with block
org.ai_budget_status              # => { enabled: true, ... }
org.ai_within_budget?             # => true/false
org.ai_remaining_budget(:daily)   # => 45.67

# Delegated from ai_budget
org.effective_daily_limit         # => 100.0
org.effective_monthly_limit       # => 1000.0
org.budgets_enabled?              # => true
```

---

## Timeline Estimate

| Phase | Description | Effort |
|-------|-------------|--------|
| 1 | Core DSL Module | 2-3 hours |
| 2 | TenantBudget Updates | 1-2 hours |
| 3 | Instance Methods | 1-2 hours |
| 4 | Callbacks | 1 hour |
| 5 | Plan Support (optional) | 1-2 hours |
| 6 | Testing | 2-3 hours |
| **Total** | | **8-13 hours** |

---

## Open Questions

1. **Polymorphic vs Foreign Key?**
   - Polymorphic allows any model to be a tenant
   - Foreign key is simpler if only one model type

2. **Keep `tenant_id` string or deprecate?**
   - Recommend: Keep for backward compatibility
   - New users can ignore it

3. **Auto-sync on plan change?**
   - Could be opt-in via `sync_on_plan_change: true`

4. **Validation on limits?**
   - Should we validate daily < monthly?
   - Should we warn on very low limits?

---

## Next Steps

1. [ ] Review and approve plan
2. [ ] Create migration for polymorphic (if approved)
3. [ ] Implement Phase 1 (Core DSL)
4. [ ] Implement Phase 2-4
5. [ ] Write tests
6. [ ] Update documentation
7. [ ] Add to CHANGELOG
