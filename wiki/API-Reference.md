# API Reference

Complete class and method documentation for RubyLLM::Agents.

## RubyLLM::Agents::Base

The base class for all agents.

### Class Methods

#### `.model(name)`

Set the LLM model.

```ruby
model "gpt-4o"
```

#### `.temperature(value)`

Set response randomness (0.0-2.0).

```ruby
temperature 0.7
```

#### `.version(string)`

Set version for cache invalidation.

```ruby
version "1.0"
```

#### `.timeout(seconds)`

Set request timeout.

```ruby
timeout 60
```

#### `.cache(duration)`

Enable response caching.

```ruby
cache 1.hour
```

#### `.streaming(boolean)`

Enable/disable streaming.

```ruby
streaming true
```

#### `.param(name, options = {})`

Define a parameter.

```ruby
param :query, required: true
param :limit, default: 10
```

Options:
- `required: true` - Parameter must be provided
- `default: value` - Default value if not provided

#### `.retries(options)`

Configure retry behavior.

```ruby
retries max: 3, backoff: :exponential, base: 0.5, max_delay: 30.0
```

Options:
- `max:` - Maximum retry attempts
- `backoff:` - `:exponential` or `:constant`
- `base:` - Initial delay in seconds
- `max_delay:` - Maximum delay cap
- `on:` - Array of error classes to retry

#### `.fallback_models(*models)`

Set fallback model chain.

```ruby
fallback_models "gpt-4o-mini", "claude-3-haiku"
```

#### `.circuit_breaker(options)`

Configure circuit breaker.

```ruby
circuit_breaker errors: 10, within: 60, cooldown: 300
```

Options:
- `errors:` - Error count to trip breaker
- `within:` - Time window in seconds
- `cooldown:` - Cooldown period in seconds

#### `.total_timeout(seconds)`

Set maximum time for all attempts.

```ruby
total_timeout 30
```

#### `.call(**params, &block)`

Execute the agent.

```ruby
result = MyAgent.call(query: "test")
result = MyAgent.call(query: "test", dry_run: true)
result = MyAgent.call(query: "test", skip_cache: true)
result = MyAgent.call(query: "test", with: "image.jpg")
result = MyAgent.call(query: "test") { |chunk| print chunk }
```

### Instance Methods

#### `#call`

Execute the agent (called by `.call`).

#### `#system_prompt` (private)

Override to define system prompt.

```ruby
def system_prompt
  "You are a helpful assistant."
end
```

#### `#user_prompt` (private, required)

Override to define user prompt.

```ruby
def user_prompt
  "Process: #{query}"
end
```

#### `#schema` (private)

Override to define structured output.

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result
  end
end
```

#### `#process_response(response)` (private)

Override to post-process response.

```ruby
def process_response(response)
  result = super(response)
  result[:processed_at] = Time.current
  result
end
```

#### `#execution_metadata` (private)

Override to add custom metadata.

```ruby
def execution_metadata
  { user_id: user_id }
end
```

#### `#cache_key_data` (private)

Override to customize cache key.

```ruby
def cache_key_data
  { query: query }
end
```

---

## RubyLLM::Agents::Result

Returned by agent calls.

### Content Access

```ruby
result.content        # Parsed response
result[:key]          # Hash-style access
result.dig(:nested, :key)
```

### Token Information

```ruby
result.input_tokens   # Input token count
result.output_tokens  # Output token count
result.total_tokens   # Total tokens
result.cached_tokens  # Cached tokens
```

### Cost Information

```ruby
result.input_cost     # Input cost (USD)
result.output_cost    # Output cost (USD)
result.total_cost     # Total cost (USD)
```

### Model Information

```ruby
result.model_id       # Requested model
result.chosen_model_id # Actual model used
result.temperature    # Temperature setting
```

### Timing Information

```ruby
result.duration_ms    # Execution duration
result.started_at     # Start timestamp
result.completed_at   # End timestamp
result.time_to_first_token_ms # TTFT (streaming)
```

### Status Information

```ruby
result.success?       # Did it succeed?
result.finish_reason  # "stop", "length", etc.
result.streaming?     # Was streaming used?
result.truncated?     # Was output truncated?
```

### Reliability Information

```ruby
result.attempts_count # Number of attempts
result.used_fallback? # Was fallback used?
```

### Tool Calls

```ruby
result.tool_calls     # Array of tool calls
result.tool_calls_count
result.has_tool_calls?
```

### Full Data

```ruby
result.to_h           # All data as hash
```

---

## RubyLLM::Agents::Execution

ActiveRecord model for execution records.

### Scopes

