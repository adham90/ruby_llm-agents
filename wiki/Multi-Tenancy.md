# Multi-Tenancy

RubyLLM::Agents supports multi-tenant applications with per-tenant budgets, circuit breaker isolation, and execution tracking.

## Configuration

Enable multi-tenancy in your initializer:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Enable multi-tenancy support
  config.multi_tenancy_enabled = true

  # Define how to resolve the current tenant
  config.tenant_resolver = -> { Current.tenant_id }
end
```

### Tenant Resolver

The `tenant_resolver` is a proc that returns the current tenant identifier. Common patterns:

```ruby
# Using Rails Current attributes
config.tenant_resolver = -> { Current.tenant_id }

# Using RequestStore gem
config.tenant_resolver = -> { RequestStore.store[:tenant_id] }

# Using Apartment gem
config.tenant_resolver = -> { Apartment::Tenant.current }

# Using ActsAsTenant gem
config.tenant_resolver = -> { ActsAsTenant.current_tenant&.id }
```

### Tenant Config Resolver

The optional `tenant_config_resolver` allows you to provide tenant configuration dynamically, overriding database lookups:

```ruby
config.tenant_config_resolver = ->(tenant_id) {
  tenant = Tenant.find(tenant_id)
  {
    name: tenant.name,
    daily_limit: tenant.subscription.daily_budget,
    monthly_limit: tenant.subscription.monthly_budget,
    daily_token_limit: tenant.subscription.daily_tokens,
    monthly_token_limit: tenant.subscription.monthly_tokens,
    enforcement: tenant.subscription.hard_limits? ? :hard : :soft
  }
}
```

This is useful when tenant budgets are managed in a different system or derived from subscription plans.

## Explicit Tenant Override

You can bypass the tenant resolver by passing the tenant explicitly to `.call()`:

```ruby
# Pass tenant_id explicitly (bypasses resolver, uses DB or config_resolver)
MyAgent.call(query: "Analyze this data", tenant: "acme_corp")

# Pass full config as a hash (runtime override, no DB lookup)
MyAgent.call(query: "Analyze this data", tenant: {
  id: "acme_corp",
  daily_limit: 100.0,
  monthly_limit: 1000.0,
  daily_token_limit: 1_000_000,
  monthly_token_limit: 10_000_000,
  enforcement: :hard
})
```

This is useful for:
- Background jobs where `Current.tenant` isn't set
- Cross-tenant operations by admin users
- Testing with specific tenant configurations

## LLMTenant DSL

The `LLMTenant` concern provides a declarative DSL for making ActiveRecord models function as LLM tenants with automatic budget management and usage tracking.

### Including the Concern

```ruby
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  llm_tenant  # Minimal setup
end
```

### DSL Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id:` | Symbol | `:id` | Method to call for tenant_id string |
| `name:` | Symbol | `:to_s` | Method for budget display name |
| `budget:` | Boolean | `false` | Auto-create TenantBudget on model creation |
| `limits:` | Hash | `nil` | Default budget limits (implies `budget: true`) |
| `enforcement:` | Symbol | `nil` | `:none`, `:soft`, or `:hard` |
| `inherit_global:` | Boolean | `true` | Inherit from global config for unset limits |
| `api_keys:` | Hash | `nil` | Provider API key mapping |

### Limits Hash Structure

The `limits:` hash supports cost, token, and execution-based limits:

```ruby
limits: {
  daily_cost: 100.0,           # USD per day
  monthly_cost: 1000.0,        # USD per month
  daily_tokens: 1_000_000,     # Tokens per day
  monthly_tokens: 10_000_000,  # Tokens per month
  daily_executions: 500,       # Agent calls per day
  monthly_executions: 10_000   # Agent calls per month
}
```

### Automatic Associations

When you include `LLMTenant`, the following associations are added:

```ruby
has_many :llm_executions   # All agent executions for this tenant
has_one :llm_budget        # The tenant's budget record
```

### Instance Methods

