# Upgrading RubyLLM::Agents

> Reference guide for AI coding agents to assist with upgrades

## Upgrading to v2.0.0

### From v1.x

v2.0.0 is a **major release with breaking changes**. The schema has been redesigned for performance and several subsystems have been removed.

### Quick Reference

| Aspect | Status |
|--------|--------|
| Schema | **Breaking** - Execution data split into two tables |
| Workflows | **Removed** - Use dedicated workflow gems |
| `version` DSL | **Removed** - Use `metadata` for traceability |
| `ApiConfiguration` | **Removed** - Use environment variables |
| Moderation/PII | **Removed** - Use `before_call`/`after_call` hooks |
| `TenantBudget` | **Deprecated** - Use `Tenant` model |
| Agent DSL | Unchanged (`app/agents/`, `ApplicationAgent`) |
| `.call()` API | Unchanged |

### Step 1: Update Gemfile

```ruby
# Before
gem "ruby_llm-agents", "~> 1.3"

# After
gem "ruby_llm-agents", "~> 2.0"
```

```bash
bundle update ruby_llm-agents
```

### Step 2: Run Database Migrations

The upgrade generator handles all schema transitions automatically:

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

The generator will:
- Create the `ruby_llm_agents_execution_details` table
- Migrate data from old columns on `executions` to `execution_details`
- Move niche columns (`time_to_first_token_ms`, `rate_limited`, `retryable`, `fallback_reason`, `span_id`, `response_cache_key`) to `metadata` JSON
- Remove deprecated columns (`agent_version`, workflow columns, polymorphic tenant columns)
- Rename `ruby_llm_agents_tenant_budgets` to `ruby_llm_agents_tenants` (if applicable)

### Step 3: Remove Workflow Code

Workflows have been removed entirely. Find and remove workflow usage:

```bash
grep -rn "Workflow" app/ --include="*.rb"
grep -rn "workflow" app/ --include="*.rb"
```

Migrate to a dedicated workflow library (Temporal, Sidekiq, etc.) for orchestration needs.

### Step 4: Remove `version` DSL Calls

```bash
grep -rn '^\s*version\s' app/agents/ --include="*.rb"
```

```ruby
# Before
class MyAgent < ApplicationAgent
  version "1.2"
  model "gpt-4o"
end

# After
class MyAgent < ApplicationAgent
  model "gpt-4o"
end
```

### Step 5: Replace Moderation/PII with Hooks

If you used built-in moderation or PII redaction, replace with `before_call`/`after_call` hooks:

```ruby
# Before
class SafeAgent < ApplicationAgent
  moderation do
    enabled true
    on_violation :block
  end
end

# After
class SafeAgent < ApplicationAgent
  before_call :check_content

  private

  def check_content
    # Your moderation logic here
    raise "Content blocked" if harmful?(user_prompt)
  end
end
```

### Step 6: Replace ApiConfiguration

If you stored API keys in the `ApiConfiguration` table, move them to environment variables or the `llm_tenant` DSL:

```ruby
# Environment variables (recommended)
# Set OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.

# Per-tenant API keys via LLMTenant DSL
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  llm_tenant(
    id: :slug,
    api_keys: {
      openai: :openai_api_key,
      anthropic: :anthropic_api_key
    }
  )
end
```

### Step 7: Update TenantBudget References

`TenantBudget` is now a deprecated alias for `Tenant`:

```ruby
# Before
RubyLLM::Agents::TenantBudget.for_tenant("tenant_123")

# After
RubyLLM::Agents::Tenant.for("tenant_123")
```

### Step 8: Update Raw SQL Queries

If you have raw SQL queries referencing columns that moved to `execution_details` or `metadata`:

```ruby
# Before - these columns are no longer on the executions table
Execution.where("time_to_first_token_ms > ?", 1000)
Execution.where(fallback_reason: "rate_limit")
Execution.where("error_message LIKE ?", "%timeout%")

# After - use metadata helpers or join with details
Execution.streaming  # Use scopes where possible
Execution.with_fallback  # Uses metadata_present("fallback_reason")
Execution.joins(:detail).where("ruby_llm_agents_execution_details.error_message LIKE ?", "%timeout%")
```

### Step 9: Update `on_alert` Handlers

The alert system has been simplified to a single `on_alert` handler:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.on_alert = ->(alert) {
    # Handle alerts (budget warnings, circuit breaker trips, etc.)
    SlackNotifier.send(alert[:message])
  }
end
```

### Verification Checklist

```bash
# Check gem version
bundle show ruby_llm-agents

# Verify migrations applied
rails db:migrate:status | grep ruby_llm

# Test agent loading
rails runner "puts ApplicationAgent.name"

# Test an agent call
rails runner "puts MyAgent.call(query: 'test').success?"

# Run test suite
bundle exec rspec
```

### New Features in v2.0.0

- **`before_call` and `after_call` callbacks** - Agent-level hooks for custom pre/post processing
- **Execution details table** - Split schema for better query performance
- **Database-agnostic metadata queries** - `metadata_present`, `metadata_true`, `metadata_value` helpers
- **Tenants table** - DB counter columns for efficient budget tracking
- **Redesigned dashboard** - Compact layout with sortable columns

See [CHANGELOG](CHANGELOG.md) for full details.

---

## Upgrading to v1.1.0

### From v1.0.0

v1.1.0 is a backwards-compatible release with new features. No breaking changes.

```ruby
# Update Gemfile
gem "ruby_llm-agents", "~> 1.1.0"
```

```bash
bundle update ruby_llm-agents
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

