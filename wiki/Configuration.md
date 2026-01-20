# Configuration

Complete guide to configuring RubyLLM::Agents.

## Configuration File

The install generator creates `config/initializers/ruby_llm_agents.rb`:

```ruby
RubyLLM::Agents.configure do |config|
  # Default Settings
  config.default_model = "gemini-2.0-flash"
  config.default_temperature = 0.0
  config.default_timeout = 60
  config.default_streaming = false

  # Caching
  config.cache_store = Rails.cache

  # Execution Logging
  config.async_logging = true
  config.retention_period = 30.days

  # Anomaly Detection
  config.anomaly_cost_threshold = 5.00
  config.anomaly_duration_threshold = 10_000

  # Dashboard
  config.dashboard_auth = ->(controller) { true }
  config.dashboard_parent_controller = "ApplicationController"
end
```

## All Configuration Options

### Default Agent Settings

| Option | Default | Description |
|--------|---------|-------------|
| `default_model` | `"gemini-2.0-flash"` | Default LLM model for agents |
| `default_temperature` | `0.0` | Default temperature (0.0-2.0) |
| `default_timeout` | `60` | Default request timeout in seconds |
| `default_streaming` | `false` | Enable streaming by default |
| `default_thinking` | `nil` | Default thinking config (e.g., `{ effort: :medium }`) |

```ruby
config.default_model = "gpt-4o"
config.default_temperature = 0.7
config.default_timeout = 120
config.default_streaming = true
config.default_thinking = nil  # Or { effort: :medium } to enable globally
```

### Extended Thinking

Configure default thinking/reasoning behavior:

```ruby
# Disable thinking by default (recommended)
config.default_thinking = nil

# Enable medium-effort thinking for all agents
config.default_thinking = { effort: :medium }

# Enable with token budget
config.default_thinking = { effort: :high, budget: 10000 }
```

See [Thinking](Thinking) for details on supported providers and per-agent configuration.

### Caching

| Option | Default | Description |
|--------|---------|-------------|
| `cache_store` | `Rails.cache` | Cache store for agent responses |

```ruby
# Use Rails default cache
config.cache_store = Rails.cache

# Use memory store
config.cache_store = ActiveSupport::Cache::MemoryStore.new

# Use Redis
config.cache_store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL']
)
```

### Execution Logging

| Option | Default | Description |
|--------|---------|-------------|
| `async_logging` | `true` | Use background jobs for logging |
| `retention_period` | `30.days` | How long to keep execution records |
| `persist_prompts` | `true` | Store prompts in database |
| `persist_responses` | `true` | Store responses in database |

```ruby
config.async_logging = Rails.env.production?
config.retention_period = 90.days
config.persist_prompts = true
config.persist_responses = true
```

### Anomaly Detection

| Option | Default | Description |
|--------|---------|-------------|
| `anomaly_cost_threshold` | `5.00` | Alert if execution costs more (in dollars) |
| `anomaly_duration_threshold` | `10_000` | Alert if execution takes longer (in ms) |

```ruby
config.anomaly_cost_threshold = 1.00
config.anomaly_duration_threshold = 5_000
```

### Dashboard

| Option | Default | Description |
|--------|---------|-------------|
| `dashboard_auth` | `->(_) { true }` | Authentication proc |
| `dashboard_parent_controller` | `"ApplicationController"` | Parent controller class |
| `dashboard_per_page` | `25` | Items per page in lists |
| `dashboard_recent_executions` | `10` | Recent executions on overview |

```ruby
# Require admin access
config.dashboard_auth = ->(controller) {
  controller.current_user&.admin?
}

# Use HTTP Basic Auth
config.dashboard_auth = ->(controller) {
  controller.authenticate_or_request_with_http_basic do |user, pass|
    user == ENV['ADMIN_USER'] && pass == ENV['ADMIN_PASS']
  end
}

# Inherit from custom controller
config.dashboard_parent_controller = "Admin::BaseController"
```

### Budget Controls

```ruby
config.budgets = {
  # Global limits
  global_daily: 100.0,
  global_monthly: 2000.0,

  # Per-agent limits
  per_agent_daily: {
    "ExpensiveAgent" => 50.0,
    "CheapAgent" => 5.0
  },
  per_agent_monthly: {
    "ExpensiveAgent" => 500.0
  },

  # Enforcement mode: :hard or :soft
  enforcement: :hard
}
```

See [Budget Controls](Budget-Controls) for details.

### Alerts

```ruby
config.alerts = {
  on_events: [
    :budget_soft_cap,
    :budget_hard_cap,
    :breaker_open
  ],
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL'],
  webhook_url: "https://your-app.com/webhooks/llm-alerts",
  custom: ->(event, payload) {
    MyNotificationService.notify(event, payload)
  }
}
```

See [Alerts](Alerts) for details.

### PII Redaction

```ruby
config.redaction = {
  fields: %w[ssn credit_card phone_number],
  patterns: [
    /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
    /\b\d{16}\b/              # Credit card
  ],
  placeholder: "[REDACTED]",
  max_value_length: 1000
}
```