#### Tenant Identity

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_tenant_id` | String | Tenant identifier (from `id:` DSL option) |
| `llm_api_keys` | Hash | Resolved API keys from `api_keys:` config |

#### Cost Tracking

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_cost(period:)` | BigDecimal | Total cost for the specified period |
| `llm_cost_today` | BigDecimal | Today's cost |
| `llm_cost_this_month` | BigDecimal | This month's cost |

#### Token Tracking

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_tokens(period:)` | Integer | Total tokens for the specified period |
| `llm_tokens_today` | Integer | Today's tokens |
| `llm_tokens_this_month` | Integer | This month's tokens |

#### Execution Counting

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_execution_count(period:)` | Integer | Execution count for the period |
| `llm_executions_today` | Integer | Today's execution count |
| `llm_executions_this_month` | Integer | This month's execution count |

#### Budget Management

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_budget` | TenantBudget | Get or build budget record |
| `llm_configure_budget { }` | TenantBudget | Configure and save budget with block |
| `llm_budget_status` | Hash | Full budget status from BudgetTracker |
| `llm_within_budget?(type:)` | Boolean | Check if within budget for limit type |
| `llm_remaining_budget(type:)` | Numeric | Remaining budget for limit type |
| `llm_check_budget!` | void | Raises `BudgetExceededError` if over hard limit |

#### Usage Summary

| Method | Returns | Description |
|--------|---------|-------------|
| `llm_usage_summary(period:)` | Hash | Combined metrics `{cost:, tokens:, executions:, period:}` |

### Period Options

All period-based methods accept these values:

| Period | Description |
|--------|-------------|
| `:today` | Current day |
| `:yesterday` | Previous day |
| `:this_week` | Current week |
| `:this_month` | Current month |
| `Range` | Custom date/time range (e.g., `2.days.ago..Time.current`) |

### Budget Limit Types

For `llm_within_budget?` and `llm_remaining_budget`:

| Type | Description |
|------|-------------|
| `:daily_cost` | Daily cost limit (default) |
| `:monthly_cost` | Monthly cost limit |
| `:daily_tokens` | Daily token limit |
| `:monthly_tokens` | Monthly token limit |
| `:daily_executions` | Daily execution limit |
| `:monthly_executions` | Monthly execution limit |

### Use Case Examples

#### 1. Minimal Tracking Only

Track executions without budgets:

```ruby
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  llm_tenant id: :slug
end

# Usage
org = Organization.find_by(slug: "acme")
org.llm_cost_this_month        # => 125.50
org.llm_executions_today       # => 42
org.llm_usage_summary(period: :today)
# => { cost: 12.50, tokens: 50000, executions: 42, period: :today }
```

#### 2. Auto-Budget with Global Defaults

Create budgets automatically, inheriting global limits:

```ruby
class Account < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  llm_tenant id: :uuid, name: :company_name, budget: true
end

# Budget auto-created on Account.create, inherits from global config
```

#### 3. Custom Limits with Hard Enforcement

Set specific limits with strict enforcement:

```ruby
class Workspace < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  llm_tenant(
    id: :external_id,
    name: :display_name,
    limits: {
      daily_cost: 50.0,
      monthly_cost: 500.0,
      daily_tokens: 500_000,
      monthly_tokens: 5_000_000,
      daily_executions: 200,
      monthly_executions: 5_000
    },
    enforcement: :hard
  )
end

# Check budget programmatically
workspace = Workspace.find(1)
workspace.llm_within_budget?(type: :daily_cost)  # => true
workspace.llm_remaining_budget(type: :daily_cost) # => 37.50

# This raises BudgetExceededError if over hard limit
workspace.llm_check_budget!
```

#### 4. Full Configuration with API Keys

Complete setup with per-tenant API keys:

```ruby
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  encrypts :openai_api_key, :anthropic_api_key  # Rails 7+ encryption

  llm_tenant(
    id: :slug,
    name: :company_name,
    limits: {
      daily_cost: 100.0,
      monthly_cost: 1000.0,
      daily_tokens: 1_000_000,
      monthly_tokens: 10_000_000
    },
    enforcement: :hard,
    inherit_global: true,
    api_keys: {
      openai: :openai_api_key,
      anthropic: :anthropic_api_key,
      gemini: :fetch_gemini_key
    }
  )

  def fetch_gemini_key
    Vault.read("secret/#{slug}/gemini")
  end
