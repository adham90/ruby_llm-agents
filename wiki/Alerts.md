# Alerts

Get notified about budget thresholds, circuit breaker events, and anomalies.

## Quick Setup

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
  }
end
```

## Alert Events

| Event | Trigger |
|-------|---------|
| `budget_soft_cap` | Budget reaches soft cap percentage |
| `budget_hard_cap` | Budget exceeded (with hard enforcement) |
| `breaker_open` | Circuit breaker opens |
| `anomaly_cost` | Execution cost exceeds threshold |
| `anomaly_duration` | Execution duration exceeds threshold |

## Notification Channels

### Slack

```ruby
config.alerts = {
  on_events: [:budget_soft_cap, :budget_hard_cap],
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
}
```

Slack message format:
```
🚨 RubyLLM::Agents Alert

Event: budget_soft_cap
Agent: ExpensiveAgent
Details:
  Scope: global_daily
  Limit: $100.00
  Current: $85.00
  Percentage: 85%

Time: 2024-01-15 10:30:00 UTC
```

### Webhook

Send alerts to any HTTP endpoint:

```ruby
config.alerts = {
  on_events: [:budget_hard_cap],
  webhook_url: "https://your-app.com/webhooks/llm-alerts"
}
```

Webhook payload:
```json
{
  "event": "budget_hard_cap",
  "agent_type": "ExpensiveAgent",
  "payload": {
    "scope": "global_daily",
    "limit": 100.0,
    "current": 105.50
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Custom Handler

```ruby
config.alerts = {
  on_events: [:breaker_open, :budget_hard_cap],
  custom: ->(event, payload) {
    case event
    when :budget_hard_cap
      PagerDuty.trigger(
        severity: "critical",
        summary: "LLM Budget Exceeded",
        details: payload
      )

    when :breaker_open
      Slack.notify(
        channel: "#ops",
        text: "Circuit breaker opened for #{payload[:model_id]}"
      )
    end

    # Log all alerts
    Rails.logger.warn("Alert: #{event} - #{payload}")
  }
}
```

### Multiple Channels

```ruby
config.alerts = {
  on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open],
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL'],
  webhook_url: ENV['WEBHOOK_URL'],
  custom: ->(event, payload) {
    MyMetricsService.record(event, payload)
  }
}
```

## Event Payloads

### Budget Events

```ruby
# budget_soft_cap
{
  scope: :global_daily,
  limit: 100.0,
  current: 85.0,
  remaining: 15.0,
  percentage_used: 85.0,
  agent_type: "MyAgent"  # nil for global
}

# budget_hard_cap
{
  scope: :per_agent_daily,
  limit: 50.0,
  current: 52.50,
  agent_type: "ExpensiveAgent"
}
```

### Circuit Breaker Events

```ruby
# breaker_open
{
  agent_type: "MyAgent",
  model_id: "gpt-4o",
  failure_count: 10,
  window_seconds: 60,
  cooldown_seconds: 300
}
```

### Anomaly Events

```ruby
# anomaly_cost
{
  agent_type: "MyAgent",
  execution_id: 12345,
  cost: 5.50,
  threshold: 5.00
}

# anomaly_duration
{
  agent_type: "MyAgent",
  execution_id: 12345,
  duration_ms: 15000,
  threshold_ms: 10000
}
```

## Anomaly Detection

### Cost Anomalies

```ruby
RubyLLM::Agents.configure do |config|
  config.anomaly_cost_threshold = 5.00  # Alert if > $5 per execution

  config.alerts = {
    on_events: [:anomaly_cost],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
  }
end
```

### Duration Anomalies

```ruby
config.anomaly_duration_threshold = 10_000  # Alert if > 10 seconds

config.alerts = {
  on_events: [:anomaly_duration],
  custom: ->(event, payload) {
    Rails.logger.warn("Slow execution: #{payload[:duration_ms]}ms")
  }
}
```

## Alert Filtering

### By Agent Type

```ruby
config.alerts = {
  on_events: [:budget_hard_cap],
  filter: ->(event, payload) {
    # Only alert for production-critical agents
    %w[CriticalAgent ImportantAgent].include?(payload[:agent_type])
  },
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
}
```

### By Severity

```ruby
config.alerts = {
  on_events: [:budget_soft_cap, :budget_hard_cap],
  custom: ->(event, payload) {
    severity = case event
               when :budget_hard_cap then "critical"
               when :budget_soft_cap then "warning"
               else "info"
               end

    AlertService.notify(severity: severity, event: event, payload: payload)
  }
}
```

## Alert Rate Limiting

Prevent alert floods:

```ruby
config.alerts = {
  on_events: [:breaker_open],
  rate_limit: {
    window: 5.minutes,
    max_alerts: 3
  },
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
}
```

## ActiveSupport::Notifications

All alerts also emit ActiveSupport::Notifications:

```ruby
# Subscribe to alerts
ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert") do |name, start, finish, id, payload|
  Rails.logger.info("Alert: #{payload[:event]} - #{payload[:data]}")
end
```

Use for custom integrations:

```ruby
# In an initializer
ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert") do |*, payload|
  case payload[:event]
  when :budget_hard_cap
    StatsD.increment("llm.budget.exceeded")
  when :breaker_open
    StatsD.increment("llm.circuit_breaker.opened")
  end
end
```

## Testing Alerts

```ruby
# In tests, verify alerts are triggered
RSpec.describe "Budget Alerts" do
  it "sends alert when budget exceeded" do
    allow(RubyLLM::Agents::AlertNotifier).to receive(:notify)

    # Trigger budget exceeded
    50.times { ExpensiveAgent.call(query: "test") }

    expect(RubyLLM::Agents::AlertNotifier)
      .to have_received(:notify)
      .with(:budget_hard_cap, hash_including(scope: :global_daily))
  end
end
```

## Best Practices

### Alert on What Matters

```ruby
# Good: Actionable events
on_events: [:budget_hard_cap, :breaker_open]

# Avoid: Too noisy
on_events: [:every_execution]  # Don't do this
```

### Use Appropriate Channels

```ruby
# Critical: PagerDuty/OpsGenie
custom: ->(event, payload) {
  if event == :budget_hard_cap
    PagerDuty.trigger(...)
  end
}

# Informational: Slack
slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
```

### Include Context

```ruby
custom: ->(event, payload) {
  message = {
    event: event,
    payload: payload,
    environment: Rails.env,
    server: Socket.gethostname,
    timestamp: Time.current.iso8601
  }

  WebhookService.post(message)
}
```

### Monitor Alert Health

```ruby
# Track that alerts are working
custom: ->(event, payload) {
  StatsD.increment("llm.alerts.sent", tags: ["event:#{event}"])
  ActualNotificationService.send(event, payload)
}
```

## Related Pages

- [Budget Controls](Budget-Controls) - Budget configuration
- [Circuit Breakers](Circuit-Breakers) - Breaker events
- [Configuration](Configuration) - Full setup guide
- [Troubleshooting](Troubleshooting) - Alert issues
