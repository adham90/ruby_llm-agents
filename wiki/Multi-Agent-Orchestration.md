# Multi-Agent Orchestration

Compose agents into workflows with sequential pipelines, parallel fan-out/fan-in, routing-based dispatch, and supervisor loops — all using a declarative DSL.

## Overview

`RubyLLM::Agents::Workflow` lets you compose multiple agents into a single callable unit. Each workflow step executes an agent through the full middleware pipeline (budget, cache, instrumentation, reliability), with automatic cost aggregation, execution tracking, and error handling.

**Key features:**

- **Sequential pipelines** — Step-by-step execution with data passing between steps
- **Parallel execution** — Fan-out to multiple agents concurrently, fan-in with dependencies
- **Dispatch routing** — Route to different agents based on a classification step
- **Supervisor loops** — Orchestrator agent delegates to sub-agents until done
- **Declarative DSL** — `step`, `flow`, `pass`, `dispatch`, `supervisor`, `delegate`
- **Automatic tracking** — Workflow executions appear in the dashboard with step breakdown
- **No new tables** — Uses existing `metadata` JSON column and `execution_type` field

## Quick Start

### Generate a Workflow

```bash
rails generate ruby_llm_agents:workflow Content --steps=research,draft,edit
```

This creates `app/agents/content_workflow.rb` and `app/agents/application_workflow.rb` (if not present).

### Define Steps

```ruby
class ContentWorkflow < ApplicationWorkflow
  description "Research, draft, and edit content"

  step :research, ResearchAgent
  step :draft,    DraftAgent,  after: :research
  step :edit,     EditAgent,   after: :draft

  flow :research >> :draft >> :edit

  pass :research, to: :draft, as: { notes: :content }
  pass :draft,    to: :edit,  as: { content: :content }
end
```

### Execute

```ruby
result = ContentWorkflow.call(topic: "AI safety")

result.success?          # => true
result.total_cost        # => 0.0082
result.total_tokens      # => 4500
result.duration_ms       # => 8500
result.step(:edit)       # => the edit agent's Result
result.step_names        # => [:research, :draft, :edit]
result.final_result      # => last step's Result
```

## DSL Reference

### `step`

Define a workflow step.

```ruby
step :name, AgentClass
step :name, AgentClass, params: { tone: "formal" }
step :name, AgentClass, after: :previous_step
step :name, AgentClass, after: [:step_a, :step_b]  # fan-in
step :name, AgentClass, if: -> (ctx) { ctx[:quality] == "high" }
step :name, AgentClass, unless: -> (ctx) { ctx[:skip_review] }
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | Symbol | Unique step identifier |
| `agent_class` | Class | Agent class to execute (must respond to `.call`) |
| `params` | Hash | Static parameters merged into the agent call |
| `after` | Symbol or Array | Dependencies — this step runs after the listed steps complete |
| `if` | Proc | Conditional — step runs only if proc returns truthy |
| `unless` | Proc | Conditional — step skips if proc returns truthy |

### `flow`

Declare sequential dependencies between steps. This is shorthand for setting `after:` on each step.

```ruby
# These are equivalent:
flow :research >> :draft >> :edit

flow [:research, :draft, :edit]
```

The `>>` operator on `Symbol` creates a `FlowChain` object that `flow` reads.

### `pass`

Map output from one step's result into input parameters for another step.

```ruby
pass :research, to: :draft, as: { notes: :content }
# The draft agent receives research's :content output as its :notes param
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `from_step` | Symbol | Source step name |
| `to:` | Symbol | Target step name |
| `as:` | Hash | Maps target param name => source output key |

### `description`

Set a human-readable description (shown in the dashboard).

```ruby
description "Content production pipeline"
```

### `on_failure`

Configure error handling strategy.

```ruby
on_failure :stop      # Stop on first error (default)
on_failure :continue  # Continue remaining steps despite errors
```

### `budget`

Set a maximum cost limit for the entire workflow.

```ruby
budget 1.00  # Stop if total cost exceeds $1.00
```

### `tenant`

Set tenant context for multi-tenancy tracking.

```ruby
tenant -> { Current.tenant }
```

