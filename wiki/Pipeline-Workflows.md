# Pipeline Workflows

Execute agents sequentially, passing each agent's output to the next.

## Basic Pipeline

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  ClassifierAgent,
  EnricherAgent,
  FormatterAgent
)

result = workflow.call(input: "raw text")
```

## Data Flow

Each step receives the previous step's output:

```
Input ──► ClassifierAgent ──► EnricherAgent ──► FormatterAgent ──► Output
            │                    │                   │
            └─ category ─────────┴─ enriched ────────┴─ formatted
```

## Input Transformation

Use `before_step` to transform data between steps:

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  ClassifierAgent,
  EnricherAgent,
  FormatterAgent,
  before_step: {
    EnricherAgent => ->(prev_result, context) {
      {
        text: context[:input],
        category: prev_result[:category]
      }
    },
    FormatterAgent => ->(prev_result, context) {
      {
        data: prev_result[:enriched_data],
        format: "markdown"
      }
    }
  }
)
```

## Step Configuration

### Optional Steps

Steps that can be skipped without failing:

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  RequiredAgent,
  { agent: OptionalEnricherAgent, optional: true },
  FinalAgent
)
```

### Conditional Steps

Skip steps based on conditions:

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  ClassifierAgent,
  {
    agent: PremiumEnricherAgent,
    skip_if: ->(prev_result, context) {
      context[:user_tier] != "premium"
    }
  },
  FormatterAgent
)

# Premium users get enrichment, others skip it
result = workflow.call(input: data, user_tier: "free")
```

## Error Handling

### Default: Abort on Error

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,  # If this fails, pipeline aborts
  Agent3   # Never reached
)
```

### Skip Failed Steps

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  Agent3,
  on_step_failure: :skip  # Continue with next step
)
```

### Provide Fallback Values

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  {
    agent: Agent2,
    on_failure: ->(error, context) {
      { fallback: true, default_value: "N/A" }
    }
  },
  Agent3
)
```

### Custom Error Handling

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  on_step_failure: ->(step, error, context) {
    Rails.logger.error("Step #{step} failed: #{error}")
    notify_team(step, error)

    case step
    when Agent2
      :skip  # Skip this step
    else
      :abort  # Abort pipeline
    end
  }
)
```

## Accessing Step Results

```ruby
result = workflow.call(input: data)

# Final output
result.content

# All step results
result.step_results.each do |step|
  puts "#{step[:agent]}: #{step[:duration_ms]}ms"
  puts "  Cost: $#{step[:cost]}"
  puts "  Output: #{step[:result]}"
end
```

## Context Passing

Pass context through all steps:

```ruby
result = workflow.call(
  input: data,
  user_id: 123,
  locale: "en",
  request_id: "abc123"
)

# Agents can access context
class MyAgent < ApplicationAgent
  param :input, required: true
  param :user_id
  param :locale

  def user_prompt
    "Process for user #{user_id} in #{locale}: #{input}"
  end
end
```

## Timeouts

### Pipeline Timeout

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  Agent3,
  timeout: 30  # Total pipeline timeout
)
```

### Per-Step Timeout

Individual agents have their own timeouts:

```ruby
class SlowAgent < ApplicationAgent
  timeout 60  # This step can take longer
end

class FastAgent < ApplicationAgent
  timeout 10  # This step should be quick
end
```

## Cost Control

### Max Pipeline Cost

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  Agent3,
  max_cost: 1.00  # Abort if cost exceeds $1
)
```

### Track Costs Per Step

```ruby
result = workflow.call(input: data)

result.step_results.each do |step|
  puts "#{step[:agent]}: $#{step[:cost]}"
end

puts "Total: $#{result.total_cost}"
```

## Real-World Example

### Content Processing Pipeline

```ruby
# Step 1: Extract text from document
class TextExtractorAgent < ApplicationAgent
  model "gpt-4o"
  param :document_url, required: true

  def user_prompt
    "Extract all text from this document"
  end
end

# Step 2: Classify content
class ContentClassifierAgent < ApplicationAgent
  model "gpt-4o-mini"
  param :text, required: true

  def user_prompt
    "Classify this content: #{text}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :category, enum: ["article", "report", "memo", "other"]
      array :topics, of: :string
    end
  end
end

# Step 3: Summarize
class SummarizerAgent < ApplicationAgent
  model "gpt-4o"
  param :text, required: true
  param :category

  def user_prompt
    "Summarize this #{category}: #{text}"
  end
end

# Pipeline
content_pipeline = RubyLLM::Agents::Workflow.pipeline(
  TextExtractorAgent,
  ContentClassifierAgent,
  SummarizerAgent,
  before_step: {
    ContentClassifierAgent => ->(prev, ctx) {
      { text: prev[:extracted_text] }
    },
    SummarizerAgent => ->(prev, ctx) {
      { text: ctx[:original_text], category: prev[:category] }
    }
  },
  timeout: 60,
  max_cost: 0.50
)

result = content_pipeline.call(document_url: "https://...")
```

## Best Practices

### Keep Pipelines Short

```ruby
# Good: 3-5 steps
pipeline(Agent1, Agent2, Agent3)

# Consider breaking up long pipelines
# Bad: 10+ steps
```

### Use Appropriate Models

```ruby
# Classification: Fast, cheap model
class ClassifierAgent < ApplicationAgent
  model "gpt-4o-mini"
end

# Generation: Better model
class GeneratorAgent < ApplicationAgent
  model "gpt-4o"
end
```

### Handle Failures Gracefully

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  CriticalAgent,
  { agent: OptionalEnricher, optional: true },
  FinalAgent
)
```

### Monitor Performance

```ruby
result = workflow.call(input: data)

# Log slow steps
result.step_results.each do |step|
  if step[:duration_ms] > 5000
    Rails.logger.warn("Slow step: #{step[:agent]}")
  end
end
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Parallel Workflows](Parallel-Workflows) - Concurrent execution
- [Router Workflows](Router-Workflows) - Conditional dispatch
- [Examples](Examples) - More pipeline examples
