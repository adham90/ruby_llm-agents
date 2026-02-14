# Alerts

Get notified about budget thresholds, circuit breaker events, and anomalies.

## Quick Setup

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.on_alert = ->(event, payload) {
    case event
    when :budget_hard_cap
      Slack::Notifier.new(ENV['SLACK_WEBHOOK']).ping("Budget exceeded: $#{payload[:total_cost]}")
    when :breaker_open
      PagerDuty.trigger(summary: "Circuit breaker opened for #{payload[:agent_type]}")
    end
  }
end
```

## Alert Events

| Event | Trigger | Severity |
|-------|---------|----------|
| `:budget_soft_cap` | Budget reaches soft limit | Warning |
| `:budget_hard_cap` | Budget exceeded (hard enforcement) | Critical |
| `:breaker_open` | Circuit breaker opens | Critical |
| `:breaker_closed` | Circuit breaker recovers | Info |
| `:agent_anomaly` | Execution exceeds cost/duration thresholds | Warning |

## Handler Configuration

The `on_alert` handler receives all events. Filter in your handler as needed:

```ruby
config.on_alert = ->(event, payload) {
  # Filter events you care about
  return unless [:budget_hard_cap, :breaker_open].include?(event)

  case event
  when :budget_hard_cap
    PagerDuty.trigger(
      severity: "critical",
      summary: "LLM Budget Exceeded",
      details: payload
    )

  when :breaker_open
    Slack::Notifier.new(ENV['SLACK_WEBHOOK']).ping(
      "Circuit breaker opened for #{payload[:agent_type]} (#{payload[:model_id]})"
    )
  end

  # Log all alerts
  Rails.logger.warn("[Alert] #{event}: #{payload}")
}
```

## Event Payloads

All events include these base fields:

```ruby
{
  event: Symbol,           # Event type
  timestamp: Time,         # When the event occurred
  tenant_id: String|nil,   # Tenant ID if multi-tenancy enabled
}
```

### Budget Events

```ruby
# :budget_soft_cap / :budget_hard_cap
{
  scope: :global_daily,    # :global_daily, :global_monthly, :per_agent_daily, :per_agent_monthly
  limit: 100.0,            # Budget limit
  total_cost: 105.50,      # Current spend
  agent_type: "MyAgent",   # Agent class (nil for global)
  tenant_id: "tenant-123"  # If multi-tenancy enabled
}
```

### Circuit Breaker Events

```ruby
# :breaker_open
{
  agent_type: "MyAgent",
  model_id: "gpt-4o",
  tenant_id: "tenant-123",
  errors: 10,              # Error threshold
  within: 60,              # Window in seconds
  cooldown: 300            # Cooldown in seconds
}

# :breaker_closed
{
  agent_type: "MyAgent",
  model_id: "gpt-4o",
  tenant_id: "tenant-123"
}
```

### Anomaly Events

```ruby
# :agent_anomaly
{
  agent_type: "MyAgent",
  model: "gpt-4o",
  execution_id: 12345,
  total_cost: 5.50,
  duration_ms: 15000,
  threshold_type: :cost,   # :cost or :duration
  threshold_value: 5.00
}
```

## ActiveSupport::Notifications

All alerts are also emitted as ActiveSupport::Notifications, providing an alternative subscription mechanism:

```ruby
# Subscribe to all alerts
ActiveSupport::Notifications.subscribe(/^ruby_llm_agents\.alert\./) do |name, start, finish, id, payload|
  event = name.sub("ruby_llm_agents.alert.", "").to_sym
  Rails.logger.info("[Alert] #{event}: #{payload}")
end

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.budget_hard_cap") do |*, payload|
  StatsD.increment("llm.budget.exceeded")
  AlertService.critical(payload)
end

ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.breaker_open") do |*, payload|
  StatsD.increment("llm.circuit_breaker.opened")