## Sequential Pipelines

The simplest pattern — steps execute one after another.

```ruby
class ContentPipeline < ApplicationWorkflow
  description "Extract, classify, and format content"

  step :extract,  ExtractorAgent
  step :classify, ClassifierAgent, after: :extract
  step :format,   FormatterAgent,  after: :classify

  flow :extract >> :classify >> :format

  pass :extract,  to: :classify, as: { data: :content }
  pass :classify, to: :format,   as: { category: :route }
end

result = ContentPipeline.call(text: "Raw content here")
result.step(:classify).content  # => classification result
result.total_cost               # => sum of all steps
```

### How Data Flows

1. **Workflow params** — All params passed to `.call()` are available to every step
2. **Pass mappings** — Explicitly route output keys from one step to input params of another
3. **Context** — Steps can read the shared `WorkflowContext` for intermediate results

## Parallel Execution

Steps without dependencies (or within the same execution layer) run concurrently using threads.

```ruby
class ContentAnalyzer < ApplicationWorkflow
  description "Analyze content from multiple perspectives"

  # These three steps have no dependencies — they run in parallel
  step :sentiment, SentimentAgent
  step :keywords,  KeywordAgent
  step :summary,   SummaryAgent

  # This step depends on all three — it runs after they complete
  step :report, ReportAgent, after: [:sentiment, :keywords, :summary]
end

result = ContentAnalyzer.call(text: "Article content...")
result.step(:sentiment).content  # => sentiment analysis
result.step(:keywords).content   # => extracted keywords
result.step(:report).content     # => combined report
```

### How Parallel Execution Works

1. The `FlowGraph` builds a DAG from step dependencies
2. Kahn's topological sort produces **execution layers** — groups of steps that can run concurrently
3. Steps in the same layer execute via `Thread.new` (no external gem dependency)
4. The `WorkflowContext` is thread-safe (Mutex-protected writes)
5. Errors in one parallel step are collected but don't kill siblings
6. `duration_ms` reflects wall-clock time, not sum of steps

## Dispatch Routing

Route to different agents based on a classification step's result. Integrates with the existing `RubyLLM::Agents::Routing` concern.

```ruby
class SupportWorkflow < ApplicationWorkflow
  description "Route support tickets to specialists"

  step :classify, SupportRouter  # Agent with Routing concern

  dispatch :classify do |d|
    d.on :billing,   agent: BillingAgent
    d.on :technical, agent: TechAgent
    d.on :sales,     agent: SalesAgent
    d.on_default     agent: GeneralAgent
  end
end

result = SupportWorkflow.call(message: "I was charged twice")
result.step(:classify)  # => RoutingResult with route: :billing
result.step(:handler)   # => BillingAgent's Result
```

### Dispatch DSL

```ruby
dispatch :router_step_name, as: :custom_handler_name do |d|
  d.on :route_name, agent: AgentClass
  d.on :route_name, agent: AgentClass, params: { extra: "value" }
  d.on_default agent: FallbackAgent
end
```

- `:as` — Name for the dispatched handler step (default: `:handler`)
- `d.on` — Map a route to an agent class
- `d.on_default` — Fallback agent for unknown routes

## Supervisor Loop

An orchestrator agent loops, delegating to sub-agents until it calls `complete` or reaches `max_turns`.

```ruby
class ResearchWorkflow < ApplicationWorkflow
  description "Supervisor-driven research"

  supervisor OrchestratorAgent, max_turns: 10

  delegate :researcher, ResearchAgent
  delegate :writer,     WriterAgent
  delegate :reviewer,   ReviewAgent
end

result = ResearchWorkflow.call(topic: "Quantum computing")
```

### How It Works

1. The supervisor agent receives two injected tools: `DelegateTool` and `CompleteTool`
2. Each turn, the supervisor's LLM decides to either delegate to a sub-agent or complete
3. `DelegateTool` calls the named sub-agent through the full middleware pipeline
4. `CompleteTool` signals the loop is done and captures the final result
5. Results from all delegations are aggregated in the `WorkflowResult`

### Supervisor DSL

```ruby
supervisor AgentClass, max_turns: 10
```

