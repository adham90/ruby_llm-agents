# Budget Controls

Set spending limits to prevent runaway LLM costs at global and per-agent levels.

## Quick Setup

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 100.0,    # $100/day across all agents
    global_monthly: 2000.0, # $2000/month across all agents
    enforcement: :hard      # Block when exceeded
  }
end
```

## Budget Types

### Global Limits

Apply to all agents combined:

```ruby
config.budgets = {
  global_daily: 100.0,    # Daily limit
  global_monthly: 2000.0  # Monthly limit
}
```

### Per-Agent Limits

Set limits for specific agents:

```ruby
config.budgets = {
  per_agent_daily: {
    "ExpensiveAgent" => 50.0,   # $50/day
    "CheapAgent" => 5.0         # $5/day
  },
  per_agent_monthly: {
    "ExpensiveAgent" => 500.0   # $500/month
  }
}
```

## Enforcement Modes

### Hard Enforcement

Block requests when budget is exceeded:

```ruby
config.budgets = {
  global_daily: 100.0,
  enforcement: :hard
}

# When exceeded:
MyAgent.call(query: "test")
# => Raises RubyLLM::Agents::BudgetExceededError
```

### Soft Enforcement

Allow requests but log warnings:

```ruby
config.budgets = {
  global_daily: 100.0,
  enforcement: :soft
}

# When exceeded:
MyAgent.call(query: "test")
# => Executes but logs warning
```

## Checking Budget Status

```ruby
# Global status
status = RubyLLM::Agents::BudgetTracker.status
# => {
#   global_daily: {
#     limit: 100.0,
#     current: 45.50,
#     remaining: 54.50,
#     percentage_used: 45.5
#   },
#   global_monthly: {
#     limit: 2000.0,
#     current: 890.0,
#     remaining: 1110.0,
#     percentage_used: 44.5
#   }
# }

# Per-agent status
status = RubyLLM::Agents::BudgetTracker.status(agent_type: "MyAgent")
```

### Remaining Budget

```ruby
# Check remaining budget
remaining = RubyLLM::Agents::BudgetTracker.remaining_budget(:global, :daily)
# => 54.50

remaining = RubyLLM::Agents::BudgetTracker.remaining_budget(:per_agent, :daily, "MyAgent")
# => 25.00
```

### Budget Exceeded?

```ruby
if RubyLLM::Agents::BudgetTracker.exceeded?(:global, :daily)
  notify_admin("Daily budget exceeded!")
end
```

## Soft Cap Alerts

Get notified before hitting hard limits:

```ruby
config.budgets = {
  global_daily: 100.0,
  soft_cap_percentage: 80,  # Alert at 80%
  enforcement: :hard
}

config.on_alert = ->(event, payload) {
  if event == :budget_soft_cap
    Slack::Notifier.new(ENV['SLACK_WEBHOOK']).ping(
      "Budget warning: $#{payload[:total_cost]} / $#{payload[:limit]}"
    )
  end
}
```

Alert triggers at $80 (80% of $100).

## Complete Configuration

```ruby
RubyLLM::Agents.configure do |config|
  config.budgets = {
    # Global limits
    global_daily: 100.0,
    global_monthly: 2000.0,

    # Per-agent limits
    per_agent_daily: {
      "ContentGeneratorAgent" => 50.0,
      "SearchAgent" => 10.0,
      "AnalyticsAgent" => 25.0
    },
    per_agent_monthly: {
      "ContentGeneratorAgent" => 500.0
    },

    # Enforcement
    enforcement: :hard,

    # Soft cap (percentage of limit to trigger warning)
    soft_cap_percentage: 80
  }
end
```

## Handling Budget Errors

```ruby
begin
  result = MyAgent.call(query: query)
rescue RubyLLM::Agents::BudgetExceededError => e
  Rails.logger.error("Budget exceeded: #{e.message}")

  # Option 1: Return cached/default response
  cached_response

  # Option 2: Queue for later
  AgentJob.perform_later(query: query)

  # Option 3: Notify user
  render json: { error: "Service temporarily unavailable" }
end
```

## Budget Analytics

### Daily Spending Trend

```ruby
# Last 7 days of spending
RubyLLM::Agents::Execution
  .where("created_at >= ?", 7.days.ago)
  .group("DATE(created_at)")
  .sum(:total_cost)
# => { "2024-01-08" => 85.20, "2024-01-09" => 92.10, ... }
```

### Spending by Agent

```ruby
RubyLLM::Agents::Execution
  .today
  .group(:agent_type)
  .sum(:total_cost)
# => { "SearchAgent" => 25.50, "ContentAgent" => 45.00 }
```

### Spending by Model

```ruby
RubyLLM::Agents::Execution
  .this_month
  .group(:model_id)
  .sum(:total_cost)