end
```

## Integration Examples

### Slack

```ruby
config.on_alert = ->(event, payload) {
  notifier = Slack::Notifier.new(ENV['SLACK_WEBHOOK'])

  message = case event
  when :budget_soft_cap
    ":warning: Budget soft cap reached: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
  when :budget_hard_cap
    ":no_entry: Budget exceeded: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
  when :breaker_open
    ":rotating_light: Circuit breaker opened for #{payload[:agent_type]}"
  end

  notifier.ping(message) if message
}
```

### PagerDuty

```ruby
config.on_alert = ->(event, payload) {
  return unless [:budget_hard_cap, :breaker_open].include?(event)

  PagerDuty.trigger(
    routing_key: ENV['PAGERDUTY_ROUTING_KEY'],
    event_action: 'trigger',
    payload: {
      summary: "RubyLLM Alert: #{event}",
      severity: event == :budget_hard_cap ? 'critical' : 'warning',
      source: payload[:agent_type] || 'global',
      custom_details: payload
    }
  )
}
```

### Webhooks

```ruby
config.on_alert = ->(event, payload) {
  HTTP.post(
    ENV['WEBHOOK_URL'],
    json: {
      event: event,
      payload: payload,
      environment: Rails.env,
      timestamp: Time.current.iso8601
    }
  )
}
```

### Email

```ruby
config.on_alert = ->(event, payload) {
  return unless [:budget_hard_cap].include?(event)

  AdminMailer.alert_notification(
    event: event,
    payload: payload
  ).deliver_later
}
```

### Multiple Channels

```ruby
config.on_alert = ->(event, payload) {
  # Always log
  Rails.logger.warn("[Alert] #{event}: #{payload}")

  # Track metrics
  StatsD.increment("llm.alerts", tags: ["event:#{event}"])

  # Route by severity
  case event
  when :budget_hard_cap, :breaker_open
    PagerDuty.trigger(summary: "Critical: #{event}")
    Slack.notify("#ops-critical", "#{event}: #{payload[:agent_type]}")
  when :budget_soft_cap
    Slack.notify("#ops-warnings", "Budget warning: #{payload[:total_cost]}")
  end
}
```

## Anomaly Detection

Configure thresholds to detect unusual executions:

```ruby
RubyLLM::Agents.configure do |config|
  # Alert if execution costs > $5
  config.anomaly_cost_threshold = 5.00

  # Alert if execution takes > 10 seconds
  config.anomaly_duration_threshold = 10_000

  config.on_alert = ->(event, payload) {
    if event == :agent_anomaly
      Rails.logger.warn("Anomaly: #{payload[:threshold_type]} exceeded for #{payload[:agent_type]}")
    end
  }
end
```

## Testing Alerts

```ruby
RSpec.describe "Budget Alerts" do
  it "sends alert when budget exceeded" do
    allow(RubyLLM::Agents::AlertManager).to receive(:notify)

    # Trigger budget exceeded condition
    50.times { ExpensiveAgent.call(query: "test") }

    expect(RubyLLM::Agents::AlertManager)
      .to have_received(:notify)
      .with(:budget_hard_cap, hash_including(scope: :global_daily))
  end

  it "calls on_alert handler" do
    received = nil
    RubyLLM::Agents.configure do |config|
      config.on_alert = ->(event, payload) { received = [event, payload] }
    end

    RubyLLM::Agents::AlertManager.notify(:budget_soft_cap, { limit: 100, total_cost: 85 })

    expect(received[0]).to eq(:budget_soft_cap)
    expect(received[1][:limit]).to eq(100)
  end
end
```

## Best Practices

### Filter Events in Your Handler

```ruby
# Good: Handle only what you need
config.on_alert = ->(event, payload) {
  return unless [:budget_hard_cap, :breaker_open].include?(event)
  # Handle critical events
}
```

### Use Appropriate Channels by Severity

```ruby
config.on_alert = ->(event, payload) {
  case event
  when :budget_hard_cap, :breaker_open
    PagerDuty.trigger(...)  # Wake someone up
  when :budget_soft_cap, :agent_anomaly
    Slack.notify(...)       # Informational
  end
}
```

### Include Context

```ruby
config.on_alert = ->(event, payload) {
  enriched_payload = payload.merge(
    environment: Rails.env,
    server: Socket.gethostname,
    git_sha: ENV['GIT_SHA']
  )

  AlertService.send(event, enriched_payload)
}
```

### Handle Errors Gracefully

```ruby
config.on_alert = ->(event, payload) {
  begin
    ExternalService.notify(event, payload)
  rescue => e
    Rails.logger.error("Alert delivery failed: #{e.message}")
    # Alerts shouldn't break your app
  end
}
```

## Dashboard

Recent alerts are displayed on the dashboard. They're stored in cache for 24 hours.

## Related Pages

- [Budget Controls](Budget-Controls) - Budget configuration
- [Circuit Breakers](Circuit-Breakers) - Breaker events
- [Configuration](Configuration) - Full setup guide
- [Troubleshooting](Troubleshooting) - Alert issues