- `AgentClass` — The orchestrator agent (receives delegate/complete tools)
- `max_turns:` — Maximum loop iterations (default: 10, prevents infinite loops)

```ruby
delegate :name, AgentClass
```

- `:name` — Name the supervisor uses to refer to this agent
- `AgentClass` — The sub-agent class to delegate work to

## WorkflowResult

`WorkflowResult` aggregates results from all steps.

### Content Access

```ruby
result.step(:name)       # => Agent Result for that step
result[:name]            # => Same as step(:name)
result.final_result      # => Last completed step's Result
result.content           # => final_result.content (convenience)
result.step_names        # => [:research, :draft, :edit]
result.step_count        # => 3
```

### Status

```ruby
result.success?              # => true (all steps succeeded)
result.error?                # => true (has errors)
result.partial?              # => true (some succeeded, some failed)
result.successful_step_count # => 2
result.failed_step_count     # => 1
```

### Cost Aggregation

```ruby
result.total_cost     # => Sum of all step costs
result.input_cost     # => Sum of input costs
result.output_cost    # => Sum of output costs
```

### Token Aggregation

```ruby
result.total_tokens   # => Sum of all tokens
result.input_tokens   # => Sum of input tokens
result.output_tokens  # => Sum of output tokens
```

### Timing

```ruby
result.duration_ms    # => Wall-clock time in milliseconds
result.started_at     # => Time
result.completed_at   # => Time
```

### Serialization

```ruby
result.to_h  # => Full hash representation for logging/debugging
```

## Execution Tracking

Workflow executions are automatically tracked in the database:

- **Parent execution** — One record per workflow call with `execution_type: "workflow"`
- **Child executions** — Each step creates its own execution linked via `parent_execution_id`
- **Metadata** — Step names, counts, success/failure breakdown stored in JSON `metadata` column
- **Dashboard** — Workflow executions appear in a dedicated "Workflows" tab with step breakdown

No new database columns or migrations are required.

## Error Handling

### Stop on First Error (Default)

```ruby
class StrictWorkflow < ApplicationWorkflow
  on_failure :stop

  step :validate, ValidatorAgent
  step :process,  ProcessorAgent, after: :validate
  # If validate fails, process never runs
end
```

### Continue Despite Errors

```ruby
class ResilientWorkflow < ApplicationWorkflow
  on_failure :continue

  step :primary,  PrimaryAgent
  step :fallback, FallbackAgent
  # Both run even if primary fails
end

result = ResilientWorkflow.call(input: "data")
result.partial?  # => true if some steps failed
```

### Conditional Steps

```ruby
step :review, ReviewAgent,
  after: :draft,
  if: -> (ctx) { ctx.step_result(:draft).content[:quality] < 0.8 }
```

## ApplicationWorkflow Base Class

The install generator creates `app/agents/application_workflow.rb`:

```ruby
class ApplicationWorkflow < RubyLLM::Agents::Workflow
  # Shared configuration for all workflows
  # on_failure :stop
end
```

All your workflows inherit from this, allowing shared configuration.

## Generator

```bash
# Basic workflow
rails generate ruby_llm_agents:workflow Content

# With steps
rails generate ruby_llm_agents:workflow Content --steps=research,draft,edit
```

The `--steps` option pre-populates the workflow with step declarations, `after:` dependencies, agent class references, and a `flow` declaration.

## Tips

- **Keep steps focused** — Each step should do one thing well
- **Use `pass` for explicit data flow** — Makes dependencies clear and testable
- **Prefer `flow` over manual `after:`** — More readable for sequential chains
- **Use `on_failure :continue`** for optional enrichment steps
- **Budget limits** catch runaway costs early in development
- **The dashboard** shows workflow step breakdown — use it for debugging

## Related Pages

- [Tools](Tools) — Agent-as-tool composition (LLM-driven orchestration)
- [Routing](Routing) — Classification concern used with dispatch
- [Execution Tracking](Execution-Tracking) — How executions are recorded
- [Dashboard](Dashboard) — Monitoring UI with workflow tab
- [Generators](Generators) — Scaffold workflows
- [Examples](Examples) — Real-world patterns
