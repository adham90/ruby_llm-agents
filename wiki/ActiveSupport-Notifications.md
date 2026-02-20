# ActiveSupport Notifications

RubyLLM::Agents emits [ActiveSupport::Notifications](https://guides.rubyonrails.org/active_support_instrumentation.html) events throughout the middleware pipeline, giving you real-time observability into every execution, cache interaction, budget check, and reliability event.

Notifications fire **independently of database tracking** — even if `track_executions` is disabled, subscribers still receive events.

## Event Taxonomy

All events use the `ruby_llm_agents.` prefix and are organized by domain:

| Event | Domain | Description |
|-------|--------|-------------|
| `ruby_llm_agents.execution.start` | Execution | Agent execution begins |
| `ruby_llm_agents.execution.complete` | Execution | Agent execution succeeded |
| `ruby_llm_agents.execution.error` | Execution | Agent execution failed |
| `ruby_llm_agents.cache.hit` | Cache | Response served from cache |
| `ruby_llm_agents.cache.miss` | Cache | Cache lookup found no match |
| `ruby_llm_agents.cache.write` | Cache | Response written to cache |
| `ruby_llm_agents.budget.check` | Budget | Budget check performed before execution |
| `ruby_llm_agents.budget.exceeded` | Budget | Execution blocked by budget limit |
| `ruby_llm_agents.budget.record` | Budget | Spend recorded after execution |
| `ruby_llm_agents.reliability.fallback_used` | Reliability | Fallback model succeeded after primary failed |
| `ruby_llm_agents.reliability.all_models_exhausted` | Reliability | All models (primary + fallbacks) failed |

## Execution Events

### `execution.start`

Fired when an agent execution begins, before the LLM call.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:model` | String | Configured model |
| `:tenant_id` | String/nil | Tenant identifier |
| `:execution_id` | Integer/nil | Database execution ID |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.start") do |*, payload|
  Rails.logger.info "[LLM] Starting #{payload[:agent_type]} with #{payload[:model]}"
end
```

### `execution.complete`

Fired when an agent execution succeeds.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:agent_type_symbol` | Symbol | Agent type (`:chat`, `:embed`, etc.) |
| `:execution_id` | Integer/nil | Database execution ID |
| `:model` | String | Configured model |
| `:model_used` | String | Model that actually ran |
| `:tenant_id` | String/nil | Tenant identifier |
| `:status` | String | `"success"` |
| `:duration_ms` | Integer | Execution time in milliseconds |
| `:input_tokens` | Integer | Prompt tokens |
| `:output_tokens` | Integer | Response tokens |
| `:total_tokens` | Integer | Sum of input + output |
| `:input_cost` | Float | Cost of input tokens |
| `:output_cost` | Float | Cost of output tokens |
| `:total_cost` | Float | Total execution cost |
| `:cached` | Boolean | Whether response came from cache |
| `:attempts_made` | Integer | Number of attempts (retries + fallbacks) |
| `:finish_reason` | String | `"stop"`, `"length"`, `"tool_calls"`, etc. |
| `:time_to_first_token_ms` | Integer/nil | TTFT (streaming only) |
| `:error_class` | nil | Always nil on success |
| `:error_message` | nil | Always nil on success |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*, payload|
  StatsD.timing("llm.duration", payload[:duration_ms])
  StatsD.increment("llm.executions", tags: [
    "agent:#{payload[:agent_type]}",
    "model:#{payload[:model_used]}"
  ])
  StatsD.gauge("llm.cost", payload[:total_cost])
  StatsD.histogram("llm.tokens", payload[:total_tokens])
end
```

### `execution.error`

Fired when an agent execution fails (after all retries and fallbacks are exhausted).

**Payload:** Same fields as `execution.complete`, but with:

| Field | Type | Description |
|-------|------|-------------|
| `:status` | String | `"error"` or `"timeout"` |
| `:error_class` | String | Exception class name |
| `:error_message` | String | Exception message |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.error") do |*, payload|
  StatsD.increment("llm.errors", tags: [
    "agent:#{payload[:agent_type]}",
    "error:#{payload[:error_class]}"
  ])

  if payload[:error_class] == "Timeout::Error"
    Slack::Notifier.new(ENV['SLACK_WEBHOOK']).ping(
      "Timeout in #{payload[:agent_type]} after #{payload[:duration_ms]}ms"
    )
  end
end
```

## Cache Events

### `cache.hit`

Fired when a cached response is returned instead of calling the LLM.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:cache_key` | String | The cache key that matched |

### `cache.miss`

Fired when a cache lookup finds no match and the LLM will be called.

**Payload:** Same as `cache.hit`.

### `cache.write`

Fired after a successful LLM response is written to cache.

**Payload:** Same as `cache.hit`.

```ruby
# Track cache hit rate
hits = 0
total = 0

ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.cache\.(hit|miss)/) do |name, *, payload|
  total += 1
  hits += 1 if name.end_with?(".hit")
  StatsD.gauge("llm.cache.hit_rate", hits.to_f / total) if total > 0
end
```

## Budget Events

### `budget.check`

Fired before execution when budget limits are checked.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:tenant_id` | String/nil | Tenant identifier |

### `budget.exceeded`

Fired when an execution is blocked because budget limits have been reached.

**Payload:** Same as `budget.check`.

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.budget.exceeded") do |*, payload|
  PagerDuty.trigger(
    summary: "Budget exceeded for #{payload[:agent_type]}",
    details: { tenant_id: payload[:tenant_id] }
  )
end
```

### `budget.record`

Fired after spend is recorded following a successful execution.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:tenant_id` | String/nil | Tenant identifier |
| `:total_cost` | Float | Cost recorded |
| `:total_tokens` | Integer | Tokens used |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.budget.record") do |*, payload|
  StatsD.increment("llm.spend", payload[:total_cost], tags: [
    "agent:#{payload[:agent_type]}",
    "tenant:#{payload[:tenant_id]}"
  ])
end
```

## Reliability Events

### `reliability.fallback_used`

Fired when the primary model fails and a fallback model succeeds.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:primary_model` | String | The model that failed |
| `:used_model` | String | The fallback model that succeeded |
| `:attempts_made` | Integer | Total attempts across all models |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.reliability.fallback_used") do |*, payload|
  StatsD.increment("llm.fallback", tags: [
    "agent:#{payload[:agent_type]}",
    "primary:#{payload[:primary_model]}",
    "used:#{payload[:used_model]}"
  ])
end
```

### `reliability.all_models_exhausted`

Fired when all models (primary + fallbacks) fail, just before raising `AllModelsExhaustedError`.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `:agent_type` | String | Agent class name |
| `:models_tried` | Array | List of all models attempted |

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.reliability.all_models_exhausted") do |*, payload|
  Slack::Notifier.new(ENV['SLACK_WEBHOOK']).ping(
    ":rotating_light: All models exhausted for #{payload[:agent_type]}: #{payload[:models_tried].join(', ')}"
  )
end
```

## Subscribing to Events

### Single Event

```ruby
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*, payload|
  # Handle event
end
```

### Pattern Matching

Subscribe to all events in a domain:

```ruby
# All execution events (start, complete, error)
ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.execution\./) do |name, *, payload|
  Rails.logger.info "[LLM] #{name}: #{payload[:agent_type]}"