See [PII Redaction](PII-Redaction) for details.

### Async/Fiber Concurrency

| Option | Default | Description |
|--------|---------|-------------|
| `async_max_concurrency` | `10` | Maximum concurrent operations for batch processing |

```ruby
# Configure concurrent operation limit
config.async_max_concurrency = 20
```

To use async features, add the async gem to your Gemfile:

```ruby
gem 'async', '~> 2.0'
```

See [Async/Fiber](Async-Fiber) for details.

## Environment-Specific Configuration

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Common settings
  config.default_model = "gpt-4o"

  if Rails.env.production?
    config.async_logging = true
    config.dashboard_auth = ->(c) { c.current_user&.admin? }
    config.budgets = {
      global_daily: 100.0,
      enforcement: :hard
    }
  else
    config.async_logging = false
    config.dashboard_auth = ->(_) { true }
  end
end
```

## Per-Agent Configuration

Agents can override defaults:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "claude-3-5-sonnet"      # Override default model
    temperature 0.7                 # Override default temperature
    timeout 120                     # Override default timeout
    cache 1.hour                    # Enable caching
    streaming true                  # Enable streaming
  end
end
```

## Complete Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_model` | String | `"gemini-2.0-flash"` | Default LLM model |
| `default_temperature` | Float | `0.0` | Default temperature (0.0-2.0) |
| `default_timeout` | Integer | `60` | Request timeout in seconds |
| `default_streaming` | Boolean | `false` | Enable streaming by default |
| `default_tools` | Array | `[]` | Default tools for all agents |
| `default_thinking` | Hash | `nil` | Default thinking config (e.g., `{effort: :medium}`) |
| `default_retries` | Hash | `{max: 0}` | Default retry configuration |
| `default_fallback_models` | Array | `[]` | Default fallback models |
| `default_total_timeout` | Integer | `nil` | Default total timeout |
| `default_embedding_model` | String | `"text-embedding-3-small"` | Default embedding model |
| `default_embedding_dimensions` | Integer | `nil` | Default embedding dimensions |
| `default_embedding_batch_size` | Integer | `100` | Default batch size for embeddings |
| `track_embeddings` | Boolean | `true` | Track embedding executions |
| `default_moderation_model` | String | `"omni-moderation-latest"` | Default moderation model |
| `default_moderation_threshold` | Float | `nil` | Default moderation threshold (0.0-1.0) |
| `default_moderation_action` | Symbol | `:block` | Default action: `:block`, `:raise`, `:warn`, `:log` |
| `track_moderation` | Boolean | `true` | Track moderation to executions table |
| `default_transcription_model` | String | `"whisper-1"` | Default transcription model |
| `track_transcriptions` | Boolean | `true` | Track transcription executions |
| `default_tts_provider` | Symbol | `:openai` | Default TTS provider |
| `default_tts_model` | String | `"tts-1"` | Default TTS model |
| `default_tts_voice` | String | `"nova"` | Default TTS voice |
| `track_speech` | Boolean | `true` | Track TTS executions |
| `async_logging` | Boolean | `true` | Log executions via background job |
| `retention_period` | Duration | `30.days` | Execution record retention |
| `cache_store` | Cache | `Rails.cache` | Custom cache store |
| `budgets` | Hash | `nil` | Budget configuration |
| `alerts` | Hash | `nil` | Alert configuration |
| `redaction` | Hash | `nil` | PII redaction configuration |
| `persist_prompts` | Boolean | `true` | Store prompts in executions |
| `persist_responses` | Boolean | `true` | Store responses in executions |
| `multi_tenancy_enabled` | Boolean | `false` | Enable multi-tenancy |
| `tenant_resolver` | Proc | `-> { nil }` | Returns current tenant ID |
| `dashboard_parent_controller` | String | `"ApplicationController"` | Dashboard controller parent |
| `dashboard_auth` | Proc | `->(_) { true }` | Custom auth lambda |
| `dashboard_per_page` | Integer | `25` | Dashboard records per page |
| `dashboard_recent_executions` | Integer | `10` | Dashboard recent executions |
| `anomaly_cost_threshold` | Float | `5.00` | Cost anomaly threshold (USD) |
| `anomaly_duration_threshold` | Integer | `10_000` | Duration anomaly threshold (ms) |
| `job_retry_attempts` | Integer | `3` | Background job retries |
| `async_max_concurrency` | Integer | `10` | Max concurrent operations for async batch |

## Resetting Configuration

For testing:

```ruby
# Reset to defaults
RubyLLM::Agents.reset_configuration!

# Then reconfigure
RubyLLM::Agents.configure do |config|
  config.async_logging = false
end
```

## Related Pages

- [Budget Controls](Budget-Controls) - Cost limits
- [Alerts](Alerts) - Notification setup
- [PII Redaction](PII-Redaction) - Data protection
- [Multi-Tenancy](Multi-Tenancy) - Tenant isolation
- [Async/Fiber](Async-Fiber) - Concurrent execution
- [Dashboard](Dashboard) - Monitoring UI
