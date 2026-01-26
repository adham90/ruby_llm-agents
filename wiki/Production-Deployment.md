# Production Deployment

Best practices for deploying RubyLLM::Agents to production.

## Configuration Checklist

### 1. Async Logging

```ruby
RubyLLM::Agents.configure do |config|
  config.async_logging = true  # Required for production
end
```

### 2. Background Job Processor

Ensure a job processor is running:

```bash
# Solid Queue (Rails 7.1+)
bin/jobs

# Or Sidekiq
bundle exec sidekiq
```

### 3. Dashboard Authentication

```ruby
config.dashboard_auth = ->(controller) {
  controller.current_user&.admin?
}
```

### 4. Budget Limits

```ruby
config.budgets = {
  global_daily: 500.0,
  global_monthly: 10000.0,
  enforcement: :hard
}
```

### 5. Alerts

```ruby
config.alerts = {
  on_events: [:budget_hard_cap, :breaker_open],
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
}
```

### 6. PII Redaction

```ruby
config.redaction = {
  fields: %w[ssn credit_card email phone],
  patterns: [/\b\d{3}-\d{2}-\d{4}\b/]
}
```

## Complete Production Configuration

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Performance
  config.async_logging = true
  config.cache_store = Rails.cache

  # Defaults
  config.default_model = "gpt-4o"
  config.default_temperature = 0.0
  config.default_timeout = 60

  # Data Management
  config.retention_period = 90.days
  config.persist_prompts = true
  config.persist_responses = true

  # Security
  config.redaction = {
    fields: %w[password token api_key ssn credit_card],
    patterns: [/\b\d{3}-\d{2}-\d{4}\b/],
    placeholder: "[REDACTED]"
  }

  # Cost Control
  config.budgets = {
    global_daily: 500.0,
    global_monthly: 10000.0,
    per_agent_daily: {
      "ExpensiveAgent" => 100.0
    },
    enforcement: :hard,
    soft_cap_percentage: 80
  }

  # Anomaly Detection
  config.anomaly_cost_threshold = 10.00
  config.anomaly_duration_threshold = 30_000

  # Alerts
  config.alerts = {
    on_events: [
      :budget_soft_cap,
      :budget_hard_cap,
      :breaker_open,
      :anomaly_cost
    ],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL'],
    webhook_url: ENV['ALERT_WEBHOOK_URL']
  }

  # Dashboard
  config.dashboard_auth = ->(controller) {
    controller.current_user&.admin?
  }
  config.dashboard_per_page = 50
end
```

## Environment Variables

```bash
# API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...

# Alerts
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
ALERT_WEBHOOK_URL=https://your-app.com/webhooks/llm

# Redis (for caching)
REDIS_URL=redis://localhost:6379/1

# Database
DATABASE_URL=postgres://...
```

## Database Setup

### Indexes

Verify indexes exist:

```bash
rails db:migrate:status | grep ruby_llm
```

If indexes are missing:

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

### Connection Pool

Ensure adequate pool size for async logging:

```yaml
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>
```

## Caching

### Redis Setup

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  namespace: 'llm_cache',
  expires_in: 1.day
}

# config/initializers/ruby_llm_agents.rb
config.cache_store = Rails.cache
```

### Cache Warming

Pre-populate cache for common queries:

```ruby
# lib/tasks/cache.rake
namespace :llm do
  task warm_cache: :environment do
    CommonQueries.each do |query|
      SearchAgent.call(query: query)
    end
  end
end
```

## Monitoring

### Application Performance Monitoring

```ruby
# Add to agents for APM integration
class ApplicationAgent < RubyLLM::Agents::Base
  def call
    NewRelic::Agent::Tracer.in_transaction(
      name: "LLM/#{self.class.name}",
      category: :task
    ) do
      super
    end
  end
end
```

### Metrics

```ruby
# Track key metrics
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution") do |*, payload|
  StatsD.timing("llm.duration", payload[:duration_ms])
  StatsD.increment("llm.executions", tags: ["agent:#{payload[:agent]}"])
  StatsD.gauge("llm.cost", payload[:cost])
end
```

### Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def llm
    # Check LLM connectivity
    result = HealthCheckAgent.call(message: "ping", timeout: 5)

    if result.success?
      render json: { status: "ok", latency_ms: result.duration_ms }
    else
      render json: { status: "error" }, status: :service_unavailable
    end
  rescue => e
    render json: { status: "error", message: e.message }, status: :service_unavailable
  end
end
```

## Scaling

### Horizontal Scaling

Agents are stateless and scale horizontally:

```yaml
# kubernetes deployment
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: rails
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
```

### Background Job Scaling

Scale job workers independently:

```yaml
# Sidekiq deployment
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: sidekiq
          command: ["bundle", "exec", "sidekiq"]
```

### Rate Limit Handling

Configure retry behavior for rate limits:

```ruby
class ProductionAgent < ApplicationAgent
  retries max: 5, backoff: :exponential, max_delay: 60.0
  fallback_models "gpt-4o-mini", "claude-3-haiku"
  circuit_breaker errors: 10, within: 60, cooldown: 300
end
```

## Data Retention

### Automatic Cleanup

```ruby
# lib/tasks/maintenance.rake
namespace :llm do
  task cleanup: :environment do
    retention = RubyLLM::Agents.configuration.retention_period

    deleted = RubyLLM::Agents::Execution
      .where("created_at < ?", retention.ago)
      .delete_all

    Rails.logger.info("Deleted #{deleted} old executions")
  end
end
```

Schedule with cron:

```ruby
# config/schedule.rb (whenever gem)
every 1.day, at: '3:00 am' do
  rake "llm:cleanup"
end
```

### Archiving

```ruby
# Archive to S3 before deletion
namespace :llm do
  task archive: :environment do
    old_executions = RubyLLM::Agents::Execution
      .where("created_at < ?", 90.days.ago)

    S3Client.upload(
      key: "llm-archive/#{Date.today}.json.gz",
      body: compress(old_executions.to_json)
    )

    old_executions.delete_all
  end
end
```

## Security Checklist

- [ ] Dashboard requires authentication
- [ ] API keys in environment variables (not code)
- [ ] PII redaction configured
- [ ] HTTPS enforced
- [ ] Rate limiting in place
- [ ] Budget limits set
- [ ] Alert notifications configured
- [ ] Logs don't contain sensitive data
- [ ] Database encrypted at rest
- [ ] Network traffic encrypted (TLS)

## Disaster Recovery

### Backup Strategy

```ruby
# Backup executions table
pg_dump -t ruby_llm_agents_executions > backup.sql
```

### Failover

Configure multiple providers:

```ruby
class CriticalAgent < ApplicationAgent
  model "gpt-4o"
  fallback_models "claude-3-5-sonnet", "gemini-2.0-flash"
end
```

### Recovery Testing

Regularly test:
1. Database restore
2. Provider failover
3. Circuit breaker recovery

## Related Pages

- [Configuration](Configuration) - Full config reference
- [Background Jobs](Background-Jobs) - Job processor setup
- [Budget Controls](Budget-Controls) - Cost management
- [Troubleshooting](Troubleshooting) - Common issues