end

# Tenant's API keys are automatically applied
org = Organization.find_by(slug: "acme-corp")
result = MyAgent.call(query: "Hello", tenant: org)
```

#### 5. Programmatic Budget Configuration

Configure budgets dynamically after model creation:

```ruby
org = Organization.find(1)

# Configure with block
org.llm_configure_budget do |budget|
  budget.daily_limit = 75.0
  budget.monthly_limit = 750.0
  budget.daily_execution_limit = 300
  budget.enforcement = "hard"
end

# Or access and modify directly
budget = org.llm_budget
budget.update(monthly_limit: 1000.0)
```

## TenantBudget Model

The `TenantBudget` model stores per-tenant spending limits:

```ruby
# Create a tenant budget
RubyLLM::Agents::TenantBudget.create!(
  tenant_id: "tenant_123",
  name: "Acme Corporation",
  daily_limit: 50.0,
  monthly_limit: 500.0,
  daily_token_limit: 500_000,
  monthly_token_limit: 5_000_000,
  daily_execution_limit: 500,
  monthly_execution_limit: 10_000,
  enforcement: "hard"
)
```

### Schema

| Field | Type | Description |
|-------|------|-------------|
| `tenant_id` | string | Unique tenant identifier |
| `name` | string | Human-readable display name |
| `daily_limit` | decimal | Daily spending limit in USD |
| `monthly_limit` | decimal | Monthly spending limit in USD |
| `daily_token_limit` | integer | Daily token usage limit |
| `monthly_token_limit` | integer | Monthly token usage limit |
| `daily_execution_limit` | integer | Daily agent call limit |
| `monthly_execution_limit` | integer | Monthly agent call limit |
| `enforcement` | string | `"none"`, `"soft"` (warn), or `"hard"` (block) |
| `inherit_global_defaults` | boolean | Fall back to global config for unset limits |

### Managing Tenant Budgets

```ruby
# Find or create with defaults
budget = RubyLLM::Agents::TenantBudget.find_or_create_by(tenant_id: tenant_id) do |b|
  b.name = "Acme Corp"
  b.daily_limit = 25.0
  b.monthly_limit = 250.0
  b.daily_execution_limit = 200
  b.enforcement = "hard"
end

# Update limits
budget.update(daily_limit: 50.0)

# Query effective limits (includes inheritance from global config)
budget.effective_daily_limit           # => 50.0 (cost)
budget.effective_monthly_limit         # => 250.0 (cost)
budget.effective_daily_token_limit     # => 500_000 (tokens)
budget.effective_monthly_token_limit   # => 5_000_000 (tokens)
budget.effective_daily_execution_limit # => 200 (executions)
budget.effective_monthly_execution_limit # => nil (not set)

# Check enforcement mode
budget.effective_enforcement  # => :hard
budget.budgets_enabled?       # => true

# Get display name
budget.display_name  # => "Acme Corp" (or tenant_id if name not set)

# Convert to budget config hash (used by BudgetTracker)
budget.to_budget_config
# => { enabled: true, enforcement: :hard, global_daily: 50.0, ... }
```

### Finding Budgets

```ruby
# By tenant_id string
budget = RubyLLM::Agents::TenantBudget.for_tenant("tenant_123")

# By tenant object (uses polymorphic association or llm_tenant_id)
budget = RubyLLM::Agents::TenantBudget.for_tenant(organization)

# Find or create with name
budget = RubyLLM::Agents::TenantBudget.for_tenant!("tenant_123", name: "Acme")
```

## Execution Filtering by Tenant

Filter executions by tenant:

```ruby
# All executions for a specific tenant
RubyLLM::Agents::Execution.by_tenant("tenant_123")

# Executions for the current tenant (uses tenant_resolver)
RubyLLM::Agents::Execution.for_current_tenant

# Executions with tenant_id set
RubyLLM::Agents::Execution.with_tenant