# => { "gpt-4o" => 450.00, "gpt-4o-mini" => 50.00 }
```

### Cost Projection

```ruby
# Current daily run rate
daily_total = RubyLLM::Agents::Execution.today.sum(:total_cost)
hours_elapsed = (Time.current - Time.current.beginning_of_day) / 3600.0
hourly_rate = daily_total / hours_elapsed
projected_daily = hourly_rate * 24

# Monthly projection
days_in_month = Time.current.end_of_month.day
monthly_total = RubyLLM::Agents::Execution.this_month.sum(:total_cost)
daily_average = monthly_total / Time.current.day
projected_monthly = daily_average * days_in_month
```

## Dashboard Integration

The dashboard shows:
- Current spending vs. limits
- Budget utilization charts
- Spending trends over time
- Per-agent cost breakdowns

## Best Practices

### Start with Monitoring

```ruby
# Start with soft enforcement to understand usage
config.budgets = {
  global_daily: 100.0,
  enforcement: :soft  # Log warnings first
}
```

### Set Realistic Limits

```ruby
# Base limits on historical usage + buffer
avg_daily = RubyLLM::Agents::Execution
  .where("created_at >= ?", 30.days.ago)
  .sum(:total_cost) / 30

# Set limit at 150% of average
config.budgets = {
  global_daily: avg_daily * 1.5
}
```

### Use Per-Agent Limits for Expensive Agents

```ruby
config.budgets = {
  per_agent_daily: {
    "ExpensiveGPT4Agent" => 20.0,  # Strict limit
    "CheapMiniAgent" => 50.0       # More lenient
  }
}
```

### Monitor Soft Cap Alerts

```ruby
config.budgets = {
  soft_cap_percentage: 75  # Early warning
}

config.on_alert = ->(event, payload) {
  return unless event == :budget_soft_cap

  percentage = (payload[:total_cost] / payload[:limit] * 100).round
  if percentage >= 90
    PagerDuty.alert("Critical: Budget at #{percentage}%")
  else
    Slack.notify("Budget warning: #{percentage}% used")
  end
}
```

### Review and Adjust

```ruby
# Weekly budget review
weekly_spending = RubyLLM::Agents::Execution
  .where("created_at >= ?", 1.week.ago)
  .sum(:total_cost)

weekly_limit = config.budgets[:global_daily] * 7

utilization = weekly_spending / weekly_limit
Rails.logger.info("Weekly budget utilization: #{(utilization * 100).round}%")
```

## API Rate vs. Budget Limits

Budget limits are different from API rate limits:

| Aspect | Budget Limits | Rate Limits |
|--------|---------------|-------------|
| Metric | Cost (dollars) | Requests per time |
| Purpose | Cost control | API protection |
| Scope | Your application | Provider-imposed |

Handle both:

```ruby
begin
  result = MyAgent.call(query: query)
rescue RubyLLM::Agents::BudgetExceededError
  # Budget exceeded - wait or use fallback
rescue Faraday::TooManyRequestsError
  # Rate limited - retry with backoff
end
```

## Multi-Tenant Budgets (v0.4.0+)

For multi-tenant applications, you can set per-tenant budget limits using the `TenantBudget` model.

### Configuration

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.multi_tenancy_enabled = true
  config.tenant_resolver = -> { Current.tenant_id }
end
```

### Setting Tenant Budgets

```ruby
# Create or update tenant budget
RubyLLM::Agents::TenantBudget.find_or_create_by(tenant_id: "tenant_123") do |budget|
  budget.daily_limit = 50.0
  budget.monthly_limit = 500.0
  budget.enforcement = :hard
end

# Update existing budget
tenant_budget = RubyLLM::Agents::TenantBudget.find_by(tenant_id: "tenant_123")
tenant_budget.update(daily_limit: 75.0)
```

### Checking Tenant Budget Status

```ruby
status = RubyLLM::Agents::BudgetTracker.status(tenant_id: "tenant_123")
# => {
#   tenant_daily: { limit: 50.0, current: 25.0, remaining: 25.0 },
#   tenant_monthly: { limit: 500.0, current: 150.0, remaining: 350.0 }
# }
```

### Querying Tenant Spending

```ruby
# Total spending for a tenant
RubyLLM::Agents::Execution
  .by_tenant("tenant_123")
  .this_month
  .sum(:total_cost)

# Compare tenants
RubyLLM::Agents::Execution
  .this_month
  .group(:tenant_id)
  .sum(:total_cost)
```

See [Multi-Tenancy](Multi-Tenancy) for complete multi-tenancy documentation.

## Related Pages

- [Multi-Tenancy](Multi-Tenancy) - Per-tenant configuration
- [Alerts](Alerts) - Budget notifications
- [Execution Tracking](Execution-Tracking) - Cost analytics
- [Dashboard](Dashboard) - Budget monitoring
- [Configuration](Configuration) - Full setup guide
