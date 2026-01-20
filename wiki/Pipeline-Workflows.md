# Pipeline Workflows

Execute agents sequentially, passing each agent's output to the next.

## Defining a Pipeline

Create a pipeline by inheriting from `RubyLLM::Agents::Workflow::Pipeline`:

```ruby
class LLM::ContentPipeline < RubyLLM::Agents::Workflow::Pipeline
  version "1.0"
  timeout 60.seconds
  max_cost 1.00

  step :extract,  agent: LLM::ExtractorAgent
  step :classify, agent: LLM::ClassifierAgent
  step :format,   agent: LLM::FormatterAgent
end

result = LLM::ContentPipeline.call(text: "raw content")
```

## Data Flow

Each step receives the workflow input plus context from previous steps:

```
Input ──► ExtractorAgent ──► ClassifierAgent ──► FormatterAgent ──► Output
            │                    │                   │
            └─ :extract result ──┴─ :classify result ─┴─ final output
```

## Step Configuration

### Basic Step

```ruby
step :name, agent: AgentClass
```

### Optional Steps

Steps that can fail without aborting the pipeline:

```ruby
step :enrich, agent: LLM::EnricherAgent, optional: true
# Alias
step :enrich, agent: EnricherAgent, continue_on_error: true
```

### Conditional Steps

Skip steps based on runtime conditions:

```ruby
step :premium_check, agent: LLM::PremiumAgent, skip_on: ->(ctx) {
  ctx[:input][:user_tier] != "premium"
}
```

The `skip_on` proc receives the current context and returns `true` to skip.

## Input Transformation

### Using before_* Hooks

Transform input before a specific step:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :extract, agent: LLM::ExtractorAgent
  step :process, agent: LLM::ProcessorAgent
  step :format,  agent: LLM::FormatterAgent

  # Transform input for :process step
  def before_process(context)
    {
      data: context[:extract].content,
      metadata: context[:input][:metadata]
    }
  end

  # Transform input for :format step
  def before_format(context)
    {
      processed: context[:process].content,
      style: "markdown"
    }
  end
end
```

### Context Structure

The context hash contains:
- `:input` - Original workflow input
- `:<step_name>` - Result from each completed step

```ruby
def before_format(context)
  context[:input]    # Original input
  context[:extract]  # Result from :extract step
  context[:process]  # Result from :process step
end
```

## Error Handling

### Default: Abort on Error

By default, if a step fails, the pipeline aborts:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :step1, agent: LLM::Agent1
  step :step2, agent: LLM::Agent2  # If this fails, pipeline aborts
  step :step3, agent: LLM::Agent3  # Never reached
end

result = LLM::MyPipeline.call(input: data)
result.status  # => "error"
```

### Continue on Error

Mark steps as optional to continue after failures:

```ruby
step :optional_step, agent: LLM::OptionalAgent, optional: true
```

### Custom Error Handling

Override `on_step_failure` for custom logic:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :step1, agent: LLM::Agent1
  step :step2, agent: LLM::Agent2
  step :step3, agent: LLM::Agent3

  def on_step_failure(step_name, error, context)
    Rails.logger.error("Step #{step_name} failed: #{error.message}")
    notify_team(step_name, error)

    case step_name
    when :step2
      :skip  # Skip this step, continue to step3
    else
      :abort  # Abort the pipeline
    end
  end
end
```

Return values:
- `:skip` - Skip the failed step, continue with next
- `:abort` - Stop the pipeline (default behavior)

### Per-Step Error Handling

Handle errors for specific steps:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :risky, agent: LLM::RiskyAgent

  def on_risky_failure(error, context)
    # Return :skip or :abort
    :skip
  end
end
```

## Accessing Results

```ruby
result = LLM::MyPipeline.call(text: "input")

# Final output
result.content                 # Last step's output

# Individual step results
result.steps[:extract]         # Result object for :extract step
result.steps[:extract].content # Content from :extract
result.steps[:extract].total_cost

# Step status
result.all_steps_successful?   # Boolean
result.failed_steps            # [:step2] - Array of failed step names
result.skipped_steps           # [:step3] - Array of skipped step names

# Aggregate metrics
result.status                  # "success", "error", or "partial"
result.total_cost              # Sum of all step costs
result.total_tokens            # Sum of all step tokens
result.duration_ms             # Total execution time
```

