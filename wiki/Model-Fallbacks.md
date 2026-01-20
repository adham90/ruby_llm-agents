# Model Fallbacks

Automatically try alternative models when your primary model fails.

## Basic Configuration

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
  end
end
```

## How Fallbacks Work

When the primary model fails (after any retries):

```
1. Primary: gpt-4o
   └─ Fails after retries

2. Fallback 1: gpt-4o-mini
   └─ Succeeds! Return result

# If fallback 1 also fails:

3. Fallback 2: claude-3-5-sonnet
   └─ Succeeds! Return result

# If all fail:
   └─ Raise error
```

## With Retries

Each model gets its own retry attempts:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    retries max: 2
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
  end
end

# Total possible attempts:
# gpt-4o: 3 attempts (1 + 2 retries)
# gpt-4o-mini: 3 attempts
# claude-3-5-sonnet: 3 attempts
# = Up to 9 attempts total
```

## Tracking Fallback Usage

```ruby
result = LLM::MyAgent.call(query: "test")

# Check which model succeeded
result.model_id         # Original model requested
result.chosen_model_id  # Model that actually succeeded
result.used_fallback?   # true if not the primary model

# Example
result.model_id         # => "gpt-4o"
result.chosen_model_id  # => "claude-3-5-sonnet"
result.used_fallback?   # => true
```

## Execution Record Details

```ruby
execution = RubyLLM::Agents::Execution.last

execution.model_id        # => "gpt-4o"
execution.chosen_model_id # => "claude-3-5-sonnet"

execution.attempts.each do |attempt|
  puts "Model: #{attempt['model_id']}"
  puts "Success: #{attempt['success']}"
  puts "Error: #{attempt['error_class']}" unless attempt['success']
end
```

## Fallback Strategies

### Cost Optimization

Start expensive, fall back to cheaper:

```ruby
module LLM
  class CostOptimizedAgent < ApplicationAgent
    model "gpt-4o"               # Best quality
    fallback_models "gpt-4o-mini" # Cheaper fallback
  end
end
```

### Provider Diversity

Spread across providers for outage resilience:

```ruby
module LLM
  class MultiProviderAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "claude-3-5-sonnet", "gemini-2.0-flash"
    # OpenAI → Anthropic → Google
  end
end
```

### Quality Tiers

Progressively lower quality:

```ruby
module LLM
  class TieredAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "gpt-4o-mini", "gpt-3.5-turbo"
  end
end
```

### Speed Priority

Fastest models first:

```ruby
module LLM
  class SpeedFirstAgent < ApplicationAgent
    model "gemini-2.0-flash"
    fallback_models "gpt-4o-mini", "claude-3-haiku"
  end
end
```

## Global Fallback Configuration

Set fallbacks for all agents:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_fallback_models = ["gpt-4o-mini", "claude-3-haiku"]
end
```

Per-agent configuration overrides global:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "claude-3-5-sonnet"  # Overrides global
  end
end
```

## Model Compatibility Notes

When using fallbacks across providers, ensure your prompts work with all models:

### Schema Support

All fallback models should support your schema:

```ruby
module LLM
  class MyAgent < ApplicationAgent
    model "gpt-4o"
    fallback_models "claude-3-5-sonnet", "gemini-2.0-flash"
    # All three support JSON mode/structured output

    def schema
      @schema ||= RubyLLM::Schema.create do
        string :result
      end
    end
  end
end
```

### Prompt Compatibility

Avoid provider-specific prompt features:

```ruby
# Good: Universal prompt
def system_prompt
  "You are a helpful assistant."
end

# Potentially problematic: Provider-specific syntax
def system_prompt
  "<|im_start|>system..."  # OpenAI-specific
end
```

### Feature Differences

Be aware of capability differences:

| Feature | GPT-4o | Claude 3.5 | Gemini 2.0 |
|---------|--------|------------|------------|
| JSON mode | Yes | Yes | Yes |
| Vision | Yes | Yes | Yes |
| Function calling | Yes | Yes | Yes |
| Max tokens | 128K | 200K | 2M |

## Monitoring Fallback Usage

Track how often fallbacks are used:

```ruby
# Fallback rate this week
total = RubyLLM::Agents::Execution.this_week.count
fallbacks = RubyLLM::Agents::Execution
  .this_week
  .where("chosen_model_id != model_id")
  .count

fallback_rate = fallbacks.to_f / total
puts "Fallback rate: #{(fallback_rate * 100).round(1)}%"

# Breakdown by model
RubyLLM::Agents::Execution
  .this_week
  .where("chosen_model_id != model_id")
  .group(:model_id, :chosen_model_id)
  .count
# => { ["gpt-4o", "claude-3-5-sonnet"] => 45, ... }
```

## Alerting on High Fallback Usage

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    on_events: [:high_fallback_rate],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL'],
    fallback_rate_threshold: 0.1  # Alert if > 10%
  }
end
```

## Best Practices

### Order by Priority

```ruby
# First fallback should be the best alternative
fallback_models "best_alternative", "second_choice", "last_resort"
```

### Consider Cost

```ruby
# Know the cost implications
model "gpt-4o"           # $0.005/1K input
fallback_models "claude-3-opus"  # $0.015/1K input (more expensive!)

# Better: Fall back to cheaper
fallback_models "gpt-4o-mini"  # $0.00015/1K input
```

### Test All Fallbacks

```ruby
# In tests, verify each model works
["gpt-4o", "gpt-4o-mini", "claude-3-5-sonnet"].each do |model|
  result = LLM::MyAgent.call(query: "test", model: model)
  expect(result.success?).to be true
end
```

### Don't Over-Fallback

```ruby
# Good: 2-3 fallbacks
fallback_models "alternative1", "alternative2"

# Excessive: Too many
fallback_models "a", "b", "c", "d", "e", "f"
# Wastes time trying failed providers
```

## Related Pages

- [Reliability](Reliability) - Overview of reliability features
- [Automatic Retries](Automatic-Retries) - Retry configuration
- [Circuit Breakers](Circuit-Breakers) - Prevent cascading failures
- [Agent DSL](Agent-DSL) - Configuration reference