end

# All reliability events
ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.reliability\./) do |name, *, payload|
  Rails.logger.warn "[LLM] #{name}: #{payload[:agent_type]}"
end

# All events
ActiveSupport::Notifications.subscribe(/ruby_llm_agents\./) do |name, *, payload|
  Rails.logger.debug "[LLM] #{name}: #{payload.inspect}"
end
```

### Unsubscribing

```ruby
subscriber = ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*, payload|
  # Handle event
end

# Later
ActiveSupport::Notifications.unsubscribe(subscriber)
```

## Production Integration Examples

### StatsD / Datadog

```ruby
# config/initializers/ruby_llm_agents.rb
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*, payload|
  tags = ["agent:#{payload[:agent_type]}", "model:#{payload[:model_used]}"]
  StatsD.timing("llm.duration_ms", payload[:duration_ms], tags: tags)
  StatsD.increment("llm.executions.success", tags: tags)
  StatsD.histogram("llm.cost", payload[:total_cost], tags: tags)
  StatsD.histogram("llm.tokens", payload[:total_tokens], tags: tags)
end

ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.error") do |*, payload|
  tags = ["agent:#{payload[:agent_type]}", "error:#{payload[:error_class]}"]
  StatsD.increment("llm.executions.error", tags: tags)
end

ActiveSupport::Notifications.subscribe("ruby_llm_agents.reliability.fallback_used") do |*, payload|
  StatsD.increment("llm.fallback", tags: [
    "agent:#{payload[:agent_type]}",
    "from:#{payload[:primary_model]}",
    "to:#{payload[:used_model]}"
  ])
end
```

### Slack Alerts

```ruby
# config/initializers/ruby_llm_agents.rb
slack = Slack::Notifier.new(ENV['SLACK_WEBHOOK'])

ActiveSupport::Notifications.subscribe("ruby_llm_agents.budget.exceeded") do |*, payload|
  slack.ping(":money_with_wings: Budget exceeded for #{payload[:agent_type]} (tenant: #{payload[:tenant_id]})")
end

ActiveSupport::Notifications.subscribe("ruby_llm_agents.reliability.all_models_exhausted") do |*, payload|
  slack.ping(":rotating_light: All models exhausted for #{payload[:agent_type]}: #{payload[:models_tried].join(', ')}")
end
```

### Custom Logging

```ruby
# config/initializers/ruby_llm_agents.rb
ActiveSupport::Notifications.subscribe(/ruby_llm_agents\./) do |name, started, finished, id, payload|
  duration = ((finished - started) * 1000).round(2)
  Rails.logger.tagged("LLM") do
    Rails.logger.info "#{name} (#{duration}ms) #{payload.except(:error_message).inspect}"
  end
end
```

## Safety

All notification calls are wrapped in a `rescue` block to ensure that subscriber errors never break agent execution. If a subscriber raises an exception, the notification is silently dropped and execution continues normally.

```ruby
# This is safe — a buggy subscriber won't crash your agent
ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*, payload|
  raise "oops" # Will not affect agent execution
end
```

## Related Pages

- [Execution Tracking](Execution-Tracking) - Database-backed execution logging
- [Reliability](Reliability) - Retries, fallbacks, circuit breakers
- [Budget Controls](Budget-Controls) - Spending limits and alerts
- [Caching](Caching) - Response caching
- [Production Deployment](Production-Deployment) - Monitoring setup
- [Model Fallbacks](Model-Fallbacks) - Alerting on fallback usage
