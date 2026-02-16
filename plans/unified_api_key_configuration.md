# Unified API Key Configuration

Users should configure everything through `RubyLLM::Agents.configure` — one gem, one config block. They shouldn't need to know about `ruby_llm` as a separate dependency or create a separate `ruby_llm.rb` initializer.

---

## Problem

1. `ruby_llm` is a dependency of `ruby_llm-agents` but requires its own `RubyLLM.configure` block for API keys
2. The install generator creates `ruby_llm_agents.rb` but not `ruby_llm.rb`, so users hit `Missing configuration for OpenAI: openai_api_key` immediately
3. Users shouldn't need to add `gem 'ruby_llm'` to their Gemfile — it's already a dependency
4. Having two separate config blocks for one gem install is confusing

---

## Solution

Add API key accessors to `RubyLLM::Agents::Configuration` that forward to `RubyLLM.configure` internally. Users set everything in one place.

### Before (two config blocks)

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end

# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_model = "gpt-4o"
end
```

### After (one config block)

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # API Keys
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.gemini_api_key = ENV["GOOGLE_API_KEY"]

  # Agent config
  config.default_model = "gpt-4o"
end
```

---

## Implementation

### 1. Add API key forwarding to Configuration

**File:** `lib/ruby_llm/agents/core/configuration.rb`

Add forwarding setters for all `ruby_llm` API key attributes. These write directly to `RubyLLM.configuration` so the underlying gem picks them up.

```ruby
# API key attributes forwarded to RubyLLM
# These let users configure everything in one place.
API_KEY_ATTRIBUTES = %i[
  openai_api_key
  anthropic_api_key
  gemini_api_key
  deepseek_api_key
  openrouter_api_key
  bedrock_api_key
  bedrock_secret_key
  bedrock_session_token
  bedrock_region
  mistral_api_key
  perplexity_api_key
  xai_api_key
  gpustack_api_key
].freeze

# Connection/provider attributes forwarded to RubyLLM
PROVIDER_ATTRIBUTES = %i[
  openai_api_base
  openai_organization_id
  openai_project_id
  gemini_api_base
  gpustack_api_base
  ollama_api_base
  vertexai_project_id
  vertexai_location
  request_timeout
  max_retries
].freeze

(API_KEY_ATTRIBUTES + PROVIDER_ATTRIBUTES).each do |attr|
  define_method(:"#{attr}=") do |value|
    RubyLLM.configuration.public_send(:"#{attr}=", value)
  end

  define_method(attr) do
    RubyLLM.configuration.public_send(attr)
  end
end
```

**Why this approach:**
- No duplication — reads and writes go straight to `RubyLLM.configuration`
- If `ruby_llm` adds new attributes, we can add them here without storing state
- If user already has `RubyLLM.configure` somewhere, both paths write to the same object — no conflict
- Only non-nil values get forwarded (setter is only called if user explicitly sets it)

### 2. Update initializer template

**File:** `lib/generators/ruby_llm_agents/templates/initializer.rb.tt`

Add API keys section at the top of the existing template:

```ruby
RubyLLM::Agents.configure do |config|
  # ============================================
  # LLM Provider API Keys
  # ============================================
  # Configure at least one provider. Set these in your environment
  # or replace ENV[] calls with your keys directly.
  #
  # config.openai_api_key = ENV["OPENAI_API_KEY"]
  # config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  # config.gemini_api_key = ENV["GOOGLE_API_KEY"]
  #
  # Additional providers:
  # config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
  # config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  # config.mistral_api_key = ENV["MISTRAL_API_KEY"]
  # config.xai_api_key = ENV["XAI_API_KEY"]
  #
  # Custom endpoints (e.g., Azure OpenAI, local Ollama):
  # config.openai_api_base = "https://your-resource.openai.azure.com"
  # config.ollama_api_base = "http://localhost:11434"
  #
  # Connection settings:
  # config.request_timeout = 120
  # config.max_retries = 3

  # ============================================
  # Model Defaults
  # ============================================
  # ... (rest of existing template unchanged)
```

### 3. Remove the separate ruby_llm_initializer.rb.tt

**Delete:** `lib/generators/ruby_llm_agents/templates/ruby_llm_initializer.rb.tt`

**File:** `lib/generators/ruby_llm_agents/install_generator.rb`

