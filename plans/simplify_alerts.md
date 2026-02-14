# Plan: Simplify Alerts and Notifier Integrations

## Goal

Reduce core gem surface area by removing built-in notifier integrations (Slack/Webhook/Email), while preserving alert functionality via a simple proc-based hook.

## Scope Decisions

- **Keep**: Alert event emission, `ActiveSupport::Notifications` emission, dashboard alert feed
- **Remove**: Built-in Slack formatting, webhook HTTP client, email mailer, all notifier-specific config
- **Add**: Single `config.on_alert` proc

## Current State Inventory

### Files to Modify or Remove

| File | Action | Notes |
|------|--------|-------|
| `lib/ruby_llm/agents/infrastructure/alert_manager.rb` | Simplify | Remove Slack/webhook/email methods, keep `notify`, AS::N emission |
| `lib/ruby_llm/agents/core/configuration.rb` | Modify | Replace `alerts` hash with `on_alert` proc |
| `app/mailers/ruby_llm/agents/alert_mailer.rb` | Delete | Email delivery removed |
| `app/views/ruby_llm/agents/alert_mailer/alert_notification.html.erb` | Delete | Email template |
| `app/views/ruby_llm/agents/alert_mailer/alert_notification.text.erb` | Delete | Email template |
| `app/views/ruby_llm/agents/dashboard/_alerts_feed.html.erb` | Keep | Dashboard display (uses cache, not notifiers) |
| `spec/lib/alert_manager_spec.rb` | Update | Remove notifier tests, add hook tests |
| `spec/mailers/ruby_llm/agents/alert_mailer_spec.rb` | Delete | Mailer spec |

### Configuration to Remove

```ruby
# Current hash-based config (remove entirely)
config.alerts = {
  slack_webhook_url: "...",
  webhook_url: "...",
  email_recipients: [...],
  email_events: [...],
  on_events: [...],
  custom: ->(event, payload) {}
}
```

### Helper Methods to Remove

In `Configuration`:
- `alerts_enabled?` - Remove (just check `on_alert.present?` where needed)
- `alert_events` - Remove (no filtering, all events fire)

---

## New Public API

### Configuration

```ruby
RubyLLM::Agents.configure do |config|
  config.on_alert = ->(event, payload) {
    case event
    when :budget_hard_cap
      Slack.notify("#alerts", "Budget exceeded: #{payload[:total_cost]}")
    when :breaker_open
      PagerDuty.trigger(payload)
    end
  }
end
```

Users filter events themselves - no magic, full control.

### ActiveSupport::Notifications (Always Emitted)

```ruby
# Subscribe to all alert events
ActiveSupport::Notifications.subscribe(/^ruby_llm_agents\.alert\./) do |name, start, finish, id, payload|
  event = name.sub("ruby_llm_agents.alert.", "").to_sym
  MyAlertService.handle(event, payload)
end

# Or subscribe to specific events
ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.budget_hard_cap") do |*args|
  # Handle budget alerts
end
```

---

## Event Catalog

### Event Types

| Event | Trigger | Severity |
|-------|---------|----------|
| `:budget_soft_cap` | Daily/monthly spend reaches soft limit | Warning |
| `:budget_hard_cap` | Daily/monthly spend exceeds hard limit | Critical |
| `:breaker_open` | Circuit breaker trips for an agent/model | Critical |
| `:breaker_closed` | Circuit breaker recovers | Info |
| `:agent_anomaly` | Execution exceeds cost/duration thresholds | Warning |

### Payload Schema

All events include these base keys:

```ruby
{
  event: Symbol,           # Event type (redundant but convenient)
  timestamp: Time,         # When the event occurred
  tenant_id: String|nil,   # Tenant ID if multi-tenancy enabled
}
```

#### `:budget_soft_cap` / `:budget_hard_cap`

