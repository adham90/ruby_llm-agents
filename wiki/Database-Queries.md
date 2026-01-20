# Database Queries

Comprehensive guide to querying the `RubyLLM::Agents::Execution` model for analytics, debugging, and reporting.

## Execution Model

All agent executions are stored in the `ruby_llm_agents_executions` table:

```ruby
RubyLLM::Agents::Execution
```

## Schema Overview

| Column | Type | Description |
|--------|------|-------------|
| `agent_type` | string | Agent class name (e.g., "SearchAgent") |
| `agent_version` | string | Version for cache invalidation |
| `model_id` | string | Configured LLM model |
| `chosen_model_id` | string | Actual model used (for fallbacks) |
| `model_provider` | string | Provider name |
| `temperature` | decimal | Temperature setting |
| `status` | string | `running`, `success`, `error`, `timeout` |
| `started_at` | datetime | Execution start time |
| `completed_at` | datetime | Execution end time |
| `duration_ms` | integer | Duration in milliseconds |
| `input_tokens` | integer | Input token count |
| `output_tokens` | integer | Output token count |
| `total_tokens` | integer | Total tokens |
| `input_cost` | decimal | Cost of input tokens (USD) |
| `output_cost` | decimal | Cost of output tokens (USD) |
| `total_cost` | decimal | Total cost (USD) |
| `parameters` | json | Agent parameters (sanitized) |
| `response` | json | LLM response data |
| `metadata` | json | Custom metadata |
| `error_class` | string | Exception class if failed |
| `error_message` | text | Exception message if failed |
| `system_prompt` | text | System prompt used |
| `user_prompt` | text | User prompt used |
| `streaming` | boolean | Whether streaming was used |
| `cache_hit` | boolean | Whether response was from cache |
| `response_cache_key` | string | Cache key used |
| `finish_reason` | string | `stop`, `length`, `content_filter`, `tool_calls` |
| `tool_calls` | json | Array of tool call details |
| `tool_calls_count` | integer | Number of tool calls |
| `attempts` | json | Array of retry/fallback attempts |
| `attempts_count` | integer | Number of attempts |
| `fallback_reason` | string | Why fallback was triggered |
| `time_to_first_token_ms` | integer | TTFT (streaming only) |
| `tenant_id` | string | Multi-tenant identifier |
| `trace_id` | string | Distributed trace ID |
| `request_id` | string | Request ID |
| `parent_execution_id` | bigint | Parent execution (workflows) |
| `root_execution_id` | bigint | Root execution (workflows) |

## Query Scopes

All scopes are chainable.

### Time-Based Scopes

```ruby
Execution.today
Execution.yesterday
Execution.this_week
Execution.this_month
Execution.last_n_days(7)
Execution.recent(100)        # Most recent N records
Execution.oldest(100)        # Oldest N records
Execution.between(start_date, end_date)
```

### Status-Based Scopes

```ruby
Execution.running            # In progress
Execution.successful         # Completed successfully
Execution.failed             # Error or timeout
Execution.errors             # Error status only
Execution.timeouts           # Timeout status only
Execution.completed          # Not running
```

### Agent/Model Filtering

```ruby
Execution.by_agent("SearchAgent")
Execution.by_version("2.0")
Execution.by_model("gpt-4o")
```

### Performance Filtering

```ruby
Execution.expensive(1.00)    # Cost >= $1.00
Execution.slow(5000)         # Duration >= 5 seconds
Execution.high_token(10000)  # Tokens >= 10k
```

### Caching Scopes

```ruby
Execution.cached             # Cache hits
Execution.cache_miss         # Cache misses
```

### Streaming Scopes

```ruby
Execution.streaming          # Used streaming
Execution.non_streaming      # Did not use streaming
```

### Tool Call Scopes

```ruby
Execution.with_tool_calls    # Made tool calls
Execution.without_tool_calls # No tool calls
```

### Reliability Scopes

```ruby
Execution.with_fallback      # Used fallback model
Execution.rate_limited       # Was rate limited
Execution.retryable_errors   # Has retryable errors
```

### Finish Reason Scopes