Remove the `create_ruby_llm_initializer` method added in the previous commit. No separate file needed anymore.

### 4. Update post-install message

**File:** `lib/generators/ruby_llm_agents/install_generator.rb`

```ruby
say "Next steps:"
say "  1. Set your API keys in config/initializers/ruby_llm_agents.rb"
say "  2. Run migrations: rails db:migrate"
say "  3. Generate an agent: rails generate ruby_llm_agents:agent MyAgent query:required"
say "  4. Access the dashboard at: /agents"
```

---

## Migration for Existing Apps

### Upgrade generator step

**File:** `lib/generators/ruby_llm_agents/upgrade_generator.rb`

Add a new step that checks for a standalone `ruby_llm.rb` initializer and tells the user they can consolidate:

```ruby
def suggest_config_consolidation
  ruby_llm_initializer = File.join(destination_root, "config/initializers/ruby_llm.rb")
  agents_initializer = File.join(destination_root, "config/initializers/ruby_llm_agents.rb")

  return unless File.exist?(ruby_llm_initializer) && File.exist?(agents_initializer)

  say ""
  say "Optional: You can now consolidate your API key configuration.", :yellow
  say ""
  say "Move your API keys from config/initializers/ruby_llm.rb"
  say "into config/initializers/ruby_llm_agents.rb:"
  say ""
  say "  RubyLLM::Agents.configure do |config|"
  say "    config.openai_api_key = ENV['OPENAI_API_KEY']"
  say "    config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']"
  say "    # ... rest of your agent config"
  say "  end"
  say ""
  say "Then delete config/initializers/ruby_llm.rb if it only contained API keys."
  say ""
end
```

This is **not breaking** — the old `ruby_llm.rb` initializer still works. It's just a suggestion.

---

## What This Does NOT Do

- **Does not break existing `RubyLLM.configure`** — If users already have `ruby_llm.rb`, it still works. Both paths write to the same `RubyLLM.configuration` object.
- **Does not require migration** — No schema changes. Pure configuration.
- **Does not remove `ruby_llm` from gemspec** — It's still a dependency, just invisible to the user.

---

## Files to Change

| File | Change |
|------|--------|
| `lib/ruby_llm/agents/core/configuration.rb` | Add API key/provider forwarding methods |
| `lib/generators/ruby_llm_agents/templates/initializer.rb.tt` | Add API keys section at top |
| `lib/generators/ruby_llm_agents/install_generator.rb` | Remove `create_ruby_llm_initializer`, update post-install message |
| `lib/generators/ruby_llm_agents/templates/ruby_llm_initializer.rb.tt` | **Delete** |
| `lib/generators/ruby_llm_agents/upgrade_generator.rb` | Add `suggest_config_consolidation` step |
| `spec/` | Add specs for API key forwarding |

---

## Tests

### Configuration forwarding spec

```ruby
describe "API key forwarding" do
  it "forwards openai_api_key to RubyLLM" do
    RubyLLM::Agents.configure do |config|
      config.openai_api_key = "sk-test-123"
    end

    expect(RubyLLM.configuration.openai_api_key).to eq("sk-test-123")
  end

  it "reads back from RubyLLM" do
    RubyLLM.configure { |c| c.openai_api_key = "sk-direct" }

    expect(RubyLLM::Agents.configuration.openai_api_key).to eq("sk-direct")
  end

  it "does not overwrite existing keys when not set" do
    RubyLLM.configure { |c| c.openai_api_key = "sk-existing" }
    RubyLLM::Agents.configure { |c| c.default_model = "gpt-4o" }

    expect(RubyLLM.configuration.openai_api_key).to eq("sk-existing")
  end
end
```

### Install generator spec

```ruby
it "does not create ruby_llm.rb initializer" do
  run_generator
  expect(file("config/initializers/ruby_llm.rb")).not_to exist
end

it "creates ruby_llm_agents.rb with API key comments" do
  run_generator
  expect(file("config/initializers/ruby_llm_agents.rb")).to contain("openai_api_key")
end
```

---

## Shipping

| Phase | What | Breaking? |
|-------|------|-----------|
| **1** | Add forwarding methods + update initializer template | **No** |
| **2** | Remove `ruby_llm_initializer.rb.tt` + update install generator | **No** |
| **3** | Add upgrade generator hint | **No** |

All three phases can ship in a single release. Nothing is breaking.