```ruby
{
  limit: Float,            # The budget limit that was hit
  total_cost: Float,       # Current spend
  period: Symbol,          # :daily or :monthly
  scope: Symbol,           # :global or :per_agent
  agent_type: String|nil,  # Agent class name (if per_agent)
}
```

#### `:breaker_open` / `:breaker_closed`

```ruby
{
  agent_type: String,      # Agent class name
  model: String,           # Model identifier
  failure_count: Integer,  # Number of failures
  error: String|nil,       # Last error message (on open)
}
```

#### `:agent_anomaly`

```ruby
{
  agent_type: String,      # Agent class name
  model: String,           # Model identifier
  execution_id: Integer,   # Execution record ID
  total_cost: Float,       # Execution cost
  duration_ms: Integer,    # Execution duration
  threshold_type: Symbol,  # :cost or :duration
  threshold_value: Float,  # The threshold that was exceeded
}
```

---

## Implementation Steps

### Step 1: Update Configuration Class

**File**: `lib/ruby_llm/agents/core/configuration.rb`

1. Replace `alerts` accessor with:
   ```ruby
   attr_accessor :on_alert
   ```

2. Update `initialize`:
   ```ruby
   @on_alert = nil
   ```

3. Remove these methods entirely:
   - `alerts_enabled?`
   - `alert_events`

4. Remove the `alerts` attribute and all documentation referencing the hash structure.

### Step 2: Simplify AlertManager

**File**: `lib/ruby_llm/agents/infrastructure/alert_manager.rb`

Replace the entire module with:

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    module AlertManager
      class << self
        def notify(event, payload)
          full_payload = build_payload(event, payload)

          # Call user-provided handler (if set)
          call_handler(event, full_payload)

          # Always emit ActiveSupport::Notification
          emit_notification(event, full_payload)

          # Store in cache for dashboard display
          store_for_dashboard(event, full_payload)
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents::AlertManager] Failed: #{e.message}")
        end

        private

        def build_payload(event, payload)
          payload.merge(
            event: event,
            timestamp: Time.current,
            tenant_id: RubyLLM::Agents.configuration.current_tenant_id
          )
        end

        def call_handler(event, payload)
          handler = RubyLLM::Agents.configuration.on_alert
          return unless handler.respond_to?(:call)

          handler.call(event, payload)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::AlertManager] Handler failed: #{e.message}")
        end

        def emit_notification(event, payload)
          ActiveSupport::Notifications.instrument("ruby_llm_agents.alert.#{event}", payload)
        rescue StandardError
          # Ignore notification failures
        end

        def store_for_dashboard(event, payload)
          cache = RubyLLM::Agents.configuration.cache_store
          key = "ruby_llm_agents:alerts:recent"

          alerts = cache.read(key) || []
          alerts.unshift(
            type: event,
            message: format_message(event, payload),
            agent_type: payload[:agent_type],
            timestamp: payload[:timestamp]
          )
          alerts = alerts.first(50)

          cache.write(key, alerts, expires_in: 24.hours)
        rescue StandardError
          # Ignore cache failures
        end

        def format_message(event, payload)
          case event
          when :budget_soft_cap
            "Budget soft cap reached: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
          when :budget_hard_cap
            "Budget hard cap exceeded: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
          when :breaker_open
            "Circuit breaker opened for #{payload[:agent_type]}"
          when :breaker_closed
            "Circuit breaker closed for #{payload[:agent_type]}"
          when :agent_anomaly
            "Anomaly detected: #{payload[:threshold_type]} threshold exceeded"
          else
            event.to_s.humanize
          end
        end
      end
    end
  end
