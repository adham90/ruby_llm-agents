# Migration Guide

This guide helps you upgrade your application between RubyLLM::Agents versions.

For full upgrade instructions, see [UPGRADE.md](../UPGRADE.md).

---

## Renaming Agents

When you rename an agent class, old execution records still reference the previous name. There are three approaches:

### Option 1: Aliases DSL (no data migration)

Declare previous names on the agent class. Queries and analytics automatically include all names:

```ruby
class SupportBot < ApplicationAgent
  aliases "CustomerSupportAgent", "HelpDeskAgent"
end
```

**Pros:** No data migration needed, reversible, preserves history.
**Cons:** Aliases must stay in the code permanently.

### Option 2: Migration generator (permanent rename)

Generate a reversible migration to rewrite execution records:

```bash
rails generate ruby_llm_agents:rename_agent CustomerSupportAgent SupportBot
rails db:migrate
```

**Pros:** Clean data, no runtime overhead.
**Cons:** Irreversible without the down migration.

### Option 3: Programmatic helper (quick rename)

For ad-hoc renames in console or scripts:

```ruby
# Dry run first
RubyLLM::Agents.rename_agent("CustomerSupportAgent", to: "SupportBot", dry_run: true)
# => { executions_affected: 1432, tenants_affected: 3 }

# Apply
RubyLLM::Agents.rename_agent("CustomerSupportAgent", to: "SupportBot")
# => { executions_updated: 1432, tenants_updated: 3 }
```

Or via Rake:

```bash
rake ruby_llm_agents:rename_agent FROM=CustomerSupportAgent TO=SupportBot DRY_RUN=1
rake ruby_llm_agents:rename_agent FROM=CustomerSupportAgent TO=SupportBot
```

This updates both execution records and per-agent budget keys in tenant configuration.

---

## Upgrading to v3.0.0

### From v2.2.0

v3.0.0 is a **major release with breaking changes**. Block-based DSL forms have been removed and `prompt` emits a deprecation warning.

**Breaking: Block forms removed**

`system do...end`, `user do...end`, and `prompt do...end` no longer work. Blocks passed to these methods are silently ignored. Use string arguments or method overrides instead.

```ruby
# Before (v2.2 — no longer works in v3.0)
class MyAgent < ApplicationAgent
  system { "You help with #{context}" }
  user { "Analyze: #{query}" }
end

# After (v3.0 — static strings)
class MyAgent < ApplicationAgent
  system "You help with {context}"
  user "Analyze: {query}"
end

# After (v3.0 — dynamic via method override)
class MyAgent < ApplicationAgent
  def system_prompt
    "You help with #{context}"
  end

  def user_prompt
    "Analyze: #{query}"
  end
end
```

**Breaking: `resolve_prompt_from_config` no longer handles Procs**

If you overrode `resolve_prompt_from_config` or relied on it accepting Proc objects, update to use string templates or method overrides.

**Deprecation: `prompt` alias**

`prompt "..."` continues to work but emits a deprecation warning. Use `user "..."` instead:

```ruby
# Deprecated (still works, emits warning)
class MyAgent < ApplicationAgent
  prompt "Analyze: {query}"
end

# Preferred
class MyAgent < ApplicationAgent
  user "Analyze: {query}"
end
```

**Migration steps:**

```bash
bundle update ruby_llm-agents
```

No database migrations are required for v3.0.0.

**Required:** Replace any block-based DSL usage:

```bash
grep -rn "system do\|user do\|prompt do" app/agents/ --include="*.rb"
```

Convert to string arguments or method overrides as shown above.

**Recommended:** Replace `prompt` with `user`:

```bash
grep -rn "^\s*prompt " app/agents/ --include="*.rb"
```

---

## Upgrading to v2.2.0

### From v2.1.0

v2.2.0 introduced the **three-role DSL** (`system`, `user`, `assistant`) and the `.ask` convenience method. `prompt` works as a deprecated alias.

**DSL: `user` replaces `prompt`**

```ruby
# Before (v2.1 and earlier)
class MyAgent < ApplicationAgent
  prompt "Analyze: {query}"
end

# After (v2.2+)
class MyAgent < ApplicationAgent
  user "Analyze: {query}"
end
```

**DSL: `assistant` prefill**

Pre-fill the assistant turn to steer output format:

```ruby
class JsonAgent < ApplicationAgent
  model "claude-sonnet-4-20250514"
  system "Extract entities as JSON."
  user   "{text}"
  assistant "{"
end
```

**Method: `.ask`**

One-shot convenience for ad-hoc queries:

```ruby
result = MyAgent.ask("What is the capital of France?")
```

**Migration steps:**

```bash
bundle update ruby_llm-agents
```

No database migrations required.

---

## Upgrading to v2.1.0

### From v2.0.0

v2.1.0 is a minor release with no breaking changes. Key additions:

**Unified API Key Configuration**

You can now configure all LLM provider API keys directly in `RubyLLM::Agents.configure`. No separate `ruby_llm.rb` initializer needed:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # API keys (forwarded to RubyLLM automatically)
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.gemini_api_key = ENV["GOOGLE_API_KEY"]

  # All other settings
  config.default_model = "gpt-4o"
end
```

**Migration steps:**

```bash
bundle update ruby_llm-agents
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

The upgrade generator will suggest consolidating if it detects a separate `config/initializers/ruby_llm.rb` file.

**Optional:** Remove your `config/initializers/ruby_llm.rb` and move its settings into `ruby_llm_agents.rb`. See [Configuration](Configuration#unified-api-key-configuration-v21) for the full list of forwarded attributes.

**Other changes:**
- Fixed cost calculation (now uses `Models.find` for correct pricing)
- Minimum `ruby_llm` dependency bumped to `>= 1.12.0`
- Dashboard: Tenants nav link hidden when multi-tenancy is disabled

---

## Upgrading to v2.0.0

### From v1.x

v2.0.0 is a **major release with breaking changes**. See the comprehensive [v2.0 Upgrade Guide](../UPGRADE.md#upgrading-to-v200) for step-by-step instructions.

**Key changes:**
- Schema split: execution data now lives in two tables (`executions` + `execution_details`)
- Workflow orchestration removed (use dedicated workflow gems)
- `version` DSL, `ApiConfiguration`, built-in moderation/PII removed
- `TenantBudget` deprecated in favor of `Tenant`

```bash
bundle update ruby_llm-agents
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

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
  system "You are a helpful support agent."
end
```

**After (v1.0.0):**

```ruby
# app/agents/support_agent.rb
class SupportAgent < ApplicationAgent
  model "gpt-4o"
  system "You are a helpful support agent."
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
