# Error Handling

Understanding and handling errors in RubyLLM::Agents.

## Error Class Hierarchy

```
StandardError
└── RubyLLM::Agents::Error (base class)
    ├── RubyLLM::Agents::BudgetExceededError
    ├── RubyLLM::Agents::CircuitBreakerOpenError
    ├── RubyLLM::Agents::ConfigurationError
    ├── RubyLLM::Agents::TimeoutError
    └── RubyLLM::Agents::ValidationError
```

## Error Types

### BudgetExceededError

Raised when budget limits are exceeded (with `:hard` enforcement):

```ruby
begin
  result = LLM::ExpensiveAgent.call(query: params[:query])
rescue RubyLLM::Agents::BudgetExceededError => e
  e.message       # => "Daily budget exceeded: $100.00 limit reached"
  e.budget_type   # => :daily or :monthly
  e.budget_scope  # => :global, :per_agent, or :tenant
  e.limit         # => 100.0
  e.current       # => 105.50
  e.tenant_budget? # => true/false (v0.4.0+)

  # Handle gracefully
  render json: { error: "Service temporarily unavailable" }, status: 503
end
```

### CircuitBreakerOpenError

Raised when the circuit breaker is open (too many recent failures):

```ruby
begin
  result = LLM::MyAgent.call(query: params[:query])
rescue RubyLLM::Agents::CircuitBreakerOpenError => e
  e.message       # => "Circuit breaker open for MyAgent"
  e.agent_type    # => "MyAgent"
  e.cooldown_ends # => Time object when circuit will close
  e.remaining_ms  # => Milliseconds until retry is allowed

  # Suggest retry time
  render json: {
    error: "Service temporarily unavailable",
    retry_after: e.remaining_ms / 1000
  }, status: 503
end
```

### ConfigurationError

Raised when agent configuration is invalid:

```ruby
# Missing required configuration
module LLM
  class BadAgent < ApplicationAgent
    # No model specified
    param :query, required: true
  end
end

LLM::BadAgent.call(query: "test")
# => Raises ConfigurationError: "Model must be configured"
```

### TimeoutError

Raised when `total_timeout` is exceeded:

```ruby
begin
  result = LLM::SlowAgent.call(query: params[:query])
rescue RubyLLM::Agents::TimeoutError => e
  e.message     # => "Total timeout of 30s exceeded"
  e.timeout     # => 30
  e.elapsed     # => 31.5
  e.attempts    # => 3 (attempts made before timeout)

  render json: { error: "Request timed out" }, status: 504
end
```

### ValidationError

Raised when parameter validation fails:

```ruby
module LLM
  class TypedAgent < ApplicationAgent
    param :count, type: :integer, required: true
  end
end

LLM::TypedAgent.call(count: "not a number")
# => Raises ValidationError: "Parameter 'count' must be Integer, got String"
```

## Retryable vs Non-Retryable Errors

RubyLLM::Agents automatically classifies errors:

### Retryable Errors (automatic retry)

- `Faraday::TimeoutError` - Request timeout
- `Faraday::ConnectionFailed` - Connection issues
- `RubyLLM::RateLimitError` - Rate limit exceeded
- `Net::OpenTimeout` - Connection timeout
- `Errno::ECONNREFUSED` - Connection refused

### Non-Retryable Errors (fail immediately)

- `RubyLLM::AuthenticationError` - Invalid API key
- `RubyLLM::InvalidRequestError` - Bad request parameters
- `ArgumentError` - Missing required parameters
- `RubyLLM::Agents::BudgetExceededError` - Budget exceeded
- `RubyLLM::Agents::CircuitBreakerOpenError` - Circuit open

### Checking Error Type in Results

```ruby
result = LLM::MyAgent.call(query: "test")

unless result.success?
  if result.retryable?
    # Safe to retry later
    RetryJob.perform_later(query: "test")
  else
    # Don't retry, handle differently
    notify_admin(result.error)
  end
end
```

## Recovery Patterns

### Basic Error Handling

```ruby
def search(query)
  result = LLM::SearchAgent.call(query: query)

  if result.success?
    result.content
  else
    # Return cached/default response
    cached_search(query) || default_response
  end
rescue RubyLLM::Agents::BudgetExceededError
  { error: "Search temporarily unavailable", results: [] }
rescue RubyLLM::Agents::CircuitBreakerOpenError => e
  { error: "Service degraded, retry in #{e.remaining_ms / 1000}s", results: [] }
end
```

### Graceful Degradation

```ruby
class SearchService
  def search(query)
    # Try AI-powered search first
    ai_search(query)
  rescue RubyLLM::Agents::Error
    # Fall back to basic search
    basic_search(query)
  end

  private

  def ai_search(query)
    result = LLM::SearchAgent.call(query: query)
    raise result.error unless result.success?
    result.content[:results]
  end

  def basic_search(query)
    # Simple database search as fallback
    Product.search(query).limit(10)
  end
end
```