end
```

### Step 3: Delete Mailer Files

```bash
rm app/mailers/ruby_llm/agents/alert_mailer.rb
rm app/views/ruby_llm/agents/alert_mailer/alert_notification.html.erb
rm app/views/ruby_llm/agents/alert_mailer/alert_notification.text.erb
rm spec/mailers/ruby_llm/agents/alert_mailer_spec.rb
```

Also check for and remove `ApplicationMailer` if it only exists for alerts.

### Step 4: Update Tests

**File**: `spec/lib/alert_manager_spec.rb`

Remove tests for:
- `send_slack_alert`
- `send_webhook_alert`
- `send_email_alerts`
- `format_slack_message`
- `post_json`

Add tests for:
- `on_alert` proc is called with correct `(event, payload)`
- `ActiveSupport::Notifications` is emitted with correct event name
- No error raised when `on_alert` is nil
- Dashboard cache is populated correctly

### Step 5: Update Configuration Spec

**File**: `spec/lib/configuration_spec.rb`

- Remove tests for `alerts` hash structure
- Remove tests for `alerts_enabled?` and `alert_events`
- Add simple test that `on_alert` accepts a proc

### Step 6: Update Documentation

Update README and any wiki pages to show the new API:

```markdown
## Alerts

RubyLLM::Agents emits alerts for important governance events.

### Using a Handler Proc

```ruby
RubyLLM::Agents.configure do |config|
  config.on_alert = ->(event, payload) {
    case event
    when :budget_hard_cap
      Slack::Notifier.new(ENV["SLACK_WEBHOOK"]).ping(
        "Budget exceeded for #{payload[:agent_type]}: $#{payload[:total_cost]}"
      )
    when :breaker_open
      PagerDuty.trigger(
        summary: "Circuit breaker opened",
        source: payload[:agent_type],
        severity: "critical"
      )
    end
  }
end
```

### Using ActiveSupport::Notifications

All alerts are emitted as ActiveSupport::Notifications:

```ruby
# In an initializer
ActiveSupport::Notifications.subscribe(/^ruby_llm_agents\.alert\./) do |name, start, finish, id, payload|
  event = name.sub("ruby_llm_agents.alert.", "").to_sym
  Rails.logger.warn("[Alert] #{event}: #{payload.inspect}")
end
```
```

---

## Migration Guide

Add to CHANGELOG.md:

```markdown
## Breaking Changes

### Alerts Configuration

The `config.alerts` hash has been replaced with `config.on_alert`.

**Before:**
```ruby
config.alerts = {
  slack_webhook_url: ENV["SLACK_WEBHOOK"],
  webhook_url: ENV["WEBHOOK_URL"],
  email_recipients: ["admin@example.com"],
  on_events: [:budget_hard_cap],
  custom: ->(event, payload) { ... }
}
```

**After:**
```ruby
config.on_alert = ->(event, payload) {
  # Filter events yourself
  return unless [:budget_hard_cap, :breaker_open].include?(event)

  # Send to Slack (use slack-notifier gem)
  Slack::Notifier.new(ENV["SLACK_WEBHOOK"]).ping("Alert: #{event}")

  # Send to webhook (use http gem)
  HTTP.post(ENV["WEBHOOK_URL"], json: payload)

  # Send email (your own mailer)
  MyAlertMailer.notify(event, payload).deliver_later
}
```

If you were using `config.alerts[:custom]`, just move that proc to `config.on_alert`.
```

---

## Acceptance Criteria

- [ ] No built-in Slack/webhook/email code remains in the gem
- [ ] `config.on_alert` proc receives `(event, payload)` for all alert events
- [ ] `ActiveSupport::Notifications` emits `ruby_llm_agents.alert.<event>` for all events
- [ ] Dashboard alerts feed continues to work (cache-based)
- [ ] All tests pass
- [ ] CHANGELOG documents the breaking change with migration guide

---

## Files Changed Summary

| Action | Count | Files |
|--------|-------|-------|
| Delete | 4 | alert_mailer.rb, 2 templates, mailer spec |
| Modify | 3 | alert_manager.rb, configuration.rb, alert_manager_spec.rb |
| Keep | 1 | _alerts_feed.html.erb |
