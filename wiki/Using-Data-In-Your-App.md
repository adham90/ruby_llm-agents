# Using Data in Your App

Build custom dashboards, usage pages, and billing integrations using the gem's query API. All execution, cost, and tenant data is accessible through ActiveRecord models and convenience methods.

## Quick Start

```ruby
# Global usage summary
RubyLLM::Agents.usage(period: :today)
# => { executions: 142, successful: 138, failed: 4, success_rate: 97.2,
#      total_cost: 1.85, total_tokens: 284000, avg_duration_ms: 1200, avg_cost: 0.013 }

# Cost breakdown by agent
RubyLLM::Agents.costs(period: :this_month)
# => { "ChatAgent" => { cost: 12.50, count: 1000, avg_cost: 0.0125 },
#      "SummaryAgent" => { cost: 3.20, count: 400, avg_cost: 0.008 } }

# All registered agents with stats
RubyLLM::Agents.agents
# => [{ name: "ChatAgent", active: true, model: "gpt-4o", execution_count: 1000, ... }]

# Raw execution query (returns ActiveRecord::Relation)
RubyLLM::Agents.executions.successful.today.count
```

## Top-Level Convenience API

The `RubyLLM::Agents` module provides four convenience methods that cover the most common queries:

### `.usage(period:, agent:, tenant:)`

Returns a summary hash for any combination of period, agent, and tenant.

```ruby
# Global
RubyLLM::Agents.usage(period: :today)
RubyLLM::Agents.usage(period: :this_month)
RubyLLM::Agents.usage(period: :last_30_days)

# Per-agent
RubyLLM::Agents.usage(period: :this_week, agent: "ChatAgent")
RubyLLM::Agents.usage(period: :this_week, agent: ChatAgent) # class also works

# Per-tenant (for "My Usage" pages)
RubyLLM::Agents.usage(period: :this_month, tenant: current_user)
RubyLLM::Agents.usage(period: :this_month, tenant: "tenant-123")

# Custom date range
RubyLLM::Agents.usage(period: 1.week.ago..Time.current)
```

**Supported periods:** `:today`, `:yesterday`, `:this_week`, `:this_month`, `:last_7_days`, `:last_30_days`, or any `Range` of times.

### `.costs(period:, tenant:)`

Returns cost breakdown grouped by agent.

```ruby
costs = RubyLLM::Agents.costs(period: :this_month)
costs.each do |agent_name, data|
  puts "#{agent_name}: $#{data[:cost]} (#{data[:count]} calls)"
end
```

### `.agents`

Returns all registered agents with configuration and stats.

```ruby
RubyLLM::Agents.agents.each do |agent|
  puts "#{agent[:name]} — #{agent[:model]} — #{agent[:execution_count]} calls"
end
```

### `.tenant_for(tenant)`

Loads a tenant record for detailed budget and usage queries.

```ruby
tenant = RubyLLM::Agents.tenant_for(current_user)
tenant.cost_today          # => 0.42
tenant.budget_status       # => { enabled: true, enforcement: :soft, ... }
tenant.usage_by_agent      # => { "ChatAgent" => { cost: 0.30, tokens: 5000, count: 20 } }
```

### `.executions`

Returns an `ActiveRecord::Relation` for custom queries.

```ruby
RubyLLM::Agents.executions.today.successful.count
RubyLLM::Agents.executions.by_agent("ChatAgent").expensive(0.50)
```

---

## Querying Executions

The `Execution` model has 30+ chainable scopes. Use `RubyLLM::Agents.executions` or `RubyLLM::Agents::Execution` directly.

### Time Scopes

```ruby
Execution.today
Execution.yesterday
Execution.this_week
Execution.this_month
Execution.last_n_days(7)
Execution.recent(10)          # Most recent N records
```

### Status Scopes

```ruby
Execution.successful
Execution.failed              # Includes errors and timeouts
Execution.errors              # Errors only
Execution.timeouts            # Timeouts only
Execution.running             # Currently in-progress
```

### Filtering

```ruby
Execution.by_agent("ChatAgent")
Execution.by_model("gpt-4o")
Execution.by_tenant("tenant-123")
Execution.expensive(1.00)     # Cost > $1.00
Execution.slow(5000)          # Duration > 5000ms
Execution.high_token(10_000)  # Tokens > 10,000
Execution.cached              # Cache hits
Execution.streaming           # Streaming executions
Execution.with_tool_calls     # Used tools
Execution.with_fallback       # Used fallback model
```

