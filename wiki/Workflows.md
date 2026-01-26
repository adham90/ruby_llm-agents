# Workflow Orchestration

Compose multiple agents into complex workflows with pipelines, parallel execution, and conditional routing.

## Overview

RubyLLM::Agents provides three workflow patterns, all defined using a class-based DSL:

| Pattern | Use Case | Base Class |
|---------|----------|------------|
| **Pipeline** | Sequential processing where each agent's output feeds the next | `Workflow::Pipeline` |
| **Parallel** | Run multiple agents concurrently and combine results | `Workflow::Parallel` |
| **Router** | Conditionally dispatch to different agents based on classification | `Workflow::Router` |

## Quick Examples

### Pipeline

Sequential execution with data flowing between steps:

```ruby
class LLM::ContentPipeline < RubyLLM::Agents::Workflow::Pipeline
  version "1.0"
  timeout 60.seconds
  max_cost 1.00

  step :extract,   agent: LLM::ExtractorAgent
  step :classify,  agent: LLM::ClassifierAgent
  step :format,    agent: LLM::FormatterAgent, optional: true
end

result = LLM::ContentPipeline.call(text: "raw content")
result.steps[:extract].content   # Individual step result
result.total_cost                # Sum of all steps
```

### Parallel

Concurrent execution with result aggregation:

```ruby
class LLM::ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  fail_fast false    # Continue even if a branch fails
  concurrency 3      # Max concurrent branches

  branch :sentiment, agent: LLM::SentimentAgent
  branch :entities,  agent: LLM::EntityAgent
  branch :summary,   agent: LLM::SummaryAgent
end

result = LLM::ReviewAnalyzer.call(text: "analyze this")
result.branches[:sentiment].content  # Individual branch result
result.content                       # Aggregated result hash
```

### Router

Conditional dispatch based on classification:

```ruby
class LLM::SupportRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"
  classifier_temperature 0.0

  route :billing,   to: LLM::BillingAgent,   description: "Billing, charges, refunds"
  route :technical, to: LLM::TechAgent,      description: "Bugs, errors, crashes"
  route :sales,     to: LLM::SalesAgent,     description: "Pricing, plans, upgrades"
  route :default,   to: LLM::GeneralAgent    # Fallback
end

result = LLM::SupportRouter.call(message: "I was charged twice")
result.routed_to         # :billing
result.classification    # Classification details
```

## Shared Configuration

All workflow types support these class-level options:

```ruby
class LLM::MyWorkflow < RubyLLM::Agents::Workflow::Pipeline
  version "2.0"           # Workflow version (default: "1.0")
  timeout 30.seconds      # Max duration for entire workflow
  max_cost 1.50           # Abort if cost exceeds this amount
end
```

## Result Object

Workflow results provide aggregate metrics:

```ruby
result = LLM::MyWorkflow.call(input: data)

# Aggregate metrics
result.total_cost       # Sum of all agent costs
result.total_tokens     # Sum of all tokens used
result.duration_ms      # Total execution time
result.status           # "success", "error", or "partial"

# Status helpers
result.success?         # true if all completed successfully
result.error?           # true if workflow failed
result.partial?         # true if some steps succeeded

# Pipeline-specific
result.steps            # Hash of step results
result.failed_steps     # Array of failed step names
result.skipped_steps    # Array of skipped step names

# Parallel-specific
result.branches         # Hash of branch results
result.failed_branches  # Array of failed branch names

# Router-specific
result.routed_to        # Selected route name
result.classification   # Classification details hash
```

## Execution Tracking

Workflows create parent-child execution records:

```ruby
# Parent execution (workflow)
execution = RubyLLM::Agents::Execution.last
execution.workflow_id    # => "550e8400-e29b-41d4-a716-446655440000"
execution.workflow_type  # => "ContentPipeline"

# Child executions (individual agents)
children = RubyLLM::Agents::Execution
  .where(parent_execution_id: execution.id)

children.each do |child|
  puts "#{child.workflow_step}: $#{child.total_cost}"
end
```

## Combining Patterns

Workflows can be composed by calling one workflow from another's agent:

```ruby
# Parallel analysis sub-workflow
class LLM::AnalysisWorkflow < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: LLM::SentimentAgent
  branch :topics,    agent: LLM::TopicAgent
end

# Agent that wraps the sub-workflow
class AnalysisAgent < ApplicationAgent
  param :text, required: true

  def call
    LLM::AnalysisWorkflow.call(text: text)
  end
end

# Main pipeline using the nested workflow
class LLM::MainPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :preprocess, agent: LLM::PreprocessorAgent
  step :analyze,    agent: AnalysisAgent    # Nested workflow
  step :summarize,  agent: LLM::SummaryAgent
end
```

## Hooks and Customization

Each workflow type provides hooks for customization:

### Pipeline Hooks

```ruby
class LLM::MyPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :extract, agent: LLM::ExtractorAgent
  step :process, agent: LLM::ProcessorAgent

  # Transform input before a specific step
  def before_process(context)
    { data: context[:extract].content, extra: "value" }
  end

  # Handle step failures
  def on_step_failure(step_name, error, context)
    :skip  # or :abort
  end
end
```

### Parallel Hooks

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :a, agent: LLM::AgentA
  branch :b, agent: LLM::AgentB

  # Custom result aggregation
  def aggregate(results)
    {
      combined: results[:a].content + results[:b].content,
      meta: { count: 2 }
    }
  end
end
```

### Router Hooks

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  route :fast, to: LLM::FastAgent, description: "Simple requests"
  route :slow, to: LLM::SlowAgent, description: "Complex requests"

  # Custom classification logic (bypasses LLM)
  def classify(input)
    input[:text].length > 100 ? :slow : :fast
  end

  # Transform input before routing
  def before_route(input, chosen_route)
    input.merge(priority: "high")
  end
end
```

## Detailed Guides

- **[Pipeline Workflows](Pipeline-Workflows)** - Sequential agent composition
- **[Parallel Workflows](Parallel-Workflows)** - Concurrent execution
- **[Router Workflows](Router-Workflows)** - Conditional dispatch

## Related Pages

- [Agent DSL](Agent-DSL) - Agent configuration
- [Execution Tracking](Execution-Tracking) - Monitoring workflows
- [Budget Controls](Budget-Controls) - Workflow cost limits
- [Examples](Examples) - Real-world workflow patterns
