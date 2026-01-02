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

```ruby
config.default_model = "gpt-4o"
config.default_temperature = 0.7
config.default_timeout = 120
config.default_streaming = true
```

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
class MyAgent < ApplicationAgent
  model "claude-3-5-sonnet"      # Override default model
  temperature 0.7                 # Override default temperature
  timeout 120                     # Override default timeout
  cache 1.hour                    # Enable caching
  streaming true                  # Enable streaming
end
```

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