```ruby
Execution.truncated          # Hit max_tokens
Execution.content_filtered   # Blocked by safety
Execution.by_finish_reason("stop")
Execution.by_finish_reason("tool_calls")
```

### Tracing Scopes

```ruby
Execution.by_trace("trace-123")
Execution.by_request("request-456")
Execution.root_executions    # Top-level only
Execution.child_executions   # Nested only
Execution.children_of(execution_id)
```

### Multi-Tenancy Scopes

```ruby
Execution.by_tenant("tenant_123")
Execution.for_current_tenant   # Uses configured resolver
Execution.with_tenant          # Has tenant_id
Execution.without_tenant       # No tenant_id
```

### Parameter Filtering (JSONB)

```ruby
Execution.with_parameter(:query)
Execution.with_parameter(:user_id, 123)
```

### Search

```ruby
Execution.search("error text")
```

## Instance Methods

```ruby
execution = RubyLLM::Agents::Execution.last

# Status checks
execution.cached?             # Was this a cache hit?
execution.streaming?          # Was streaming used?
execution.truncated?          # Did it hit max_tokens?
execution.content_filtered?   # Was it blocked by safety?
execution.has_tool_calls?     # Were tools called?
execution.used_fallback?      # Did it use fallback model?
execution.has_retries?        # Were there multiple attempts?
execution.rate_limited?       # Was it rate limited?

# Hierarchy (workflows)
execution.root?               # Is this a root execution?
execution.child?              # Is this a child execution?
execution.depth               # Nesting level (0 = root)

# Attempt analysis
execution.successful_attempt      # The successful attempt data
execution.failed_attempts         # Array of failed attempts
execution.short_circuited_attempts # Circuit breaker blocked
```

## Aggregation Methods

```ruby
scope = RubyLLM::Agents::Execution.by_agent("SearchAgent").this_week

scope.total_cost_sum   # Sum of total_cost
scope.total_tokens_sum # Sum of total_tokens
scope.avg_duration     # Average duration_ms
scope.avg_tokens       # Average total_tokens
```

## Analytics Methods

### Daily Report

```ruby
RubyLLM::Agents::Execution.daily_report
# => {
#   date: Date.current,
#   total_executions: 156,
#   successful: 150,
#   failed: 6,
#   total_cost: 12.50,
#   total_tokens: 500000,
#   avg_duration_ms: 1200,
#   error_rate: 3.85,
#   by_agent: { "SearchAgent" => 100, "ChatAgent" => 56 },
#   top_errors: { "RateLimitError" => 4, "TimeoutError" => 2 }
# }
```

### Cost Breakdown

```ruby
RubyLLM::Agents::Execution.cost_by_agent(period: :this_week)
# => { "ContentAgent" => 45.50, "SearchAgent" => 12.30 }
```

### Agent Statistics

```ruby
RubyLLM::Agents::Execution.stats_for("SearchAgent", period: :today)
# => {
#   agent_type: "SearchAgent",
#   count: 100,
#   total_cost: 5.25,
#   avg_cost: 0.0525,
#   total_tokens: 150000,
#   avg_tokens: 1500,
#   avg_duration_ms: 800,
#   success_rate: 98.0,
#   error_rate: 2.0
# }
```

### Version Comparison

```ruby
RubyLLM::Agents::Execution.compare_versions("SearchAgent", "1.0", "2.0", period: :this_week)
# => {
#   version1: { version: "1.0", count: 50, avg_cost: 0.06, ... },
#   version2: { version: "2.0", count: 75, avg_cost: 0.04, ... },
#   improvements: { cost_change_pct: -33.3, speed_change_pct: -20.0 }
# }
```

### Trend Analysis

```ruby
RubyLLM::Agents::Execution.trend_analysis(agent_type: "SearchAgent", days: 7)
# => [
#   { date: 7.days.ago.to_date, count: 100, total_cost: 5.0, avg_duration_ms: 850, error_count: 2 },
#   { date: 6.days.ago.to_date, count: 120, ... },
#   ...
# ]
```

### Dashboard Data

