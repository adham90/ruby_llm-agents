# Tenant DSL Implementation Plan

## Overview

Add a declarative DSL that allows Rails models to declare themselves as LLM tenants with automatic budget management and usage tracking, reducing boilerplate and improving developer experience.

---

## Goals

1. **Declarative syntax** - `has_llm_budget` and `tracks_llm_usage` macros for models
2. **Automatic budget creation** - Optional auto-create on model creation
3. **Block configuration** - `llm_configure_budget { |b| ... }` syntax
4. **Backward compatible** - String-based `tenant_id` still works
5. **Rails conventions** - Follows familiar patterns (like `has_many`, `has_one`)
6. **Composable** - `tracks_llm_usage` for tracking only, `has_llm_budget` includes tracking + budgets

---

## Naming Convention

| Macro | Purpose | Includes |
|-------|---------|----------|
| `tracks_llm_usage` | Usage tracking only | Executions, costs, tokens |
| `has_llm_budget` | Tracking + Budget management | Everything from `tracks_llm_usage` + budget |

**Method prefix:** `llm_` (e.g., `llm_budget`, `llm_cost_today`, `llm_within_budget?`)

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
# Tracking only (no budget limits)
class Conversation < ApplicationRecord
  tracks_llm_usage
end

conversation.llm_cost_today        # => 0.23
conversation.llm_tokens_this_month # => 45000
conversation.llm_executions        # => ActiveRecord::Relation

# Tracking + Budget management
class Organization < ApplicationRecord
  has_llm_budget(
    auto_create: true,
    tenant_id_method: :slug,
    default_limits: {
      daily_cost: 100.0,
      monthly_cost: 1000.0,
      enforcement: "soft"
    }
  )
end

# Block configuration
org.llm_configure_budget do |budget|
  budget.daily_limit = 50.0
  budget.enforcement = "hard"
end

# Automatic context (with controller helpers)
ChatAgent.call(prompt, tenant_id: org.llm_tenant_id)

# Budget checks
org.llm_within_budget?      # => true
org.llm_remaining_budget    # => 45.67
```

---

## Implementation Tasks

### Phase 1: Core DSL Modules

#### 1.1 Create TracksLLMUsage Concern (Base)

**File:** `lib/ruby_llm/agents/tracks_llm_usage.rb`

```ruby
module RubyLLM
  module Agents
    module TracksLLMUsage
      extend ActiveSupport::Concern

      included do
        has_many :llm_executions,
                 class_name: "RubyLLM::Agents::Execution",
                 as: :trackable,
                 dependent: :nullify
      end

      # Instance methods for tracking
      def llm_tenant_id
      def llm_cost(period:)
      def llm_cost_today
      def llm_cost_this_month
      def llm_tokens(period:)
      def llm_tokens_today
      def llm_tokens_this_month
      def llm_execution_count(period:)
      def llm_usage_summary(period:)
    end
  end
end
```

#### 1.2 Create HasLLMBudget Concern (Extended)

**File:** `lib/ruby_llm/agents/has_llm_budget.rb`

```ruby
module RubyLLM
  module Agents
    module HasLLMBudget
      extend ActiveSupport::Concern

      included do
        include TracksLLMUsage  # Includes all tracking methods

        has_one :llm_budget,
                class_name: "RubyLLM::Agents::TenantBudget",
                as: :tenant_record,
                dependent: :destroy
      end

      class_methods do
        def has_llm_budget(options = {})
          # Store options
          # Set up callbacks
          # Configure defaults
        end
      end

      # Budget-specific instance methods
      def llm_budget
      def llm_configure_budget(&block)
      def llm_budget_status
      def llm_within_budget?(type: :daily)
      def llm_remaining_budget(type: :daily)
      def llm_check_budget!
    end
  end
end
```

#### 1.3 Options Supported

**For `tracks_llm_usage`:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tenant_id_method` | Symbol | `:id` | Method to call for tenant_id string |
| `association_name` | Symbol | `:llm_executions` | Name of the executions association |

**For `has_llm_budget`:** (includes all above plus)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auto_create` | Boolean | `false` | Create TenantBudget on model creation |
| `name_method` | Symbol | `:to_s` | Method to call for budget display name |
| `default_limits` | Hash | `{}` | Default budget limits |
| `inherit_global` | Boolean | `true` | Inherit from global config |
| `sync_name` | Boolean | `false` | Sync name when model updates |

#### 1.4 Default Limits Hash Structure

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

#### 2.1 Add Polymorphic Association

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

#### 3.1 Tracking Methods (TracksLLMUsage)

```ruby
# Returns the tenant_id string (for BudgetTracker compatibility)
def llm_tenant_id
  method = self.class.llm_tracking_options[:tenant_id_method] || :id
  send(method).to_s
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

