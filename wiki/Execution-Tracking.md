# Execution Tracking

RubyLLM::Agents automatically logs every agent execution with comprehensive metadata.

## What's Tracked

Every execution records:

| Field | Description |
|-------|-------------|
| `agent_type` | Agent class name |
| `model_id` | LLM model configured for agent |
| `chosen_model_id` | Actual model used (may differ if fallback triggered) |
| `status` | success, error, timeout |
| `input_tokens` | Tokens in the prompt |
| `output_tokens` | Tokens in the response |
| `input_cost` | Cost of input tokens |
| `output_cost` | Cost of output tokens |
| `total_cost` | Total execution cost |
| `duration_ms` | Execution time |
| `parameters` | Input parameters (redacted) |
| `system_prompt` | System prompt (if persisted) |
| `user_prompt` | User prompt (if persisted) |
| `response` | LLM response (if persisted) |
| `error_message` | Error details (if failed) |
| `metadata` | Custom metadata |
| `streaming` | Whether streaming was used |
| `time_to_first_token_ms` | TTFT (streaming only) |
| `tool_calls` | Array of tool invocations |
| `tool_calls_count` | Number of tools called |

### Reliability Fields (v0.4.0+)

| Field | Description |
|-------|-------------|
| `attempts` | JSON array of all attempt details |
| `attempts_count` | Number of attempts made |
| `fallback_chain` | Models attempted in order |
| `fallback_reason` | Why fallback was triggered |
| `cache_hit` | Whether response came from cache |
| `retryable` | Whether error was retryable |
| `rate_limited` | Whether rate limit was hit |

### Multi-Tenancy Fields (v0.4.0+)

| Field | Description |
|-------|-------------|
| `tenant_id` | Tenant identifier (when multi-tenancy enabled) |

## Viewing Executions

### Dashboard

Visit `/agents/executions` for a visual interface with:
- Filterable list
- Cost breakdowns
- Performance charts
- Error details

### Programmatic Access

```ruby
# Get recent executions
RubyLLM::Agents::Execution.order(created_at: :desc).limit(10)

# Find by agent
RubyLLM::Agents::Execution.by_agent("SearchAgent")

# Find by status
RubyLLM::Agents::Execution.successful
RubyLLM::Agents::Execution.failed

# Find by time
RubyLLM::Agents::Execution.today
RubyLLM::Agents::Execution.this_week
RubyLLM::Agents::Execution.this_month
```

## Custom Metadata

Add application-specific data to executions:

```ruby
class MyAgent < ApplicationAgent
  param :query, required: true
  param :user_id, required: true

  def metadata
    {
      user_id: user_id,
      source: "web",
      request_id: Current.request_id,
      feature_flags: current_flags
    }
  end
end
```

Access metadata:

```ruby
execution = RubyLLM::Agents::Execution.last
execution.metadata
# => { "user_id" => 123, "source" => "web", ... }
```

Query by metadata:

```ruby
# PostgreSQL JSONB query
RubyLLM::Agents::Execution
  .where("metadata->>'user_id' = ?", "123")
  .where("metadata->>'source' = ?", "web")
```

## Analytics Queries

### Daily Summary

```ruby
RubyLLM::Agents::Execution.daily_report
# => {
#   total_executions: 1250,
#   successful: 1180,
#   failed: 70,
#   success_rate: 94.4,
#   total_cost: 12.45,
#   avg_duration_ms: 850,
#   total_tokens: 450000
# }
```

### Cost by Agent

```ruby
RubyLLM::Agents::Execution.cost_by_agent(period: :this_week)
# => [
#   { agent_type: "SearchAgent", total_cost: 5.67, executions: 450 },
#   { agent_type: "ContentAgent", total_cost: 3.21, executions: 120 }
# ]
```

### Cost by Model

```ruby
RubyLLM::Agents::Execution.cost_by_model(period: :today)
# => [
#   { model_id: "gpt-4o", total_cost: 8.50, executions: 300 },
#   { model_id: "claude-3-sonnet", total_cost: 2.10, executions: 150 }
# ]
```

### Agent Statistics