# Executions without tenant_id (global/system executions)
RubyLLM::Agents::Execution.without_tenant
```

### Tenant Analytics

```ruby
# Cost by tenant this month
RubyLLM::Agents::Execution
  .this_month
  .with_tenant
  .group(:tenant_id)
  .sum(:total_cost)
# => { "tenant_a" => 150.00, "tenant_b" => 75.00, ... }

# Execution count by tenant
RubyLLM::Agents::Execution
  .this_week
  .with_tenant
  .group(:tenant_id)
  .count
# => { "tenant_a" => 1250, "tenant_b" => 890, ... }

# Top spending tenants
RubyLLM::Agents::Execution
  .this_month
  .with_tenant
  .group(:tenant_id)
  .sum(:total_cost)
  .sort_by { |_, cost| -cost }
  .first(10)
```

## Circuit Breaker Isolation

When multi-tenancy is enabled, circuit breakers are isolated per tenant. This prevents one tenant's failures from affecting other tenants.

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"
  circuit_breaker errors: 10, within: 60, cooldown: 300
end
```

With multi-tenancy enabled:
- Tenant A's errors only affect Tenant A's circuit breaker
- Tenant B can continue operating even if Tenant A's circuit is open
- Each tenant has their own error count and cooldown state

### Checking Circuit Breaker State

```ruby
# Check if circuit is open for current tenant
RubyLLM::Agents::CircuitBreaker.open_for?(
  agent: MyAgent,
  tenant_id: Current.tenant_id
)

# Check for specific tenant
RubyLLM::Agents::CircuitBreaker.open_for?(
  agent: MyAgent,
  tenant_id: "tenant_123"
)
```

## Adding Custom Tenant Metadata

Include tenant information in execution metadata:

```ruby
class TenantAwareAgent < ApplicationAgent
  model "gpt-4o"

  def execution_metadata
    {
      tenant_id: Current.tenant_id,
      tenant_name: Current.tenant&.name,
      tenant_plan: Current.tenant&.plan
    }
  end
end
```

## Budget Enforcement

With multi-tenancy enabled, budget checks happen at both global and tenant levels. Limits can be set for costs, tokens, and executions:

```ruby
# Global limits (all tenants combined)
config.budgets = {
  global_daily: 1000.0,
  global_monthly: 20000.0,
  global_daily_tokens: 10_000_000,
  global_monthly_tokens: 100_000_000,
  global_daily_executions: 5000,
  global_monthly_executions: 100_000
}

# Per-tenant limits (via TenantBudget model)
RubyLLM::Agents::TenantBudget.create!(
  tenant_id: "tenant_123",
  daily_limit: 50.0,
  monthly_limit: 500.0,
  daily_token_limit: 500_000,
  monthly_token_limit: 5_000_000,
  daily_execution_limit: 200,
  monthly_execution_limit: 5000,
  enforcement: "hard"
)
```

Execution is blocked if **any** limit is exceeded (when using `"hard"` enforcement). With `"soft"` enforcement, warnings are logged but execution continues.

### Handling Tenant Budget Errors

```ruby
begin
  result = MyAgent.call(query: params[:query])
rescue RubyLLM::Agents::BudgetExceededError => e
  if e.tenant_budget?
    # Tenant-specific budget exceeded
    render json: { error: "Your organization has exceeded its daily limit" }
  else
    # Global budget exceeded
    render json: { error: "Service temporarily unavailable" }
  end
end
```

## Dashboard Integration

The dashboard automatically shows:
- Spending breakdown by tenant (when multi-tenancy enabled)
- Tenant budget status and utilization
- Per-tenant execution filtering

Filter executions by tenant in the dashboard URL:
```
/agents/executions?tenant_id=tenant_123
```

## Tenant API Keys

Each tenant can have their own API keys stored on the model and resolved at runtime via the `api_keys:` option in the `llm_tenant` DSL.

### Configuration

