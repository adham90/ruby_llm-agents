# Best Practices

Guidelines for building production-ready LLM agents with RubyLLM::Agents.

## Agent Design

### 1. Use ApplicationAgent as Base Class

Centralize shared configuration:

```ruby
# app/agents/application_agent.rb
class ApplicationAgent < RubyLLM::Agents::Base
  # Shared defaults
  temperature 0.0

  reliability do
    retries max: 3, backoff: :exponential
    total_timeout 60
  end

  # Common metadata
  def execution_metadata
    {
      request_id: Current.request_id,
      user_id: Current.user&.id
    }
  end
end
```

### 2. Set Explicit Versions

Invalidate cache when agent logic changes:

```ruby
module LLM
  class SearchAgent < ApplicationAgent
    version "2.1"  # Bump when changing prompts or logic
    cache_for 1.hour
  end
end
```

### 3. Type Your Parameters

Catch type errors early:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    param :query, type: String, required: true
    param :limit, type: Integer, default: 10
    param :filters, type: Hash, default: {}
  end
end
```

### 4. Use Structured Output

Ensure predictable responses:

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result, description: "The processed result"
    array :items, of: :string
    boolean :success
  end
end
```

## Reliability

### 5. Enable Reliability for Production

Don't rely on single requests:

```ruby
module LLM
  class ProductionAgent < ApplicationAgent
    model "gpt-4o"

    reliability do
      retries max: 3, backoff: :exponential
      fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
      circuit_breaker errors: 10, within: 60, cooldown: 300
      total_timeout 30
    end
  end
end
```

### 6. Use the reliability Block

Group related config together:

```ruby
# Good - organized
reliability do
  retries max: 3, backoff: :exponential
  fallback_models "gpt-4o-mini"
  total_timeout 30
end

# Less clear - scattered
retries max: 3, backoff: :exponential
fallback_models "gpt-4o-mini"
total_timeout 30
```

## Cost Management

### 7. Set Budgets

Prevent runaway costs:

```ruby
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 100.0,
    global_monthly: 2000.0,
    per_agent_daily: { "ExpensiveAgent" => 50.0 },
    enforcement: :hard
  }
end
```

### 8. Cache Expensive Operations

Reduce API calls:

```ruby
module LLM
  class ExpensiveAgent < ApplicationAgent
    cache_for 2.hours

    # Custom cache key to maximize hits
    def cache_key_data
      { query: query.downcase.strip }
    end
  end
end
```

### 9. Use cache_for over cache

Clearer intent, no deprecation warning:

```ruby
# Good
cache_for 1.hour

# Deprecated
cache 1.hour
```

## Observability

### 10. Monitor via Dashboard

Track costs, errors, and latency:

```ruby
# Mount dashboard
mount RubyLLM::Agents::Engine => "/agents"

# Set up authentication
config.dashboard_auth = ->(c) { c.current_user&.admin? }
```

### 11. Add Meaningful Metadata

Enable filtering and debugging:

```ruby
def execution_metadata
  {
    user_id: user_id,
    feature: "search",
    source: source,
    experiment_variant: experiment_variant
  }
end
```

### 12. Set Up Alerts

Get notified of issues:

```ruby
config.alerts = {
  on_events: [:budget_hard_cap, :breaker_open],
  slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
}
```

## Development

### 13. Test with dry_run

Debug prompts without API calls:

```ruby
result = LLM::MyAgent.call(query: "test", dry_run: true)
puts result.content[:user_prompt]
puts result.content[:system_prompt]
```

### 14. Use Generators

Scaffold quickly:

```bash
rails generate ruby_llm_agents:agent search query:required limit:10
rails generate ruby_llm_agents:embedder document --dimensions 512
```

### 15. Write Agent Tests

Mock LLM responses:

```ruby
RSpec.describe SearchAgent do
  let(:mock_response) do
    double(content: { results: [] }, input_tokens: 10, output_tokens: 5)
  end

  before do
    allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)
  end

  it "returns results" do
    result = described_class.call(query: "test")
    expect(result.content[:results]).to eq([])
  end
end
```

## Security

### 16. Enable PII Redaction

Protect sensitive data in logs:

```ruby
config.redaction = {
  fields: %w[password api_key email ssn],
  patterns: [/\b\d{3}-\d{2}-\d{4}\b/],
  placeholder: "[REDACTED]"
}
```

### 17. Control Prompt Persistence

Disable for sensitive applications:

```ruby
config.persist_prompts = false
config.persist_responses = false
```

### 18. Use Content Moderation

Block harmful content:

```ruby
module LLM
  class SafeAgent < ApplicationAgent
    moderation :both,
      threshold: 0.7,
      on_flagged: :block
  end
end
```

## Performance

### 19. Use Streaming for Long Responses

Better UX for chat interfaces:

```ruby
module LLM
  class ChatAgent < ApplicationAgent
    streaming true
  end
end

LLM::ChatAgent.call(message: msg) do |chunk|
  stream << chunk.content
end
```

### 20. Use Appropriate Models

Match model to task:

```ruby
module LLM
  # Classification - fast, cheap, deterministic
  class ClassifierAgent < ApplicationAgent
    model "gpt-4o-mini"
    temperature 0.0
  end

  # Creative writing - more capable
  class WriterAgent < ApplicationAgent
    model "gpt-4o"
    temperature 0.8
  end

  # Simple extraction - fastest
  class ExtractorAgent < ApplicationAgent
    model "gemini-2.0-flash"
    temperature 0.0
  end
end
```

## Multi-Tenancy

### 21. Isolate Tenant Data

Set up proper tenant resolution:

```ruby
config.multi_tenancy_enabled = true
config.tenant_resolver = -> { Current.tenant&.id }
```

### 22. Set Per-Tenant Budgets

Prevent tenant cost overruns:

```ruby
RubyLLM::Agents::TenantBudget.create!(
  tenant_id: "acme_corp",
  daily_limit: 50.0,
  monthly_limit: 500.0,
  enforcement: "hard"
)
```

## Deprecation Handling

### 23. Address Deprecation Warnings

Update deprecated methods:

```ruby
# Deprecated
cache 1.hour
result[:key]
result.dig(:a, :b)

# Preferred
cache_for 1.hour
result.content[:key]
result.content.dig(:a, :b)
```

Silence warnings during migration:

```ruby
RubyLLM::Agents::Deprecations.silenced = true
```

## Related Pages

- [Testing Agents](Testing-Agents) - Testing patterns
- [Production Deployment](Production-Deployment) - Deployment guide
- [Error Handling](Error-Handling) - Error recovery
- [Configuration](Configuration) - All settings