### Retry with Backoff

```ruby
class AgentRetryService
  MAX_RETRIES = 3
  BASE_DELAY = 1

  def call(agent_class, **params)
    retries = 0

    begin
      agent_class.call(**params)
    rescue RubyLLM::Agents::Error => e
      raise unless e.retryable? && retries < MAX_RETRIES

      retries += 1
      sleep(BASE_DELAY * (2 ** retries))
      retry
    end
  end
end
```

### Queue for Later Processing

```ruby
class AgentJob < ApplicationJob
  retry_on RubyLLM::Agents::CircuitBreakerOpenError, wait: :polynomially_longer
  discard_on RubyLLM::Agents::BudgetExceededError

  def perform(agent_class_name, **params)
    agent_class = agent_class_name.constantize
    result = agent_class.call(**params)

    if result.success?
      ResultHandler.process(result)
    else
      handle_failure(result)
    end
  end

  private

  def handle_failure(result)
    Rails.logger.error("Agent failed: #{result.error}")
    notify_admin(result)
  end
end
```

## Controller Error Handling

### Rescue From Pattern

```ruby
class ApplicationController < ActionController::Base
  rescue_from RubyLLM::Agents::BudgetExceededError, with: :handle_budget_exceeded
  rescue_from RubyLLM::Agents::CircuitBreakerOpenError, with: :handle_circuit_open
  rescue_from RubyLLM::Agents::TimeoutError, with: :handle_timeout

  private

  def handle_budget_exceeded(error)
    render json: {
      error: "Service limit reached",
      type: "budget_exceeded"
    }, status: :service_unavailable
  end

  def handle_circuit_open(error)
    response.headers["Retry-After"] = (error.remaining_ms / 1000).to_s

    render json: {
      error: "Service temporarily unavailable",
      type: "circuit_open",
      retry_after: error.remaining_ms / 1000
    }, status: :service_unavailable
  end

  def handle_timeout(error)
    render json: {
      error: "Request timed out",
      type: "timeout"
    }, status: :gateway_timeout
  end
end
```

### API-Specific Handling

```ruby
class Api::V1::SearchController < Api::BaseController
  def search
    result = LLM::SearchAgent.call(query: params[:q])

    if result.success?
      render json: {
        data: result.content,
        meta: {
          tokens: result.total_tokens,
          cost: result.total_cost,
          duration_ms: result.duration_ms
        }
      }
    else
      render json: {
        error: result.error,
        retryable: result.retryable?
      }, status: :unprocessable_entity
    end
  end
end
```

## Monitoring and Alerting

### Error Rate Monitoring

```ruby
# Track error rates
error_rate = RubyLLM::Agents::Execution
  .today
  .by_agent("MyAgent")
  .then { |e| e.failed.count.to_f / e.count }

if error_rate > 0.1  # >10% error rate
  SlackNotifier.alert("High error rate for MyAgent: #{(error_rate * 100).round}%")
end
```

### Error Type Breakdown

```ruby
# Analyze failure reasons
RubyLLM::Agents::Execution
  .today
  .failed
  .group(:error_message)
  .count
  .sort_by { |_, count| -count }
  .first(5)
# => [["Rate limit exceeded", 45], ["Timeout", 12], ...]
```

### Setting Up Alerts

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    on_events: [
      :budget_soft_cap,
      :budget_hard_cap,
      :breaker_open,
      :high_error_rate
    ],
    slack_webhook_url: ENV["SLACK_WEBHOOK_URL"],
    custom: ->(event, payload) {
      case event
      when :breaker_open
        PagerDuty.trigger(
          summary: "Circuit breaker open for #{payload[:agent_type]}",
          severity: "warning"
        )
      when :high_error_rate
        Rails.logger.error("High error rate: #{payload}")
      end
    }
  }
end
```

## Best Practices

1. **Always check `result.success?`** - Don't assume calls succeed
2. **Use rescue blocks sparingly** - Prefer checking result status
3. **Log errors with context** - Include agent type, parameters, and timing
4. **Set up monitoring** - Track error rates and patterns
5. **Implement graceful degradation** - Have fallback strategies
6. **Use circuit breakers** - Prevent cascade failures
7. **Configure appropriate timeouts** - Balance responsiveness and reliability

## Related Pages

- [Reliability](Reliability) - Retries and fallbacks
- [Circuit Breakers](Circuit-Breakers) - Failure protection
- [Budget Controls](Budget-Controls) - Spending limits
- [Execution Tracking](Execution-Tracking) - Error logging
- [Testing Agents](Testing-Agents) - Testing error paths