#### 3.2 Budget Methods (HasLLMBudget)

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

#### 3.3 Delegation Methods

```ruby
# Delegate to llm_budget for convenience
delegate :effective_daily_limit,
         :effective_monthly_limit,
         :effective_daily_token_limit,
         :effective_monthly_token_limit,
         :budgets_enabled?,
         :effective_enforcement,
         to: :llm_budget,
         allow_nil: true,
         prefix: false
```

---

### Phase 4: Callbacks

#### 4.1 After Create Callback

```ruby
after_create :create_default_llm_budget, if: -> {
  self.class.llm_budget_options[:auto_create]
}

private

def create_default_llm_budget
  return if llm_budget.persisted?

  options = self.class.llm_budget_options
  defaults = options[:default_limits] || {}
  name_method = options[:name_method] || :to_s

  llm_budget.assign_attributes(
    tenant_id: llm_tenant_id,
    name: send(name_method),  # Defaults to to_s
    daily_limit: defaults[:daily_cost],
    monthly_limit: defaults[:monthly_cost],
    daily_token_limit: defaults[:daily_tokens],
    monthly_token_limit: defaults[:monthly_tokens],
    enforcement: defaults[:enforcement] || "soft",
    per_agent_daily: defaults[:per_agent_daily] || {},
    per_agent_monthly: defaults[:per_agent_monthly] || {},
    inherit_global_defaults: options.fetch(:inherit_global, true)
  )

  llm_budget.tenant_record = self
  llm_budget.save!
end
```

> **Note:** The `name` field defaults to the tenant model's `to_s` method. This follows Rails conventions and works with any model. Override `to_s` in your model to customize the display name.

#### 4.2 After Update Callback (Optional)

```ruby
# Sync name changes when model's display name would change
after_update :sync_llm_budget_name, if: -> {
  self.class.llm_budget_options[:sync_name]
}

def sync_llm_budget_name
  name_method = self.class.llm_budget_options[:name_method] || :to_s
  current_name = send(name_method)
  llm_budget&.update(name: current_name) if llm_budget&.name != current_name
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
  has_llm_budget(
    auto_create: true,
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
  llm_configure_budget do |budget|
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

**File:** `spec/ruby_llm/agents/tracks_llm_usage_spec.rb`

```ruby
RSpec.describe RubyLLM::Agents::TracksLLMUsage do
  describe ".tracks_llm_usage" do
    it "adds llm_executions association"
    it "stores options in class attribute"
    it "includes instance methods"
  end

  describe "#llm_tenant_id" do
    context "with default" do
      it "returns id.to_s"
    end

    context "with custom method" do
      it "calls the specified method"
    end
  end

  describe "#llm_cost" do
    it "returns total cost for period"
    it "returns 0 when no executions"
  end

  describe "#llm_usage_summary" do
    it "returns summary hash"
  end
end
```

**File:** `spec/ruby_llm/agents/has_llm_budget_spec.rb`

```ruby
RSpec.describe RubyLLM::Agents::HasLLMBudget do
  describe ".has_llm_budget" do
    it "includes TracksLLMUsage"
    it "adds llm_budget association"
    it "stores options in class attribute"
  end

  describe "#llm_budget" do
    it "returns existing budget"
    it "builds new budget if none exists"
  end

  describe "#llm_configure_budget" do
    it "yields budget to block"
    it "saves after block"
    it "creates if not exists"
  end

  describe "#llm_within_budget?" do
    it "returns true when under limit"
    it "returns false when over limit"
    it "returns true when budgets disabled"
  end

  describe "auto_create" do
    it "creates budget on model creation when enabled"
    it "does not create when disabled"
    it "applies default limits"
    it "uses to_s for name by default"
  end
end
```

#### 6.2 Integration Tests

**File:** `spec/integration/llm_tracking_integration_spec.rb`

```ruby
RSpec.describe "LLM Tracking Integration" do
  it "tracks executions for trackable models"
  it "works end-to-end with agent execution"
  it "respects budget limits"
  it "tracks usage per tenant"
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── tracks_llm_usage.rb           # Base tracking concern
├── has_llm_budget.rb             # Extended budget concern
├── tracks_llm_usage/
│   └── instance_methods.rb       # llm_cost, llm_tokens, etc.
├── has_llm_budget/
│   ├── class_methods.rb          # has_llm_budget macro
│   ├── instance_methods.rb       # llm_budget, llm_configure_budget, etc.
│   └── callbacks.rb              # after_create, after_update hooks
└── tenant_budget.rb              # Updated model (existing)

