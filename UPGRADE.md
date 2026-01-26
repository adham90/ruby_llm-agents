# Upgrading RubyLLM::Agents

> Reference guide for AI coding agents to assist with upgrades

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

- **Wait Steps** - Human-in-the-loop workflows with `wait`, `wait_until`, `wait_for`
- **Sub-Workflows** - Compose workflows by nesting other workflows
- **Iteration** - Process collections with `each:` option
- **Notifications** - Slack, Email, Webhook notifications for approvals
- **New Agents** - `SpecialistAgent` and `ValidatorAgent`

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

### Workflow DSL with Wait Steps (v1.1.0+)

Build human-in-the-loop workflows:

```ruby
class ApprovalWorkflow < RubyLLM::Agents::Workflow
  step :analyze, AnalyzerAgent

  # Wait for human approval
  wait_for :manager_approval,
    timeout: 24.hours,
    notify: [:slack, :email],
    on_timeout: :skip_next

  step :execute, ExecutorAgent
end
```

### Sub-Workflows and Iteration (v1.1.0+)

```ruby
class BatchWorkflow < RubyLLM::Agents::Workflow
  # Nest another workflow
  step :preprocess, PreprocessWorkflow

  # Iterate over collections
  step :process, ProcessorAgent, each: ->(ctx) { ctx[:items] }
end
```

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

### Content Moderation
```ruby
class SafeAgent < ApplicationAgent
  moderation do
    enabled true
    on_violation :block  # :warn, :log, :raise
  end
end
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