### Composing Queries

All scopes are chainable:

```ruby
# Expensive failures this week
Execution.this_week.failed.expensive(0.50)

# Successful GPT-4 calls for a tenant
Execution.by_tenant("acme").by_model("gpt-4o").successful

# Slow streaming calls today
Execution.today.streaming.slow(3000)
```

### Aggregations

```ruby
Execution.today.sum(:total_cost)          # Total spend
Execution.today.sum(:total_tokens)        # Total tokens
Execution.today.average(:duration_ms)     # Avg duration
Execution.today.count                     # Total calls
```

### Analytics Methods

```ruby
# Daily report
Execution.daily_report
# => { total_executions: 142, total_cost: 1.85, ... }

# Cost by agent
Execution.cost_by_agent(period: :today)
# => { "ChatAgent" => 0.85, "SummaryAgent" => 0.42 }

# Trend analysis
Execution.trend_analysis(days: 7)
# => [{ date: "2024-01-01", count: 50, cost: 0.65 }, ...]

# Cache hit rate
Execution.cache_hit_rate
# => 45.2

# Model stats
Execution.model_stats
# => { "gpt-4o" => { count: 100, avg_cost: 0.02, avg_duration: 1200 } }
```

### Chart Data (Highcharts-ready)

```ruby
# Activity chart (hourly for today, daily for ranges)
Execution.activity_chart_json(range: "today")
Execution.activity_chart_json(range: "7d")
Execution.activity_chart_json(range: "30d")

# Custom date range
Execution.activity_chart_json_for_dates(from: 1.week.ago, to: Time.current)
```

---

## Per-Agent Queries

Every agent class has built-in query methods:

```ruby
ChatAgent.executions                      # All executions for this agent
ChatAgent.last_run                        # Most recent execution
ChatAgent.failures(since: 24.hours)       # Recent failures
ChatAgent.total_spent(since: 1.month)     # Total cost
ChatAgent.stats                           # Summary hash
ChatAgent.stats(since: 1.week)            # Stats for time window
ChatAgent.cost_by_model                   # Cost breakdown by model
ChatAgent.with_params(query: "test")      # Filter by parameters
```

### Stats Hash

```ruby
ChatAgent.stats
# => {
#   total: 1000,
#   successful: 980,
#   failed: 20,
#   success_rate: 98.0,
#   avg_duration_ms: 1200,
#   avg_cost: 0.013,
#   total_cost: 13.00,
#   total_tokens: 2000000,
#   avg_tokens: 2000
# }
```

---

## Tenant Data

For multi-tenant apps, the `Tenant` model tracks per-tenant usage and budgets.

### Finding Tenants

```ruby
tenant = RubyLLM::Agents.tenant_for(current_user)
# or
tenant = RubyLLM::Agents::Tenant.for("tenant-123")
```

### Usage Queries

```ruby
tenant.cost_today             # => 0.42
tenant.cost_this_month        # => 12.50
tenant.tokens_today           # => 50000
tenant.executions_today       # => 25
tenant.errors_today           # => 2
tenant.success_rate_today     # => 92.0
```

### Usage Breakdowns

```ruby
tenant.usage_summary(period: :this_month)
# => { tenant_id: "acme", cost: 12.50, tokens: 500000, executions: 400 }

tenant.usage_by_agent(period: :this_month)
# => { "ChatAgent" => { cost: 8.00, tokens: 300000, count: 250 },
#      "SummaryAgent" => { cost: 4.50, tokens: 200000, count: 150 } }

tenant.usage_by_model(period: :this_month)
# => { "gpt-4o" => { cost: 10.00, tokens: 400000, count: 350 },
#      "gpt-4o-mini" => { cost: 2.50, tokens: 100000, count: 50 } }

tenant.usage_by_day(period: :this_month)
# => { Date.today => { cost: 0.42, tokens: 50000, count: 25 }, ... }
```

### Budget Status

```ruby
tenant.budget_status
# => { enabled: true, enforcement: :soft,
#      global_daily: 25.0, global_monthly: 500.0, ... }

tenant.within_budget?                     # => true
tenant.within_budget?(type: :monthly_cost)  # => true
tenant.remaining_budget(type: :daily_cost)  # => 24.58
```