## Pipeline Configuration

### Timeout

Set a timeout for the entire pipeline:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  timeout 60.seconds  # or timeout 60

  step :step1, agent: LLM::Agent1
  step :step2, agent: LLM::Agent2
end
```

### Max Cost

Abort if accumulated cost exceeds threshold:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  max_cost 1.00  # $1.00 maximum

  step :step1, agent: LLM::Agent1  # $0.30
  step :step2, agent: LLM::Agent2  # $0.40
  step :step3, agent: LLM::Agent3  # Would exceed $1.00, aborts
end
```

### Version

Track pipeline versions:

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  version "2.1"
end
```

## Real-World Example

### Document Processing Pipeline

```ruby
# Step 1: Extract text from document
module LLM
  class TextExtractorAgent < ApplicationAgent
    model "gpt-4o"
    param :document, required: true

    def user_prompt
      "Extract all text content from this document"
    end
  end
end

# Step 2: Classify the content
module LLM
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
end

# Step 3: Generate summary
module LLM
  class SummarizerAgent < ApplicationAgent
    model "gpt-4o"
    param :text, required: true
    param :category

    def user_prompt
      "Summarize this #{category}: #{text}"
    end
  end
end

# The pipeline
class LLM::DocumentPipeline < RubyLLM::Agents::Workflow::Pipeline
  version "1.0"
  timeout 120.seconds
  max_cost 0.50

  step :extract,   agent: LLM::TextExtractorAgent
  step :classify,  agent: LLM::ContentClassifierAgent
  step :summarize, agent: LLM::SummarizerAgent

  def before_classify(context)
    { text: context[:extract].content }
  end

  def before_summarize(context)
    {
      text: context[:extract].content,
      category: context[:classify].content[:category]
    }
  end
end

# Usage
result = LLM::DocumentPipeline.call(document: uploaded_file)

puts result.steps[:classify].content[:category]  # "report"
puts result.steps[:classify].content[:topics]    # ["finance", "quarterly"]
puts result.content                              # Summary text
```

## Inheritance

Pipelines support inheritance:

```ruby
class LLM::BasePipeline < RubyLLM::Agents::Workflow::Pipeline
  version "1.0"
  timeout 60.seconds

  step :validate, agent: LLM::ValidatorAgent
end

class LLM::ExtendedPipeline < LLM::BasePipeline
  # Inherits :validate step
  step :process, agent: LLM::ProcessorAgent
  step :format,  agent: LLM::FormatterAgent
end
```

## Best Practices

### Keep Pipelines Short

```ruby
# Good: 3-5 steps
class LLM::GoodPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :extract, agent: LLM::ExtractorAgent
  step :process, agent: LLM::ProcessorAgent
  step :format,  agent: LLM::FormatterAgent
end

# Consider breaking up long pipelines
```

### Use Appropriate Models

```ruby
# Classification: Fast, cheap model
module LLM
  class ClassifierAgent < ApplicationAgent
    model "gpt-4o-mini"
  end
end

# Generation: Better model
module LLM
  class GeneratorAgent < ApplicationAgent
    model "gpt-4o"
  end
end
```

### Handle Failures Gracefully

```ruby
class LLM::RobustPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :critical, agent: LLM::CriticalAgent
  step :enhance,  agent: LLM::EnhancerAgent, optional: true
  step :final,    agent: LLM::FinalAgent
end
```

### Monitor Performance

```ruby
result = LLM::MyPipeline.call(input: data)

result.steps.each do |name, step_result|
  if step_result.duration_ms > 5000
    Rails.logger.warn("Slow step: #{name} took #{step_result.duration_ms}ms")
  end
end
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Parallel Workflows](Parallel-Workflows) - Concurrent execution
- [Router Workflows](Router-Workflows) - Conditional dispatch
- [Examples](Examples) - More pipeline examples
