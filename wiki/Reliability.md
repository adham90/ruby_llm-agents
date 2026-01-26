# Reliability Features

Build resilient AI agents that handle failures gracefully with built-in retries, fallbacks, and circuit breakers.

## Overview

LLM APIs can fail for many reasons:
- Rate limits
- Network timeouts
- Service outages
- Transient errors

RubyLLM::Agents provides three layers of protection:

| Feature | Purpose |
|---------|---------|
| **Retries** | Retry failed requests with backoff |
| **Fallbacks** | Try alternative models |
| **Circuit Breaker** | Prevent cascading failures |

## Quick Start

```ruby
class ReliableAgent < ApplicationAgent
  model "gpt-4o"

  # Retry up to 3 times with exponential backoff
  retries max: 3, backoff: :exponential

  # Fall back to alternative models
  fallback_models "gpt-4o-mini", "claude-3-5-sonnet"

  # Prevent cascading failures
  circuit_breaker errors: 10, within: 60, cooldown: 300

  # Maximum total time
  total_timeout 30

  param :query, required: true

  def user_prompt
    query
  end
end
```

## Execution Flow

When you call an agent with reliability features:

```
1. Try primary model (gpt-4o)
   ├─ Success → Return result
   └─ Failure → Check circuit breaker
       ├─ Breaker OPEN → Skip to fallback
       └─ Breaker CLOSED → Retry with backoff
           ├─ Retry 1, 2, 3...
           ├─ Success → Return result
           └─ All retries failed → Try fallback model

2. Try first fallback (gpt-4o-mini)
   └─ Same retry logic...

3. Try second fallback (claude-3-5-sonnet)
   └─ Same retry logic...

4. All models failed → Raise error
```

## Viewing Attempt Details

The execution record captures all attempts:

```ruby
result = ReliableAgent.call(query: "test")

# Check what happened
result.attempts_count    # => 3 (total attempts)
result.used_fallback?    # => true (if fallback was used)
result.chosen_model_id   # => "claude-3-5-sonnet" (model that succeeded)

# Get from execution record
execution = RubyLLM::Agents::Execution.last
execution.attempts.each do |attempt|
  puts "Model: #{attempt['model_id']}"
  puts "Success: #{attempt['success']}"
  puts "Duration: #{attempt['duration_ms']}ms"
  puts "Error: #{attempt['error_class']}" if attempt['error_class']
end
```

## Dashboard Integration

The dashboard shows:
- Retry counts per execution
- Fallback usage statistics
- Circuit breaker status
- Success rates by model

## Configuration Combinations

### High Availability

```ruby
class HighAvailabilityAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 5, backoff: :exponential, max_delay: 30.0
  fallback_models "gpt-4o-mini", "claude-3-5-sonnet", "gemini-2.0-flash"
  circuit_breaker errors: 5, within: 30, cooldown: 120
  total_timeout 60
end
```

### Fast Fail

```ruby
class FastFailAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 1
  total_timeout 5
  # No fallbacks - fail fast
end
```

### Cost-Optimized

```ruby
class CostOptimizedAgent < ApplicationAgent
  model "gpt-4o-mini"  # Start with cheaper model
  retries max: 2
  fallback_models "gpt-3.5-turbo"  # Even cheaper fallback
  # No circuit breaker - rely on rate limiting
end
```

## Default Retryable Errors

These errors trigger retries automatically:

- `Timeout::Error`
- `Net::ReadTimeout`
- `Faraday::TimeoutError`
- `Errno::ECONNREFUSED`
- `Errno::ECONNRESET`
- `Errno::ETIMEDOUT`
- `SocketError`
- `OpenSSL::SSL::SSLError`
- Errors with messages matching:
  - `/rate.?limit/i`
  - `/too.?many.?requests/i`
  - `/5\d\d/` (5xx status codes)

## Custom Retryable Errors

Add your own error types:

```ruby
class MyAgent < ApplicationAgent
  retries max: 3, on: [
    Timeout::Error,
    MyCustomError,
    ServiceUnavailableError
  ]
end
```

## Monitoring & Alerting

Get notified when reliability features are triggered:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    on_events: [:breaker_open],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
  }
end
```

See [Alerts](Alerts) for more notification options.

## Detailed Guides

- **[Automatic Retries](Automatic-Retries)** - Configure retry behavior
- **[Model Fallbacks](Model-Fallbacks)** - Set up fallback chains
- **[Circuit Breakers](Circuit-Breakers)** - Prevent cascading failures

## Related Pages

- [Agent DSL](Agent-DSL) - Reliability configuration
- [Execution Tracking](Execution-Tracking) - View attempt history
- [Dashboard](Dashboard) - Monitor reliability metrics
