# Custom Middleware

Inject your own middleware into the agent execution pipeline — globally for all agents or per-agent.

## Writing Custom Middleware

Custom middleware must inherit from `RubyLLM::Agents::Pipeline::Middleware::Base`:

```ruby
class AuditMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    # Pre-execution: inspect input, model, tenant
    AuditLog.create!(agent: context.agent_class.name, input: context.input)

    result = @app.call(context)

    # Post-execution: inspect output, cost, duration
    AuditLog.last.update!(status: context.success? ? "ok" : "error")
    result
  end
end
```

### Available in `call(context)`

| Accessor | Description |
|----------|-------------|
| `@app` | Next middleware in the chain — **must** call `@app.call(context)` |
| `@agent_class` | The agent class being executed |
| `context.input` | User prompt / input |
| `context.model` | Configured model |
| `context.tenant_id` | Tenant identifier |
| `context.output` | Result (available after `@app.call`) |
| `context.total_cost` | Execution cost (after) |
| `context.duration_ms` | Execution duration (after) |
| `context.success?` | Whether execution succeeded (after) |

### Helper Methods

The base class provides:

```ruby
config(:method_name, default)  # Read agent class config safely
global_config                  # RubyLLM::Agents.configuration
debug("message")               # Rails.logger.debug
error("message")               # Rails.logger.error
```

## Global Middleware

Register middleware for all agents in the configuration:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.use_middleware AuditMiddleware
  config.use_middleware RateLimitMiddleware, before: RubyLLM::Agents::Pipeline::Middleware::Cache
  config.use_middleware TracingMiddleware, after: RubyLLM::Agents::Pipeline::Middleware::Tenant
end
```

### Clearing Global Middleware

```ruby
RubyLLM::Agents.configuration.clear_middleware!
```

## Per-Agent Middleware

Register middleware on specific agent classes:

```ruby
class SensitiveAgent < ApplicationAgent
  model "gpt-4o"
  use_middleware ContentModerationMiddleware
  use_middleware ComplianceMiddleware, before: RubyLLM::Agents::Pipeline::Middleware::Instrumentation
end
```

Per-agent middleware is inherited by subclasses:

```ruby
class ApplicationAgent < RubyLLM::Agents::Base
  use_middleware AuditMiddleware  # All agents get this
end

class SensitiveAgent < ApplicationAgent
  use_middleware ContentModerationMiddleware  # Only this agent gets this (plus inherited)
end
```

## Execution Order

The pipeline executes middleware in this order:

```
1. Tenant           (built-in, always)
2. Budget           (built-in, if enabled)
3. Instrumentation  (built-in, always)
4. Cache            (built-in, if enabled)
5. Reliability      (built-in, if enabled)
6. [global custom middleware]
7. [per-agent custom middleware]
-> Core Executor
```

Use `before:` or `after:` to position custom middleware relative to built-in middleware:

```ruby
# Run before any caching
config.use_middleware MyMiddleware, before: RubyLLM::Agents::Pipeline::Middleware::Cache

# Run right after tenant resolution
config.use_middleware MyMiddleware, after: RubyLLM::Agents::Pipeline::Middleware::Tenant
```

Without positioning, middleware appends to the end (just before core executor).

## Examples

### Content Moderation

```ruby
class ContentModerationMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    raise "Blocked: unsafe input" if contains_pii?(context.input)

    result = @app.call(context)

    if context.output && contains_pii?(context.output.content)
      context.output = redact(context.output)
    end

    result
  end

  private

  def contains_pii?(text)
    # Your PII detection logic
  end

  def redact(output)
    # Your redaction logic
  end
end
```

### Rate Limiting

```ruby
class RateLimitMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    key = "agent_rate:#{context.tenant_id}:#{Time.current.beginning_of_minute.to_i}"
    count = Rails.cache.increment(key, 1, expires_in: 2.minutes)

    if count > 60  # 60 requests per minute
      raise "Rate limit exceeded for tenant #{context.tenant_id}"
    end

    @app.call(context)
  end
end
```

### Request Tracing (OpenTelemetry)

```ruby
class TracingMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm_agents")

    tracer.in_span("agent.execute", attributes: {
      "agent.type" => context.agent_class.name,
      "agent.model" => context.model,
      "agent.tenant" => context.tenant_id
    }) do |span|
      result = @app.call(context)

      span.set_attribute("agent.tokens", context.total_tokens)
      span.set_attribute("agent.cost", context.total_cost)
      span.set_attribute("agent.cached", context.cached?)

      result
    end
  end
end
```

### Compliance Logging

```ruby
class AuditMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    audit = AuditLog.create!(
      agent: context.agent_class.name,
      tenant_id: context.tenant_id,
      input_hash: Digest::SHA256.hexdigest(context.input.to_s),
      started_at: Time.current
    )

    result = @app.call(context)

    audit.update!(
      status: context.success? ? "success" : "error",
      duration_ms: context.duration_ms,
      completed_at: Time.current
    )

    result
  rescue => e
    audit&.update!(status: "error", error: e.message)
    raise
  end
end
```

## Testing Custom Middleware

```ruby
RSpec.describe AuditMiddleware do
  let(:app) do
    ->(ctx) {
      ctx.output = RubyLLM::Agents::Result.new(content: "done")
      ctx
    }
  end

  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name; "TestAgent"; end
      model "gpt-4o"
    end
  end

  it "creates an audit log" do
    middleware = described_class.new(app, agent_class)
    context = RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class
    )

    middleware.call(context)

    expect(AuditLog.count).to eq(1)
    expect(AuditLog.last.status).to eq("success")
  end
end
```

## Related Pages

- [Configuration](Configuration) - Global configuration reference
- [Agent DSL](Agent-DSL) - Per-agent configuration
- [ActiveSupport Notifications](ActiveSupport-Notifications) - Built-in instrumentation events
- [Reliability](Reliability) - Built-in retry/fallback/circuit breaker middleware