#### New Features in v1.1.0

- **New Agents** - `SpecialistAgent` and `ValidatorAgent`

> **Note:** Workflow features introduced in v1.1.0 (Wait Steps, Sub-Workflows, Iteration) have been removed in v2.0.0.

See [CHANGELOG](CHANGELOG.md) for full details.

---

## Upgrading from v0.5.0 → v1.0.0

### Quick Reference

| Aspect | Status |
|--------|--------|
| Directory structure | **Unchanged** (`app/agents/`) |
| Namespace | **None required** |
| Base class | Use `ApplicationAgent` |
| `cache` DSL | Deprecated → use `cache_for` |
| Result access | `result[:key]` deprecated → `result.content[:key]` |

### Step 1: Update Gemfile

```ruby
# Before
gem "ruby_llm-agents", "~> 0.5.0"

# After
gem "ruby_llm-agents", "~> 1.1.0"
```

Then run:
```bash
bundle update ruby_llm-agents
```

## Step 2: Run Database Migrations

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

## Step 3: Fix Deprecated DSL

### Find `cache` usage:
```bash
grep -rn "^\s*cache\s" app/agents/ --include="*.rb"
```

### Replace with `cache_for`:
```ruby
# Before
class MyAgent < ApplicationAgent
  cache 1.hour
end

# After
class MyAgent < ApplicationAgent
  cache_for 1.hour
end
```

## Step 4: Fix Result Object Access

### Find hash-style access:
```bash
grep -rn "result\[:" app/ --include="*.rb"
grep -rn "\.call.*\[:" app/ --include="*.rb"
```

### Replace pattern:
```ruby
# Before
result = MyAgent.call(query: "test")
value = result[:key]

# After
result = MyAgent.call(query: "test")
value = result.content[:key]
```

## Step 5: Update Base Class References

### Find direct RubyLLM::Agents::Base usage:
```bash
grep -rn "< RubyLLM::Agents::Base" app/ --include="*.rb"
```

### If found, ensure ApplicationAgent exists:
```ruby
# app/agents/application_agent.rb
class ApplicationAgent < RubyLLM::Agents::Base
  # Shared configuration for all agents
end
```

Then update agents:
```ruby
# Before
class MyAgent < RubyLLM::Agents::Base

# After
class MyAgent < ApplicationAgent
```

## Step 6: Find All Agent Calls (Reference Check)

Use these commands to find all agent usage in the app:

```bash
# Find all agent calls
grep -rn "Agent\.call\|Agent\.stream" app/ lib/ --include="*.rb"

# Find embedder calls
grep -rn "Embedder\.call" app/ lib/ --include="*.rb"

# Find audio agent calls
grep -rn "Speaker\.call\|Transcriber\.call" app/ lib/ --include="*.rb"

# Find image agent calls
grep -rn "Generator\.call\|Analyzer\.call\|Pipeline\.call" app/ lib/ --include="*.rb"
```

## New Features Available After Upgrade

### Extended Thinking (Claude models)
```ruby
class ReasoningAgent < ApplicationAgent
  model "claude-sonnet-4-20250514"

  thinking do
    enabled true
    budget_tokens 10_000
  end
end

result = ReasoningAgent.call(query: "Complex problem")
result.thinking  # Access reasoning trace
result.content   # Final answer
```

### Reliability Enhancements
```ruby
class ReliableAgent < ApplicationAgent
  reliability do
    retries max: 3, backoff: :exponential
    fallback_provider "anthropic"        # NEW: Provider-level fallback
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    retryable_patterns [/timeout/i]      # NEW: Custom patterns
    total_timeout 30
    circuit_breaker errors: 10, within: 60, cooldown: 300
  end
end
```

### Audio Agents (New)
```bash
rails generate ruby_llm_agents:transcriber Meeting
rails generate ruby_llm_agents:speaker Narrator
```

### Image Agents (New)
```bash
rails generate ruby_llm_agents:image_generator Logo
rails generate ruby_llm_agents:image_analyzer Product
rails generate ruby_llm_agents:image_pipeline Ecommerce
```

### Embeddings
```bash
rails generate ruby_llm_agents:embedder Document
```

## Verification Checklist

Run these commands to verify successful upgrade:

```bash
# Check gem version
bundle show ruby_llm-agents

# Verify migrations applied
rails db:migrate:status | grep ruby_llm

# Test agent loading
rails runner "puts ApplicationAgent.name"

# Test a simple agent call (if you have one)
rails runner "puts MyAgent.call(query: 'test').success?"

# Run test suite
bundle exec rspec
```

## Rollback (If Needed)

```bash
# Revert to previous version
bundle update ruby_llm-agents --conservative

# Or in Gemfile:
gem "ruby_llm-agents", "~> 0.5.0"
```

## Common Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `undefined method 'cache'` | Using old DSL | Replace with `cache_for` |
| `NoMethodError: []` on result | Hash access deprecated | Use `result.content[:key]` |
| `uninitialized constant ApplicationAgent` | Missing base class | Run install generator or create manually |
| Migration errors | Missing columns | Run `rails g ruby_llm_agents:upgrade` |