```ruby
# Real-time metrics
RubyLLM::Agents::Execution.now_strip_data(range: "today")
# => {
#   running: 2,
#   success_today: 150,
#   errors_today: 3,
#   timeouts_today: 1,
#   cost_today: 12.50,
#   executions_today: 156,
#   success_rate: 96.2
# }

# Ranges: "today", "7d", "30d"
RubyLLM::Agents::Execution.now_strip_data(range: "7d")
```

### Chart Data

```ruby
RubyLLM::Agents::Execution.activity_chart_json(range: "today")  # Hourly
RubyLLM::Agents::Execution.activity_chart_json(range: "7d")     # Daily
RubyLLM::Agents::Execution.activity_chart_json(range: "30d")    # Daily
```

### Performance Metrics

```ruby
RubyLLM::Agents::Execution.today.cache_hit_rate        # => 45.2
RubyLLM::Agents::Execution.today.streaming_rate        # => 12.5
RubyLLM::Agents::Execution.today.avg_time_to_first_token  # => 150 (ms)
RubyLLM::Agents::Execution.today.rate_limited_rate     # => 0.5
```

### Finish Reason Distribution

```ruby
RubyLLM::Agents::Execution.today.finish_reason_distribution
# => { "stop" => 145, "tool_calls" => 8, "length" => 3 }
```

## Common Query Examples

### Recent Executions for an Agent

```ruby
RubyLLM::Agents::Execution.by_agent("SearchAgent").recent(10)
```

### Failed Executions Today

```ruby
RubyLLM::Agents::Execution.today.failed
```

### Expensive Executions This Week

```ruby
RubyLLM::Agents::Execution.this_week.expensive(0.50)
```

### Slow Streaming Executions

```ruby
RubyLLM::Agents::Execution.streaming.slow(5000)
  .where("time_to_first_token_ms > ?", 1000)
```

### Cache Hit Rate

```ruby
hits = RubyLLM::Agents::Execution.today.cached.count
total = RubyLLM::Agents::Execution.today.count
rate = total > 0 ? (hits.to_f / total * 100).round(1) : 0
```

### Total Cost This Month

```ruby
RubyLLM::Agents::Execution.this_month.sum(:total_cost)
```

### Average Duration by Agent

```ruby
RubyLLM::Agents::Execution.group(:agent_type).average(:duration_ms)
```

### Token Usage by Model

```ruby
RubyLLM::Agents::Execution.group(:model_id).sum(:total_tokens)
```

### Executions with Fallbacks

```ruby
RubyLLM::Agents::Execution.with_fallback
  .select(:agent_type, :model_id, :chosen_model_id)
```

### Tool Usage Statistics

```ruby
RubyLLM::Agents::Execution.with_tool_calls.group(:agent_type).count
```

### Workflow Executions

```ruby
RubyLLM::Agents::Execution.child_executions.where.not(parent_execution_id: nil)
```

## Rails Console Examples

```ruby
# Quick stats
puts "Today: #{Execution.today.count} executions, $#{Execution.today.sum(:total_cost).round(2)}"
puts "Errors: #{Execution.today.errors.count}"
puts "Cache hits: #{Execution.today.cached.count}"

# Find problematic executions
Execution.today.errors.pluck(:agent_type, :error_class, :error_message)

# Cost breakdown by agent
Execution.this_month.group(:agent_type).sum(:total_cost).sort_by(&:last).reverse

# Slowest executions
Execution.today.order(duration_ms: :desc).limit(5).pluck(:agent_type, :duration_ms)

# Recent execution details
e = Execution.last
puts "Agent: #{e.agent_type}"
puts "Model: #{e.model_id} (chosen: #{e.chosen_model_id})"
puts "Status: #{e.status}"
puts "Duration: #{e.duration_ms}ms"
puts "Tokens: #{e.total_tokens}"
puts "Cost: $#{e.total_cost}"
puts "Cache hit: #{e.cache_hit}"
puts "Tool calls: #{e.tool_calls_count}"
```

## Related Pages

- [Execution Tracking](Execution-Tracking) - What gets logged
- [Dashboard](Dashboard) - Visual monitoring
- [Budget Controls](Budget-Controls) - Cost management
