# Frequently Asked Questions

Common questions about RubyLLM::Agents.

## General

### What is RubyLLM::Agents?

RubyLLM::Agents is a Rails engine for building, managing, and monitoring LLM-powered AI agents. It provides:
- Clean DSL for agent configuration
- Automatic execution tracking
- Cost analytics and budget controls
- Reliability features (retries, fallbacks, circuit breakers)
- Real-time dashboard

### How is it different from LangChain?

| Aspect | RubyLLM::Agents | LangChain |
|--------|-----------------|-----------|
| Language | Ruby/Rails | Python/JS |
| Integration | Rails-native | Framework-agnostic |
| Focus | Production operations | Rapid prototyping |
| Observability | Built-in dashboard | Requires add-ons |
| Cost tracking | Automatic | Manual |

### What LLM providers are supported?

Through RubyLLM, we support:
- OpenAI (GPT-4, GPT-4o, GPT-3.5)
- Anthropic (Claude 3.5, Claude 3)
- Google (Gemini 2.0, Gemini 1.5)
- And more via RubyLLM

### What Ruby/Rails versions are required?

- Ruby >= 3.1.0
- Rails >= 7.0

---

## Configuration

### How do I set API keys?

```ruby
# Environment variables (recommended)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...

# Or Rails credentials
rails credentials:edit
```

### How do I change the default model?

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_model = "gpt-4o"
end
```

### How do I enable caching?

```ruby
class MyAgent < ApplicationAgent
  cache 1.hour  # Cache for 1 hour
end
```

### How do I configure the dashboard?

```ruby
config.dashboard_auth = ->(controller) {
  controller.current_user&.admin?
}
```

---

## Usage

### How do I call an agent?

```ruby
result = MyAgent.call(query: "test")
result.content      # The response
result.total_cost   # Cost in USD
```

### How do I use streaming?

```ruby
class StreamingAgent < ApplicationAgent
  streaming true
end

StreamingAgent.call(prompt: "Write a story") do |chunk|
  print chunk
end
```

### How do I send images to an agent?

```ruby
result = VisionAgent.call(
  question: "Describe this image",
  with: "photo.jpg"
)
```

### How do I get structured output?

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :title
    array :tags, of: :string
  end
end
```

### How do I debug an agent?

```ruby
result = MyAgent.call(query: "test", dry_run: true)
# Shows prompts without making API call
```

---

## Costs & Budgets

### How are costs calculated?

Costs are calculated based on:
- Input tokens × model input price
- Output tokens × model output price

Prices are from RubyLLM's model pricing data.

### How do I set budget limits?

```ruby
config.budgets = {
  global_daily: 100.0,      # $100/day
  global_monthly: 2000.0,   # $2000/month
  enforcement: :hard        # Block when exceeded
}
```

### How do I check current spending?

```ruby
RubyLLM::Agents::BudgetTracker.status
# => { global_daily: { limit: 100, current: 45.50, ... } }
```

### Why is my agent blocked?

Check if budget is exceeded:
```ruby
RubyLLM::Agents::BudgetTracker.exceeded?(:global, :daily)
```

---

## Reliability

### How do retries work?

```ruby
retries max: 3, backoff: :exponential
```

Failed requests are automatically retried with increasing delays.

### How do fallbacks work?

```ruby
model "gpt-4o"
fallback_models "gpt-4o-mini", "claude-3-haiku"
```

If the primary model fails, fallbacks are tried in order.

### What is a circuit breaker?

Circuit breakers prevent cascading failures by temporarily blocking requests to failing services.

```ruby
circuit_breaker errors: 10, within: 60, cooldown: 300
```

After 10 errors in 60 seconds, requests are blocked for 5 minutes.

---

## Performance

### How do I improve latency?

1. Enable caching: `cache 1.hour`
2. Use streaming: `streaming true`
3. Use faster models: `model "gpt-4o-mini"`
4. Enable async logging: `config.async_logging = true`

### How do I reduce costs?

1. Enable caching
2. Use cheaper models for simple tasks
3. Set budget limits
4. Optimize prompts (shorter = cheaper)

### Why is the dashboard slow?

1. Too much data: Set `config.retention_period = 30.days`
2. Missing indexes: Run `rails generate ruby_llm_agents:upgrade`
3. Complex queries: Reduce `config.dashboard_per_page`

---

## Data & Privacy

### What data is logged?

By default:
- Agent type, model, status
- Token counts, costs, duration
- Parameters
- Prompts (optional)
- Responses (optional)

### How do I disable prompt storage?

```ruby
config.persist_prompts = false
config.persist_responses = false
```

### How long is data retained?

```ruby
config.retention_period = 30.days
```

Run cleanup regularly to delete old data.

---

## Chaining Agents

### How do I chain agents together?

Compose agents by calling one from another's result:

```ruby
# Sequential composition
intent_result = IntentAgent.call(query: user_input)
response_result = ResponseAgent.call(
  query: user_input,
  intent: intent_result.content[:intent]
)
```

For complex orchestration patterns (pipelines, parallel execution, routing), use a dedicated workflow library like Temporal or Sidekiq.

---

## Troubleshooting

### Agent returns nil

1. Check for errors: `result.success?`
2. Check schema matches response
3. Try dry_run to see prompts

### Executions not appearing in dashboard

1. Check async logging: Is job processor running?
2. Try sync: `config.async_logging = false`
3. Check for database errors

### Rate limit errors

1. Add retries with backoff
2. Add fallback models
3. Implement request queuing

### Memory issues

1. Disable response storage
2. Set retention period
3. Use streaming for large responses

---

## Getting Help

### Where can I report bugs?

GitHub Issues: https://github.com/adham90/ruby_llm-agents/issues

### Where can I ask questions?

GitHub Discussions: https://github.com/adham90/ruby_llm-agents/discussions

### How do I contribute?

See [Contributing](Contributing) guide.

## Related Pages

- [Troubleshooting](Troubleshooting) - Detailed solutions
- [Configuration](Configuration) - Full config reference
- [API Reference](API-Reference) - Class documentation
