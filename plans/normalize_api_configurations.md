# Remove API Configurations Table

This plan removes the `ruby_llm_agents_api_configurations` table entirely. Credentials and connection settings are managed through `ruby_llm` gem configuration and environment variables, following 12-factor app principles.

---

## Problem

The current `api_configurations` table:
- Duplicates what `ruby_llm` gem already handles
- Stores API keys in the database (security concern)
- Has 30+ columns, most unused
- Adds complexity with no clear benefit

---

## Solution

**Delete the table.** Use existing configuration mechanisms:

| Setting | Where |
|---------|-------|
| API keys | `ruby_llm` configuration / ENV vars |
| Connection settings | `ruby_llm` configuration |
| Default models | `RubyLLM::Agents.configuration` |

---

## Configuration (After Removal)

### API Keys & Connection Settings

Handled by `ruby_llm` gem (already works):

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  # API Keys (from ENV)
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.gemini_api_key = ENV["GEMINI_API_KEY"]
  config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
  # ... other providers

  # Connection settings
  config.request_timeout = 120
  config.max_retries = 3
end
```

### Default Models

Handled by `RubyLLM::Agents` configuration:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_model = "gpt-4o"
  config.default_embedding_model = "text-embedding-3-small"
  config.default_image_model = "dall-e-3"
end
```

---

## What's NOT Supported

- **Per-tenant API keys** - All tenants use the same configured API keys
- **Per-tenant model overrides** - Agents define their own models; use different agent classes for different tiers if needed

These are intentional simplifications. If needed, users can implement in their app:

```ruby
# Example: Different models per tenant tier (user's app code)
class MyAgent < ApplicationAgent
  def model
    tenant&.premium? ? "claude-sonnet-4-20250514" : "gpt-4o-mini"
  end
end
```

---

## Migration

### Single Migration: Drop Table

```ruby
class RemoveApiConfigurations < ActiveRecord::Migration[7.1]
  def up
    drop_table :ruby_llm_agents_api_configurations, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, <<~MSG
      The api_configurations table has been removed.
      Configure API keys via environment variables and ruby_llm gem configuration.
    MSG
  end
end
```

---

## Files to Delete

| File | Reason |
|------|--------|
| `app/models/ruby_llm/agents/api_configuration.rb` | No longer needed |
| `app/controllers/ruby_llm/agents/api_configurations_controller.rb` | No longer needed |
| `app/views/ruby_llm/agents/api_configurations/` | No longer needed |
| `lib/generators/ruby_llm_agents/templates/create_api_configurations_migration.rb.tt` | No longer needed |
| `spec/models/api_configuration_spec.rb` | No longer needed |
| `spec/factories/api_configurations.rb` | No longer needed |

---

## Files to Update

| File | Change |
|------|--------|
| `lib/ruby_llm/agents/configuration.rb` | Ensure `default_model` attrs exist |
| `lib/generators/ruby_llm_agents/templates/initializer.rb.tt` | Remove api_configurations references |
| `lib/generators/ruby_llm_agents/install_generator.rb` | Remove api_configurations migration |
| Any code referencing `ApiConfiguration` | Remove or use `RubyLLM.configuration` |

---

## Benefits

1. **Simpler** - No database table, no model, no controller
2. **More secure** - API keys in ENV vars, not database
3. **12-factor compliant** - Config in environment
4. **No duplication** - `ruby_llm` already handles this
5. **Less code** - Delete ~500 lines

---

## Shipping

| Phase | What | Breaking? |
|-------|------|-----------|
| **1** | Drop table, delete files, update docs | **Yes** |

### Upgrade Guide

```markdown
## Upgrading to v1.0

The `api_configurations` table has been removed.

**Before (database):**
```ruby
ApiConfiguration.global.first.update!(openai_api_key: "sk-...")
```

**After (environment):**
```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
```

**Steps:**
1. Export API keys from database before upgrading
2. Set as environment variables
3. Run `rails db:migrate`
```

---

## Summary

| Before | After |
|--------|-------|
| 30-column `api_configurations` table | Deleted |
| `ApiConfiguration` model | Deleted |
| API keys in database | ENV vars |
| Connection settings in database | `ruby_llm` config |
| Default models in database | `RubyLLM::Agents.configuration` |
