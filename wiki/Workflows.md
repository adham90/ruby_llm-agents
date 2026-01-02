# Workflow Orchestration

Compose multiple agents into complex workflows with pipelines, parallel execution, and conditional routing.

## Overview

RubyLLM::Agents provides three workflow patterns:

| Pattern | Use Case |
|---------|----------|
| **Pipeline** | Sequential processing where each agent's output feeds the next |
| **Parallel** | Run multiple agents concurrently and combine results |
| **Router** | Conditionally dispatch to different agents based on classification |

## Quick Examples

### Pipeline

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  ClassifierAgent,
  EnricherAgent,
  FormatterAgent
)

result = workflow.call(input: "raw text")
```

### Parallel

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  entities: EntityAgent,
  summary: SummaryAgent
)

result = workflow.call(text: "analyze this")
# => { sentiment: {...}, entities: {...}, summary: {...} }
```

### Router

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent,
    "general" => GeneralAgent
  }
)

result = workflow.call(message: "I need help")
```

## Workflow Options

### Timeout

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  timeout: 60  # Maximum seconds for entire workflow
)
```

### Max Cost

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  max_cost: 1.00  # Abort if cost exceeds $1
)
```

### Versioning

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  version: "1.0"
)
```

## Result Object

Workflow results include:

```ruby
result = workflow.call(input: data)

result.content        # Combined output
result.total_cost     # Sum of all agent costs
result.total_tokens   # Sum of all tokens
result.duration_ms    # Total execution time
result.step_results   # Individual step results
```

## Execution Tracking

Workflows create parent-child execution records:

```ruby
# Parent execution
execution = RubyLLM::Agents::Execution.last
execution.workflow_id  # => "wf_abc123"

# Child executions
children = RubyLLM::Agents::Execution
  .where(parent_execution_id: execution.id)

children.each do |child|
  puts "#{child.agent_type}: #{child.total_cost}"
end
```

## Combining Patterns

Nest workflows for complex scenarios:

```ruby
# Analysis sub-workflow (parallel)
analysis = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  topics: TopicAgent
)

# Main pipeline
main = RubyLLM::Agents::Workflow.pipeline(
  PreprocessorAgent,
  analysis,  # Nested parallel workflow
  SummaryAgent
)

result = main.call(text: document)
```

## Error Handling

### Pipeline Errors

```ruby
workflow = RubyLLM::Agents::Workflow.pipeline(
  Agent1,
  Agent2,
  on_step_failure: :skip  # or :abort (default)
)
```

### Parallel Errors

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  a: AgentA,
  b: AgentB,
  fail_fast: true  # Abort all if one fails
)
```

### Router Fallback

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: { ... },
  default: GeneralAgent  # If no route matches
)
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
