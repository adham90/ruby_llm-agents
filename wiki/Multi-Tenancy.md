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

## TenantBudget Model

The `TenantBudget` model stores per-tenant spending limits:

```ruby
# Create a tenant budget
RubyLLM::Agents::TenantBudget.create!(
  tenant_id: "tenant_123",
  daily_limit: 50.0,
  monthly_limit: 500.0,
  daily_token_limit: 500_000,
  monthly_token_limit: 5_000_000,
  enforcement: :hard
)
```

### Schema

| Field | Type | Description |
|-------|------|-------------|
| `tenant_id` | string | Unique tenant identifier |
| `daily_limit` | decimal | Daily spending limit in USD |
| `monthly_limit` | decimal | Monthly spending limit in USD |
| `daily_token_limit` | integer | Daily token usage limit |
| `monthly_token_limit` | integer | Monthly token usage limit |
| `enforcement` | string | `:hard` (block) or `:soft` (warn) |

### Managing Tenant Budgets

```ruby
# Find or create with defaults
budget = RubyLLM::Agents::TenantBudget.find_or_create_by(tenant_id: tenant_id) do |b|
  b.daily_limit = 25.0
  b.monthly_limit = 250.0
  b.enforcement = :hard
end

# Update limits
budget.update(daily_limit: 50.0)

# Check current spending
budget.current_daily_spending   # => 12.50
budget.current_monthly_spending # => 125.00
budget.daily_remaining          # => 37.50
budget.monthly_remaining        # => 125.00

# Query effective token limits (includes inheritance from global config)
budget.effective_daily_token_limit   # => 500_000
budget.effective_monthly_token_limit # => 5_000_000
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

With multi-tenancy enabled, budget checks happen at both global and tenant levels:

```ruby
# Global limits (all tenants combined)
config.budgets = {
  global_daily: 1000.0,
  global_monthly: 20000.0
}

# Per-tenant limits (via TenantBudget model)
RubyLLM::Agents::TenantBudget.create!(
  tenant_id: "tenant_123",
  daily_limit: 50.0,
  monthly_limit: 500.0,
  enforcement: :hard
)
```

Execution is blocked if either limit is exceeded (when using `:hard` enforcement).

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
    enforcement: :hard
  }
end

# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant_id, :tenant
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :set_current_tenant

  private

  def set_current_tenant
    Current.tenant_id = current_user&.tenant_id
    Current.tenant = current_user&.tenant
  end
end

# Create tenant budgets (in a service or admin panel)
class TenantOnboardingService
  def call(tenant)
    RubyLLM::Agents::TenantBudget.create!(
      tenant_id: tenant.id,
      daily_limit: tenant.plan.daily_ai_limit,
      monthly_limit: tenant.plan.monthly_ai_limit,
      daily_token_limit: tenant.plan.daily_token_limit,
      monthly_token_limit: tenant.plan.monthly_token_limit,
      enforcement: :hard
    )
  end
end
```

## Related Pages

- [Budget Controls](Budget-Controls) - Spending limits
- [Execution Tracking](Execution-Tracking) - Filtering and analytics
- [Circuit Breakers](Circuit-Breakers) - Failure handling
- [Configuration](Configuration) - Full setup guide