```ruby
RubyLLM::Agents::Execution.stats_for("SearchAgent", period: :today)
# => {
#   total: 150,
#   successful: 145,
#   failed: 5,
#   success_rate: 96.67,
#   avg_cost: 0.012,
#   total_cost: 1.80,
#   avg_duration_ms: 450,
#   total_tokens: 75000
# }
```

### Trend Analysis

```ruby
RubyLLM::Agents::Execution.trend_analysis(
  agent_type: "SearchAgent",
  days: 7
)
# => [
#   { date: "2024-01-01", executions: 120, cost: 1.45, avg_duration: 450 },
#   { date: "2024-01-02", executions: 135, cost: 1.62, avg_duration: 430 },
#   ...
# ]
```

## Available Scopes

### Time-Based

```ruby
.today
.yesterday
.this_week
.this_month
.last_7_days
.last_30_days
.between(start_date, end_date)
```

### Status-Based

```ruby
.successful
.failed
.status_error
.status_timeout
.status_running
```

### Agent/Model

```ruby
.by_agent("AgentName")
.by_model("gpt-4o")
```

### Performance

```ruby
.expensive(threshold)    # cost > threshold
.slow(milliseconds)      # duration > ms
.high_token_usage(count) # tokens > count
```

### Streaming

```ruby
.streaming
.non_streaming
```

### Reliability (v0.4.0+)

```ruby
.with_fallback           # Executions that used fallback models
.without_fallback        # Executions that used primary model
.retryable_errors        # Executions with retryable failures
.rate_limited            # Executions that hit rate limits
.cached                  # Executions with cache hits
.cache_miss              # Executions that missed cache
```

### Tool Calls

```ruby
.with_tool_calls         # Executions that called tools
.without_tool_calls      # Executions without tool calls
```

### Multi-Tenancy (v0.4.0+)

```ruby
.by_tenant(tenant_id)    # Filter by specific tenant
.for_current_tenant      # Filter by resolved current tenant
.with_tenant             # Executions with tenant_id set
.without_tenant          # Executions without tenant_id
```

## Complex Queries

```ruby
# Expensive failures this week
expensive_failures = RubyLLM::Agents::Execution
  .this_week
  .failed
  .expensive(0.50)
  .order(total_cost: :desc)

# Slow streaming executions
slow_streams = RubyLLM::Agents::Execution
  .streaming
  .slow(5000)
  .where("time_to_first_token_ms > ?", 1000)

# High-cost agent usage by user
RubyLLM::Agents::Execution
  .this_month
  .where("metadata->>'user_id' = ?", user_id)
  .sum(:total_cost)
```

## Async Logging

For production, enable async logging to avoid blocking:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.async_logging = true
end
```

This uses `ExecutionLoggerJob` to log in the background.

## Data Retention

Configure how long to keep execution records:

```ruby
config.retention_period = 30.days
```

Clean up old records:

```ruby
# In a scheduled job
RubyLLM::Agents::Execution
  .where("created_at < ?", 30.days.ago)
  .delete_all
```

## Persistence Options

Control what gets stored:

```ruby
config.persist_prompts = true    # Store prompts
config.persist_responses = true  # Store responses
```

Disable for compliance:

```ruby
config.persist_prompts = false
config.persist_responses = false
```

## Exporting Data

### CSV Export

```ruby
require 'csv'

CSV.open("executions.csv", "wb") do |csv|
  csv << ["Agent", "Model", "Status", "Cost", "Duration", "Timestamp"]

  RubyLLM::Agents::Execution.this_month.find_each do |e|
    csv << [
      e.agent_type,
      e.model_id,
      e.status,
      e.total_cost,
      e.duration_ms,
      e.created_at
    ]
  end
end
```

### JSON Export

```ruby
data = RubyLLM::Agents::Execution.this_week.map do |e|
  {
    agent: e.agent_type,
    model: e.model_id,
    status: e.status,
    cost: e.total_cost,
    tokens: e.input_tokens + e.output_tokens,
    duration_ms: e.duration_ms,
    timestamp: e.created_at.iso8601
  }
end

File.write("executions.json", data.to_json)
```

## Related Pages

- [Dashboard](Dashboard) - Visual monitoring
- [Budget Controls](Budget-Controls) - Cost management
- [Configuration](Configuration) - Logging settings
- [Troubleshooting](Troubleshooting) - Debugging executions
