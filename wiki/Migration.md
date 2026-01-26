# Migration Guide

This guide helps you upgrade your application between RubyLLM::Agents versions.

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

### New Features in v1.1.0

- **Wait Steps** - Human-in-the-loop workflows with `wait`, `wait_until`, `wait_for`
- **Sub-Workflows** - Compose workflows by nesting other workflows as steps
- **Iteration** - Process collections with `each:` option on steps
- **Recursion** - Workflows can call themselves with depth limits
- **Notifications** - Slack, Email, Webhook notifications for workflow approvals
- **New Agents** - `SpecialistAgent` and `ValidatorAgent` for common patterns
- **Workflows Index** - Dashboard page with filtering and navigation

#### Workflow DSL Examples (v1.1.0+)

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

Sub-workflows and iteration:

```ruby
class BatchWorkflow < RubyLLM::Agents::Workflow
  # Nest another workflow
  step :preprocess, PreprocessWorkflow

  # Iterate over collections
  step :process, ProcessorAgent, each: ->(ctx) { ctx[:items] }
end
```

See [CHANGELOG](../CHANGELOG.md) for full details.

---

## Upgrading from v0.5.0 to v1.0.0

### Quick Summary

| Change | v0.5.0 | v1.0.0 |
|--------|--------|--------|
| Directory | `app/agents/` | `app/agents/` (unchanged) |
| Namespace | None | None (optional) |
| Base class | `RubyLLM::Agents::Base` | `ApplicationAgent` |
| `cache` DSL | `cache 1.hour` | `cache_for 1.hour` |

## What's New in v1.0.0

v1.0.0 introduces significant new features while maintaining the same directory structure:

- **Extended Thinking** - Support for chain-of-thought reasoning with Claude models
- **Content Moderation** - Built-in content safety filtering
- **Audio Agents** - New Transcriber and Speaker agents for speech-to-text and text-to-speech
- **Image Operations** - Comprehensive image generation, analysis, editing, and pipelines
- **Embedder Improvements** - Enhanced embedding support
- **Middleware Pipeline** - Pluggable architecture for agent execution
- **Multi-Tenant API Keys** - Per-tenant API configuration support
- **Reliability Enhancements** - Fallback providers, custom retry patterns, circuit breakers

---

## Breaking Changes

### 1. ApplicationAgent Base Class

In v1.0.0, agents should inherit from `ApplicationAgent` rather than `RubyLLM::Agents::Base` directly.

**Before (v0.5.0):**

```ruby
# app/agents/support_agent.rb
class SupportAgent < RubyLLM::Agents::Base
  model "gpt-4o"

  def system_prompt
    "You are a helpful support agent."
  end
end
```

**After (v1.0.0):**

```ruby
# app/agents/support_agent.rb
class SupportAgent < ApplicationAgent
  model "gpt-4o"

  def system_prompt
    "You are a helpful support agent."
  end
end
```

If you don't have an `ApplicationAgent`, create one:

```ruby
# app/agents/application_agent.rb
class ApplicationAgent < RubyLLM::Agents::Base
  # Shared configuration for all agents
end
```

Or run the install generator:

```bash
rails generate ruby_llm_agents:install
```

### 2. DSL Deprecations

#### cache → cache_for

The `cache` DSL method is deprecated. Use `cache_for` instead:

```ruby
# Before (deprecated, still works with warning)
class MyAgent < ApplicationAgent
  cache 1.hour
end

# After (preferred)
class MyAgent < ApplicationAgent
  cache_for 1.hour
end
```

#### Result Hash Access

Direct hash access on result objects is deprecated. Use `result.content` instead:

```ruby
# Before (deprecated)
result = MyAgent.call(query: "test")
value = result[:key]

# After (preferred)
result = MyAgent.call(query: "test")
value = result.content[:key]
```

---

## Migration Steps

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

### Step 2: Run Database Migrations

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

### Step 3: Ensure ApplicationAgent Exists

Check if you have `app/agents/application_agent.rb`. If not, create it:

```ruby
# app/agents/application_agent.rb
class ApplicationAgent < RubyLLM::Agents::Base
  # Shared configuration for all agents
end
```

### Step 4: Update Base Class References

Find any agents that inherit directly from `RubyLLM::Agents::Base`:

```bash
grep -rn "< RubyLLM::Agents::Base" app/ --include="*.rb"
```

Update them to inherit from `ApplicationAgent`:

```ruby
# Before
class MyAgent < RubyLLM::Agents::Base

# After
class MyAgent < ApplicationAgent
```

### Step 5: Update Deprecated DSL

Find `cache` usage:

```bash
grep -rn "^\s*cache\s" app/agents/ --include="*.rb"
```

Replace with `cache_for`:

```ruby
# Before
cache 1.hour

# After
cache_for 1.hour
```

### Step 6: Update Result Access

Find hash-style result access:

```bash
grep -rn "result\[:" app/ --include="*.rb"
```

Update to use `.content`:

```ruby
# Before
result[:key]

# After
result.content[:key]
```

---

## New Features (Optional)

### Extended Thinking

Enable chain-of-thought reasoning for supported models (Claude):

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

Add content safety filtering:

```ruby
class SafeAgent < ApplicationAgent
  moderation do
    enabled true
    on_violation :block  # :warn, :log, :raise
  end
end
```

### Enhanced Reliability

Configure fallback providers and retry patterns:

```ruby
class ReliableAgent < ApplicationAgent
  reliability do
    retries max: 3, backoff: :exponential
    fallback_provider "anthropic"        # Provider-level fallback
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    retryable_patterns [/timeout/i]      # Custom patterns
    total_timeout 30
    circuit_breaker errors: 10, within: 60, cooldown: 300
  end
end
```

### Audio Agents

Generate speech-to-text and text-to-speech agents:

```bash
rails generate ruby_llm_agents:transcriber Meeting
rails generate ruby_llm_agents:speaker Narrator
```

```ruby
# Speech-to-text
result = MeetingTranscriber.call(audio: audio_file)
puts result.content  # Transcribed text

# Text-to-speech
result = NarratorSpeaker.call(text: "Hello world")
result.content  # Audio data
```

### Image Agents

Generate image operation agents:

```bash
rails generate ruby_llm_agents:image_generator Logo
rails generate ruby_llm_agents:image_analyzer Product
rails generate ruby_llm_agents:image_pipeline Ecommerce
```

```ruby
# Generate image
result = LogoGenerator.call(prompt: "A tech startup logo")

# Analyze image
result = ProductAnalyzer.call(image: image_file)

# Multi-step pipeline
result = EcommercePipeline.call(prompt: "Product photo")
```

### Embeddings

Generate embedding agents:

```bash
rails generate ruby_llm_agents:embedder Document
```

```ruby
result = DocumentEmbedder.call(text: "Hello world")
result.content  # Embedding vector
```

---

## Optional: Custom Directory/Namespace

By default, agents live in `app/agents/` with no namespace. You can customize this:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.root_directory = "llm"      # Creates app/llm/agents/
  config.root_namespace = "Llm"      # Agents use Llm:: prefix
end
```

With custom namespace:

```ruby
# app/llm/agents/support_agent.rb
module Llm
  class SupportAgent < ApplicationAgent
    # ...
  end
end

# Usage
Llm::SupportAgent.call(message: "Help!")
```

---

## Verification Checklist

After migration, verify:

- [ ] `rails console` loads without errors
- [ ] `ApplicationAgent` is accessible
- [ ] All your agents are accessible
- [ ] Test suite passes
- [ ] Application starts without errors
- [ ] No deprecation warnings (optional)

Run these commands to verify:

```bash
# Check gem version
bundle show ruby_llm-agents

# Verify migrations applied
rails db:migrate:status | grep ruby_llm

# Test agent loading
rails runner "puts ApplicationAgent.name"

# Run test suite
bundle exec rspec
```

---

## Troubleshooting

### Common Issues

#### "uninitialized constant ApplicationAgent"

**Cause:** Missing ApplicationAgent base class.

**Fix:** Create `app/agents/application_agent.rb`:

```ruby
class ApplicationAgent < RubyLLM::Agents::Base
end
```

Or run `rails generate ruby_llm_agents:install`

#### "undefined method 'cache' for class"

**Cause:** `cache` is deprecated.

**Fix:** Use `cache_for` instead

#### "NoMethodError: undefined method '[]' for result"

**Cause:** Hash access on result objects is deprecated.

**Fix:** Use `result.content[:key]` instead of `result[:key]`

#### Migration errors

**Cause:** Missing database columns.

**Fix:** Run `rails generate ruby_llm_agents:upgrade && rails db:migrate`

#### Tests failing with NameError

**Cause:** Test files reference old class names.

**Fix:** Update test references to match new class structure

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting](Troubleshooting) page
2. Search [GitHub Issues](https://github.com/adham90/ruby_llm-agents/issues)
3. Open a new issue with:
   - Error message
   - Ruby/Rails versions
   - Steps to reproduce

---

## Related Pages

- [Getting Started](Getting-Started) - Fresh installation guide
- [Generators](Generators) - All available generators
- [Configuration](Configuration) - Configuration options
- [Agent DSL](Agent-DSL) - Agent configuration reference
- [Audio](Audio) - Audio agent documentation
- [Image Operations](Image-Generation) - Image agent documentation