spec/ruby_llm/agents/
├── tracks_llm_usage_spec.rb
├── has_llm_budget_spec.rb
└── integration/
    └── llm_tracking_integration_spec.rb
```

---

## Migration Path

### For New Users

```ruby
# Tracking only
class Conversation < ApplicationRecord
  tracks_llm_usage
end

# Tracking + Budget
class Organization < ApplicationRecord
  has_llm_budget auto_create: true
end

# That's it! Budget created automatically
```

### For Existing Users

```ruby
# Add DSL (no breaking changes)
class Organization < ApplicationRecord
  has_llm_budget(
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
  has_llm_budget auto_create: true

  def to_s
    name || "Org ##{id}"
  end
end

class Account < ApplicationRecord
  has_llm_budget auto_create: true

  def to_s
    company_name.presence || email
  end
end

# Results
org.llm_budget.name      # => "Acme Corporation" (from org.to_s)
account.llm_budget.name  # => "john@example.com" (from account.to_s)
```

**Why `to_s` instead of `name` attribute?**
- Not all models have a `name` column
- `to_s` is a Ruby/Rails convention
- Each model controls its own display logic
- Works with composite names (e.g., `"#{first_name} #{last_name}"`)

---

## API Reference (Final)

### Class Methods

#### `tracks_llm_usage`

```ruby
tracks_llm_usage(
  tenant_id_method: :id,              # Method for tenant_id string
  association_name: :llm_executions   # Name of executions association
)
```

#### `has_llm_budget`

```ruby
has_llm_budget(
  # Inherited from tracks_llm_usage
  tenant_id_method: :id,              # Method for tenant_id string

  # Budget-specific options
  auto_create: false,                 # Auto-create on model creation
  name_method: :to_s,                 # Method for budget display name
  inherit_global: true,               # Inherit global defaults
  sync_name: false,                   # Sync name when model updates
  default_limits: {                   # Default budget values
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

#### From `tracks_llm_usage`

```ruby
# Tenant ID
model.llm_tenant_id                   # => "123" (string for BudgetTracker)

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
```

#### From `has_llm_budget` (additional)

```ruby
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

# Delegated from llm_budget
model.effective_daily_limit           # => 100.0
model.effective_monthly_limit         # => 1000.0
model.budgets_enabled?                # => true
```

---

## Method Summary Table

| Method | `tracks_llm_usage` | `has_llm_budget` |
|--------|:------------------:|:----------------:|
| `llm_tenant_id` | ✅ | ✅ |
| `llm_executions` | ✅ | ✅ |
| `llm_cost` / `llm_cost_today` | ✅ | ✅ |
| `llm_tokens` / `llm_tokens_today` | ✅ | ✅ |
| `llm_execution_count` | ✅ | ✅ |
| `llm_usage_summary` | ✅ | ✅ |
| `llm_budget` | ❌ | ✅ |
| `llm_configure_budget` | ❌ | ✅ |
| `llm_budget_status` | ❌ | ✅ |
| `llm_within_budget?` | ❌ | ✅ |
| `llm_remaining_budget` | ❌ | ✅ |
| `llm_check_budget!` | ❌ | ✅ |

---

## Timeline Estimate

| Phase | Description | Effort |
|-------|-------------|--------|
| 1 | Core DSL Modules | 3-4 hours |
| 2 | TenantBudget Updates | 1-2 hours |
| 3 | Instance Methods | 2-3 hours |
| 4 | Callbacks | 1 hour |
| 5 | Plan Support (optional) | 1-2 hours |
| 6 | Testing | 2-3 hours |
| **Total** | | **10-15 hours** |

---

## Open Questions

1. **Polymorphic vs Foreign Key?**
   - Polymorphic allows any model to be a tenant
   - Foreign key is simpler if only one model type
   - **Recommendation:** Polymorphic for flexibility

2. **Keep `tenant_id` string or deprecate?**
   - **Recommendation:** Keep for backward compatibility
   - New users can ignore it

3. **Auto-sync on plan change?**
   - Could be opt-in via `sync_on_plan_change: true`

4. **Validation on limits?**
   - Should we validate daily < monthly?
   - Should we warn on very low limits?

---

## Next Steps

1. [ ] Review and approve plan
2. [ ] Create migration for polymorphic association
3. [ ] Implement `TracksLLMUsage` concern
4. [ ] Implement `HasLLMBudget` concern
5. [ ] Update `TenantBudget` model
6. [ ] Write tests
7. [ ] Update documentation
8. [ ] Add to CHANGELOG