```ruby
# Time-based
.today
.yesterday
.this_week
.this_month
.last_7_days
.last_30_days
.between(start, finish)

# Status
.successful
.failed
.status_error
.status_timeout
.status_running

# Agent/Model
.by_agent("AgentName")
.by_model("gpt-4o")
.by_version("1.0")

# Performance
.expensive(threshold)
.slow(milliseconds)
.high_token_usage(count)

# Streaming
.streaming
.non_streaming
```

### Attributes

```ruby
execution.agent_type      # String
execution.model_id        # String
execution.status          # String: success, error, timeout
execution.input_tokens    # Integer
execution.output_tokens   # Integer
execution.cached_tokens   # Integer
execution.input_cost      # Decimal
execution.output_cost     # Decimal
execution.total_cost      # Decimal
execution.duration_ms     # Integer
execution.parameters      # Hash (JSONB)
execution.system_prompt   # Text
execution.user_prompt     # Text
execution.response        # Text
execution.error_message   # Text
execution.error_class     # String
execution.metadata        # Hash (JSONB)
execution.streaming       # Boolean
execution.time_to_first_token_ms # Integer
execution.attempts        # Array (JSONB)
execution.chosen_model_id # String
execution.finish_reason   # String
execution.created_at      # DateTime
```

### Class Methods

```ruby
# Reports
Execution.daily_report
Execution.cost_by_agent(period: :today)
Execution.cost_by_model(period: :this_week)
Execution.stats_for("AgentName", period: :today)
Execution.compare_versions("Agent", "1.0", "2.0")
Execution.trend_analysis(agent_type: "Agent", days: 7)

# Analytics
Execution.streaming_rate
Execution.avg_time_to_first_token
```

---

## RubyLLM::Agents::Workflow

Workflow orchestration.

### Pipeline

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  Agent3,
  timeout: 60,
  max_cost: 1.00,
  before_step: { Agent2 => ->(prev, ctx) { ... } },
  on_step_failure: :skip  # or :abort
)

result = workflow.call(input: data)
```

### Parallel

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  branch1: Agent1,
  branch2: Agent2,
  timeout: 30,
  fail_fast: true,
  aggregate: ->(results) { ... }
)

result = workflow.call(input: data)
```

### Router

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: ClassifierAgent,
  routes: {
    "route1" => Agent1,
    "route2" => Agent2
  },
  default: DefaultAgent,
  classification_field: :intent,
  confidence_threshold: 0.8
)

result = workflow.call(input: data)
```

---

## RubyLLM::Agents::BudgetTracker

Budget management.

```ruby
# Check status
BudgetTracker.status
BudgetTracker.status(agent_type: "MyAgent")

# Check remaining
BudgetTracker.remaining_budget(:global, :daily)
BudgetTracker.remaining_budget(:per_agent, :daily, "MyAgent")

# Check exceeded
BudgetTracker.exceeded?(:global, :daily)
```

---

## RubyLLM::Agents::CircuitBreaker

Circuit breaker management.

```ruby
# Check status
CircuitBreaker.status("gpt-4o")
# => { state: :open, errors: 10, closes_at: Time }

# Manual control
CircuitBreaker.open!("gpt-4o")
CircuitBreaker.close!("gpt-4o")
CircuitBreaker.reset_all!
```

---

## RubyLLM::Agents.configure

Global configuration.

```ruby
RubyLLM::Agents.configure do |config|
  # Defaults
  config.default_model = "gpt-4o"
  config.default_temperature = 0.0
  config.default_timeout = 60
  config.default_streaming = false

  # Caching
  config.cache_store = Rails.cache

  # Logging
  config.async_logging = true
  config.retention_period = 30.days
  config.persist_prompts = true
  config.persist_responses = true

  # Anomaly Detection
  config.anomaly_cost_threshold = 5.00
  config.anomaly_duration_threshold = 10_000

  # Dashboard
  config.dashboard_auth = ->(c) { c.current_user&.admin? }
  config.dashboard_parent_controller = "ApplicationController"
  config.dashboard_per_page = 25

  # Budgets
  config.budgets = {
    global_daily: 100.0,
    enforcement: :hard
  }

  # Alerts
  config.alerts = {
    on_events: [:budget_hard_cap],
    slack_webhook_url: "..."
  }

  # Redaction
  config.redaction = {
    fields: %w[password],
    patterns: [/.../],
    placeholder: "[REDACTED]"
  }
end
```

---

## Exceptions

```ruby
RubyLLM::Agents::BudgetExceededError  # Budget limit exceeded
RubyLLM::Agents::CircuitOpenError     # Circuit breaker is open
```

## Related Pages

- [Agent DSL](Agent-DSL) - DSL reference
- [Configuration](Configuration) - Configuration guide
- [Result Object](Result-Object) - Result details