```ruby
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  # Encrypt API keys at rest (Rails 7+)
  encrypts :openai_api_key, :anthropic_api_key

  llm_tenant(
    id: :slug,
    name: :company_name,
    api_keys: {
      openai: :openai_api_key,        # Column name
      anthropic: :anthropic_api_key,  # Column name
      gemini: :fetch_gemini_key       # Custom method
    }
  )

  # Custom method to fetch from external source
  def fetch_gemini_key
    Vault.read("secret/#{slug}/gemini")
  end
end
```

### API Key Resolution Priority

When an agent executes, API keys are resolved in this order:

1. **Tenant object `api_keys:`** → DSL-defined methods/columns (highest priority)
2. **Runtime hash `api_keys:`** → Passed via `tenant: { id: ..., api_keys: {...} }`
3. **ApiConfiguration.for_tenant** → Database per-tenant config
4. **ApiConfiguration.global** → Database global config
5. **RubyLLM.configure** → Config file/environment (lowest priority)

### Usage

```ruby
# Tenant's API keys are automatically applied when agent executes
org = Organization.find_by(slug: "acme-corp")
result = MyAgent.call(query: "Hello", tenant: org)
# Uses org.openai_api_key for OpenAI requests

# Runtime hash also supports api_keys
result = MyAgent.call(
  query: "Hello",
  tenant: {
    id: "acme-corp",
    api_keys: {
      openai: "sk-runtime-key-123"
    }
  }
)
```

### Supported Providers

The `api_keys:` hash maps provider names to RubyLLM config setters:

| Key | RubyLLM Setter |
|-----|----------------|
| `openai:` | `openai_api_key=` |
| `anthropic:` | `anthropic_api_key=` |
| `gemini:` | `gemini_api_key=` |
| `deepseek:` | `deepseek_api_key=` |
| `mistral:` | `mistral_api_key=` |

### Security Considerations

- **Always encrypt API keys** - Use `encrypts` (Rails 7+) or `attr_encrypted`
- **Avoid logging** - Ensure API keys aren't exposed in logs
- **Rotate regularly** - Allow tenants to rotate their keys through your UI
- **Validate keys** - Consider validating keys before storing them

## Example: Full Multi-Tenant Setup

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.multi_tenancy_enabled = true
  config.tenant_resolver = -> { Current.tenant_id }

  # Global limits as a safety net
  config.budgets = {
    global_daily: 1000.0,
    global_monthly: 20000.0,
    global_daily_tokens: 10_000_000,
    global_monthly_executions: 50_000,
    enforcement: :hard
  }
end

# app/models/organization.rb
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  encrypts :openai_api_key, :anthropic_api_key

  llm_tenant(
    id: :slug,
    name: :display_name,
    limits: {
      daily_cost: 100.0,
      monthly_cost: 1000.0,
      daily_tokens: 1_000_000,
      monthly_tokens: 10_000_000,
      daily_executions: 500,
      monthly_executions: 10_000
    },
    enforcement: :hard,
    api_keys: {
      openai: :openai_api_key,
      anthropic: :anthropic_api_key
    }
  )
end

# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant_id, :organization
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :set_current_tenant

  private

  def set_current_tenant
    Current.organization = current_user&.organization
    Current.tenant_id = Current.organization&.slug
  end
end

# Usage in controllers
class AiController < ApplicationController
  def analyze
    # Pass the organization as tenant - API keys and budget are automatic
    result = AnalysisAgent.call(
      query: params[:query],
      tenant: Current.organization
    )
    render json: result.response
  rescue RubyLLM::Agents::BudgetExceededError => e
    render json: { error: "Usage limit exceeded" }, status: 429
  end
end

# Usage in views/dashboards
org = Organization.find(1)
org.llm_usage_summary(period: :this_month)
# => { cost: 450.50, tokens: 4_500_000, executions: 3200, period: :this_month }

org.llm_within_budget?(type: :monthly_cost)  # => true
org.llm_remaining_budget(type: :monthly_cost) # => 549.50
```

## Related Pages

- [Budget Controls](Budget-Controls) - Spending limits
- [Execution Tracking](Execution-Tracking) - Filtering and analytics
- [Circuit Breakers](Circuit-Breakers) - Failure handling
- [Configuration](Configuration) - Full setup guide
