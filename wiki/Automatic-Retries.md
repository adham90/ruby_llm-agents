# Automatic Retries

Configure automatic retry behavior for handling transient failures.

## Basic Configuration

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 3  # Retry up to 3 times
end
```

## Backoff Strategies

### Exponential Backoff (Recommended)

Delay doubles each retry to avoid overwhelming the API:

```ruby
retries max: 3, backoff: :exponential
# Delays: ~0.5s, ~1s, ~2s, ~4s...
```

With custom timing:

```ruby
retries max: 3, backoff: :exponential, base: 1.0, max_delay: 30.0
# base: Initial delay in seconds
# max_delay: Maximum delay cap
```

### Constant Backoff

Same delay between each retry:

```ruby
retries max: 3, backoff: :constant, base: 2.0
# Delays: 2s, 2s, 2s
```

### Jitter

Jitter is automatically added to prevent thundering herd:

```ruby
# Actual delay = calculated_delay * random(0.5..1.5)
# Example with exponential:
# Base 1s → actual 0.5-1.5s
# Base 2s → actual 1-3s
# Base 4s → actual 2-6s
```

## Custom Error Types

Specify which errors should trigger retries:

```ruby
class MyAgent < ApplicationAgent
  retries max: 3, on: [
    Timeout::Error,
    Net::ReadTimeout,
    Faraday::TimeoutError,
    MyCustomError
  ]
end
```

## Default Retryable Errors

By default, these errors are retried:

```ruby
# Network/Timeout errors
Timeout::Error
Net::ReadTimeout
Net::OpenTimeout
Faraday::TimeoutError
Faraday::ConnectionFailed
Errno::ECONNREFUSED
Errno::ECONNRESET
Errno::ETIMEDOUT
SocketError
OpenSSL::SSL::SSLError

# Rate limiting (by message pattern)
/rate.?limit/i
/too.?many.?requests/i
/429/

# Server errors (by message pattern)
/5\d\d/  # 500, 502, 503, etc.
```

## Total Timeout

Set a maximum time for all attempts:

```ruby
class MyAgent < ApplicationAgent
  retries max: 5
  total_timeout 30  # Abort everything after 30 seconds
end
```

Without `total_timeout`, 5 retries with exponential backoff could take several minutes.

## Retry Lifecycle

```ruby
# What happens during retries:

1. Initial attempt
   └─ Error: Rate limit

2. Wait 0.5-1.5s (jittered)

3. Retry 1
   └─ Error: Rate limit

4. Wait 1-3s (jittered)

5. Retry 2
   └─ Error: Rate limit

6. Wait 2-6s (jittered)

7. Retry 3
   └─ Success! Return result

# Or if total_timeout reached:
   └─ Timeout::Error raised
```

## Viewing Retry Details

```ruby
result = MyAgent.call(query: "test")

# Number of attempts (including initial)
result.attempts_count  # => 3

# Get execution record
execution = RubyLLM::Agents::Execution.last

# Each attempt is recorded
execution.attempts.each do |attempt|
  puts "Attempt at: #{attempt['started_at']}"
  puts "Duration: #{attempt['duration_ms']}ms"
  puts "Error: #{attempt['error_class']}: #{attempt['error_message']}"
end
```

## Configuration Examples

### High Reliability

```ruby
class HighReliabilityAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 5, backoff: :exponential, base: 1.0, max_delay: 30.0
  total_timeout 120  # 2 minutes max
end
```

### Fast Response

```ruby
class FastAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 2, backoff: :constant, base: 0.5
  total_timeout 10
end
```

### Background Jobs

```ruby
class BackgroundAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 10, backoff: :exponential, max_delay: 60.0
  total_timeout 300  # 5 minutes OK for background
end
```

### No Retries

```ruby
class NoRetryAgent < ApplicationAgent
  model "gpt-4o"
  # No retries configuration = fail immediately
end
```

## Combining with Fallbacks

Retries work with fallback models:

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 2
  fallback_models "gpt-4o-mini"
end

# Flow:
# 1. gpt-4o attempt 1 → fails
# 2. gpt-4o attempt 2 → fails
# 3. gpt-4o attempt 3 → fails
# 4. gpt-4o-mini attempt 1 → fails
# 5. gpt-4o-mini attempt 2 → succeeds!
```

## Best Practices

### Don't Over-Retry

```ruby
# Good: Limited retries with reasonable timeout
retries max: 3, backoff: :exponential
total_timeout 30

# Bad: Too many retries, too long
retries max: 10, max_delay: 120.0
# Could take 10+ minutes to fail
```

### Match Retry Strategy to Use Case

```ruby
# User-facing: Fast fail, short retries
retries max: 2
total_timeout 10

# Background: More patience
retries max: 5
total_timeout 120
```

### Log Failed Attempts

```ruby
def call
  super
rescue => e
  Rails.logger.error("Agent failed after retries: #{e.message}")
  raise
end
```

### Monitor Retry Rates

```ruby
# High retry rates indicate issues
retry_rate = RubyLLM::Agents::Execution
  .this_week
  .where("(attempts->0->>'success')::boolean = false")
  .count
  .to_f / RubyLLM::Agents::Execution.this_week.count

if retry_rate > 0.1  # More than 10% need retries
  Rails.logger.warn("High retry rate: #{retry_rate}")
end
```

## Related Pages

- [Reliability](Reliability) - Overview of reliability features
- [Model Fallbacks](Model-Fallbacks) - Fallback model chains
- [Circuit Breakers](Circuit-Breakers) - Prevent cascading failures
- [Agent DSL](Agent-DSL) - Configuration reference
