# Circuit Breakers

Prevent cascading failures by temporarily blocking requests to failing models.

## The Problem

Without circuit breakers, a failing service causes:

```
Request 1 → Wait 30s → Timeout
Request 2 → Wait 30s → Timeout
Request 3 → Wait 30s → Timeout
...
```

Users wait forever, resources are wasted, and the problem compounds.

## The Solution

Circuit breakers detect failure patterns and "trip" to fast-fail:

```
Requests 1-10 → Failures → Circuit OPENS
Request 11 → Immediate failure (no wait)
Request 12 → Immediate failure (no wait)
...
[After cooldown]
Request N → Try again → Success → Circuit CLOSES
```

## Basic Configuration

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    circuit_breaker errors: 10, within: 60, cooldown: 300
  end
end
```

| Parameter | Meaning |
|-----------|---------|
| `errors` | Number of errors to trip the breaker |
| `within` | Time window in seconds |
| `cooldown` | Seconds before retrying |

## Circuit Breaker States

### Closed (Normal)

- Requests pass through normally
- Failures are counted
- If errors exceed threshold → Opens

### Open (Blocking)

- All requests fail immediately
- No API calls made
- Saves time and resources
- After cooldown → Half-Open

### Half-Open (Testing)

- One request allowed through
- If successful → Closes
- If fails → Opens again

```
CLOSED ──(too many errors)──► OPEN
   ▲                           │
   │                      (cooldown)
   │                           │
   └───(success)─── HALF-OPEN ◄┘
                        │
                   (failure)
                        │
                        └──► OPEN
```

## Per-Model Breakers

Each model has its own circuit breaker:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "claude-3-5-sonnet"
    circuit_breaker errors: 5, within: 60, cooldown: 120
  end
end

# gpt-4o breaker opens → try claude-3-5-sonnet
# claude-3-5-sonnet breaker opens → all fail fast
```

## Checking Breaker Status

```ruby
# Check if breaker is open for a model
status = RubyLLM::Agents::CircuitBreaker.status("gpt-4o")
# => { state: :open, errors: 10, opens_at: Time, closes_at: Time }

status[:state]      # => :closed, :open, or :half_open
status[:errors]     # => current error count
status[:opens_at]   # => when breaker opened (if open)
status[:closes_at]  # => when cooldown ends (if open)
```

## Execution Tracking

```ruby
execution = RubyLLM::Agents::Execution.last

# Check if attempt was short-circuited
execution.attempts.each do |attempt|
  if attempt['short_circuited']
    puts "#{attempt['model_id']} was short-circuited"
  end
end
```

## Alerting

Get notified when breakers open:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    on_events: [:breaker_open],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
  }
end
```

Alert payload:

```ruby
{
  event: :breaker_open,
  agent_type: "MyAgent",
  model_id: "gpt-4o",
  failure_count: 10,
  window_seconds: 60
}
```

## Configuration Strategies

### Conservative (Production)

```ruby
circuit_breaker errors: 10, within: 60, cooldown: 300
# 10 errors in 1 minute → block for 5 minutes
```

### Aggressive (Fast Fail)

```ruby
circuit_breaker errors: 3, within: 30, cooldown: 60
# 3 errors in 30s → block for 1 minute
```

### Relaxed (High Volume)

```ruby
circuit_breaker errors: 50, within: 300, cooldown: 600
# 50 errors in 5 minutes → block for 10 minutes
```

### Per-Agent Tuning

```ruby
module LLM
  # Critical agent: Lower threshold
  class CriticalAgent < ApplicationAgent
    circuit_breaker errors: 5, within: 60, cooldown: 120
  end

  # Background agent: Higher tolerance
  class BackgroundAgent < ApplicationAgent
    circuit_breaker errors: 20, within: 300, cooldown: 600
  end
end
```

## With Fallbacks

Circuit breakers work well with fallbacks:

```ruby
module LLM
  class ResilientAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    circuit_breaker errors: 5, within: 60, cooldown: 120
  end
end
```

When `gpt-4o` breaker opens:
1. Skip `gpt-4o` entirely (no waiting)
2. Try `gpt-4o-mini` immediately
3. If that fails, try `claude-3-5-sonnet`

## Manual Breaker Control

In emergencies:

```ruby
# Force open a breaker
RubyLLM::Agents::CircuitBreaker.open!("gpt-4o")

# Force close a breaker
RubyLLM::Agents::CircuitBreaker.close!("gpt-4o")

# Reset all breakers
RubyLLM::Agents::CircuitBreaker.reset_all!
```

## Monitoring Dashboard

The dashboard shows:
- Current breaker states
- Error counts per model
- Time until cooldown ends
- Historical breaker events

## Best Practices

### Match Thresholds to Traffic

```ruby
# Low traffic: Lower threshold
# 100 requests/day = 5 errors is significant
circuit_breaker errors: 5, within: 60, cooldown: 300

# High traffic: Higher threshold
# 10,000 requests/day = 50 errors might be noise
circuit_breaker errors: 50, within: 60, cooldown: 300
```

### Consider Error Types

Not all errors should trip breakers:

```ruby
# Only rate limits and server errors should trip
# Authentication errors won't be helped by waiting
```

### Set Appropriate Cooldowns

```ruby
# Too short: Breaker oscillates
circuit_breaker cooldown: 10  # Bad: 10 seconds

# Too long: Service recovers but blocked
circuit_breaker cooldown: 3600  # Bad: 1 hour

# Just right: Time for service to recover
circuit_breaker cooldown: 300  # Good: 5 minutes
```

### Combine with Fallbacks

```ruby
# Always have a fallback when using circuit breakers
model "gpt-4o"
fallback_models "gpt-4o-mini"
circuit_breaker errors: 5, within: 60, cooldown: 120
```

### Monitor Breaker Events

```ruby
# Track breaker open events
RubyLLM::Agents::Execution
  .where("attempts @> ?", '[{"short_circuited": true}]')
  .count

# Alert on frequent breaker openings
# Indicates persistent service issues
```

## Troubleshooting

### Breaker Opens Too Often

- Increase `errors` threshold
- Increase `within` window
- Check for actual service issues

### Breaker Never Opens

- Decrease `errors` threshold
- Ensure errors are being counted correctly
- Check error types are retryable

### Service Recovered But Still Blocked

- Wait for cooldown
- Manually close breaker if urgent:
  ```ruby
  RubyLLM::Agents::CircuitBreaker.close!("gpt-4o")
  ```

## Related Pages

- [Reliability](Reliability) - Overview of reliability features
- [Automatic Retries](Automatic-Retries) - Retry configuration
- [Model Fallbacks](Model-Fallbacks) - Fallback model chains
- [Alerts](Alerts) - Notification setup