### Listing Tenants

```ruby
RubyLLM::Agents::Tenant.active                 # Active tenants
RubyLLM::Agents::Tenant.top_by_spend(limit: 10)  # Top spenders
RubyLLM::Agents::Tenant.with_budgets           # Tenants with budget limits
```

---

## Result Objects

Every agent call returns a `Result` with rich metadata:

```ruby
result = ChatAgent.call(query: "Hello")

# Content
result.content                # Processed response

# Cost
result.total_cost             # => 0.013
result.input_cost             # => 0.005
result.output_cost            # => 0.008

# Tokens
result.total_tokens           # => 2000
result.input_tokens           # => 800
result.output_tokens          # => 1200

# Timing
result.duration_ms            # => 1200
result.time_to_first_token_ms # => 450 (streaming only)

# Model
result.model_id               # => "gpt-4o" (requested)
result.chosen_model_id        # => "gpt-4o" (actual, may differ if fallback)

# Status
result.success?               # => true
result.streaming?             # => false
result.used_fallback?         # => false
result.attempts_count         # => 1

# Link to execution record
result.execution_id           # => 12345
result.execution              # => Execution record

# Serialize
result.to_h                   # All data as Hash
```

---

## Tracking Groups of Calls

Use `RubyLLM::Agents.track` to aggregate metrics across multiple agent calls:

```ruby
report = RubyLLM::Agents.track(tenant: current_user) do
  ChatAgent.call(query: "Hello")
  SummaryAgent.call(text: long_document)
end

report.total_cost          # => 0.025
report.total_tokens        # => 5000
report.execution_count     # => 2
report.success_count       # => 2
report.success_rate        # => 100.0
report.results             # => [Result, Result]
```

---

## Common Patterns

### "My Usage" Page

```ruby
# In your controller
class UsageController < ApplicationController
  def show
    @tenant = RubyLLM::Agents.tenant_for(current_user)
    @usage = RubyLLM::Agents.usage(period: :this_month, tenant: current_user)
    @by_agent = @tenant&.usage_by_agent(period: :this_month) || {}
    @by_day = @tenant&.usage_by_day(period: :this_month) || {}
  end
end
```

### Admin Dashboard

```ruby
class Admin::AiUsageController < ApplicationController
  def index
    @global = RubyLLM::Agents.usage(period: params[:period]&.to_sym || :today)
    @costs = RubyLLM::Agents.costs(period: params[:period]&.to_sym || :today)
    @agents = RubyLLM::Agents.agents
    @top_tenants = RubyLLM::Agents::Tenant.top_by_spend(limit: 10)
    @chart = RubyLLM::Agents::Execution.activity_chart_json(range: "7d")
  end
end
```

### API Endpoint

```ruby
class Api::UsageController < ApplicationController
  def show
    period = params[:period]&.to_sym || :this_month
    usage = RubyLLM::Agents.usage(period: period, tenant: current_user)
    render json: usage
  end

  def costs
    costs = RubyLLM::Agents.costs(period: :this_month, tenant: current_user)
    render json: costs
  end
end
```

### Background Monitoring

```ruby
# Daily cost check (e.g., in a cron job)
usage = RubyLLM::Agents.usage(period: :today)
if usage[:total_cost] > 50.0
  AdminMailer.cost_alert(usage).deliver_later
end

# Agent health check
RubyLLM::Agents.agents.each do |agent|
  stats = RubyLLM::Agents::Execution.stats_for(agent[:name], period: :today)
  if stats[:success_rate] < 90
    Rails.logger.warn("[AI] #{agent[:name]} success rate: #{stats[:success_rate]}%")
  end
end
```

---

## Related Pages

- **[Querying Executions](Querying-Executions)** - Agent-level query methods
- **[Database Queries](Database-Queries)** - Full scope reference
- **[Execution Tracking](Execution-Tracking)** - What gets tracked
- **[Multi-Tenancy](Multi-Tenancy)** - Tenant setup and isolation
- **[Budget Controls](Budget-Controls)** - Budget configuration
- **[Dashboard](Dashboard)** - Built-in monitoring UI
- **[Result Object](Result-Object)** - Result object reference
