# Workflows

This directory contains workflow orchestration classes that compose multiple agents. Workflows provide patterns for sequential, parallel, and conditional agent execution.

## Workflow Types

| Type | Class | Description |
|------|-------|-------------|
| **DSL Workflow** | `Workflow` | Declarative DSL for mixed sequential/parallel/routing |
| Pipeline | `Workflow::Pipeline` | Legacy: Sequential execution, data flows between steps |
| Parallel | `Workflow::Parallel` | Legacy: Concurrent execution with aggregation |
| Router | `Workflow::Router` | Legacy: Conditional dispatch based on classification |

## Declarative DSL Workflows (Recommended)

The new declarative DSL provides a clean, expressive syntax for defining workflows with minimal boilerplate. It supports sequential steps, parallel execution, conditional routing, and input validation all in one workflow class.

### Minimal Workflow

```ruby
module Workflows
  class SimpleWorkflow < RubyLLM::Agents::Workflow
    step :fetch, FetcherAgent
    step :process, ProcessorAgent
    step :save, SaverAgent
  end
end

# Usage
result = Workflows::SimpleWorkflow.call(order_id: "ORD-123")
result.success?          # => true
result.content           # => final step output
result.steps[:process]   # => ProcessorAgent result
```

### Full-Featured Workflow

```ruby
module Workflows
  class OrderWorkflow < RubyLLM::Agents::Workflow
    description "Process customer orders end-to-end"
    version "2.0"
    timeout 300
    max_cost 2.00

    # Input validation with defaults
    input do
      required :order_id, String
      required :user_id, Integer
      optional :priority, String, default: "normal"
      optional :expedited, :boolean, default: false
    end

    # Sequential steps
    step :fetch, FetcherAgent, timeout: 30
    step :validate, ValidatorAgent

    # Conditional routing based on previous step result
    step :process, on: -> { validate.tier } do |route|
      route.premium  PremiumProcessorAgent
      route.standard StandardProcessorAgent
      route.default  BasicProcessorAgent
    end

    # Parallel execution block
    parallel do
      step :analyze, AnalyzerAgent
      step :summarize, SummarizerAgent
      step :notify, NotifierAgent
    end

    # Conditional step execution
    step :expedite, ExpediteAgent, if: :expedited?

    private

    def expedited?
      input.expedited == true
    end
  end
end
```

### DSL Reference

#### Input Schema

Define required and optional inputs with type validation:

```ruby
input do
  required :order_id, String
  required :amount, Numeric
  optional :priority, String, default: "normal"
  optional :debug, :boolean, default: false

  # With enum validation
  optional :status, String, in: %w[pending active completed]
end
```

#### Step Options

```ruby
# Basic step
step :name, AgentClass

# With description
step :validate, ValidatorAgent, "Validates order data"

# With timeout (seconds)
step :fetch, FetcherAgent, timeout: 30

# Optional step (workflow continues on failure)
step :enrich, EnricherAgent, optional: true

# With default value on failure
step :lookup, LookupAgent, optional: true, default: { found: false }

# Conditional execution
step :notify, NotifierAgent, if: :should_notify?
step :skip_this, SkipAgent, unless: :condition_met?

# With retry
step :api_call, ApiAgent, retry: 3
step :api_call, ApiAgent, retry: { max: 3, delay: 2, backoff: :exponential }
```

#### Conditional Routing

Route to different agents based on a value:

```ruby
# Route based on lambda returning a value
step :process, on: -> { validate.tier } do |route|
  route.premium  PremiumAgent
  route.standard StandardAgent
  route.default  FallbackAgent  # Required fallback
end

# With custom input mapping per route
step :handle, on: -> { classify.type } do |route|
  route.billing  BillingAgent,  input: -> { { account: input.account_id } }
  route.support  SupportAgent,  input: -> { { ticket: input.ticket_id } }
  route.default  GeneralAgent
end
```

#### Parallel Execution

Execute steps concurrently:

```ruby
# Anonymous parallel group
parallel do
  step :sentiment, SentimentAgent
  step :keywords, KeywordAgent
  step :entities, EntityAgent
end

# Named parallel group with options
parallel :analysis, fail_fast: true, concurrency: 2 do
  step :deep_analyze, DeepAnalyzer
  step :quick_scan, QuickScanner
end
```

#### Lifecycle Hooks

```ruby
class MyWorkflow < RubyLLM::Agents::Workflow
  step :process, ProcessorAgent
  step :save, SaverAgent

  # Workflow-level hooks
  before_workflow { Rails.logger.info("Starting workflow") }
  after_workflow { Rails.logger.info("Workflow complete") }

  # Step-level hooks
  before_step(:process) { |context| log_step_start(:process) }
  after_step(:process) { |result, duration_ms| log_step_end(:process, duration_ms) }

  # Error hooks
  on_step_failure(:process) { |error, context| handle_error(error) }
end
```

#### Accessing Step Results

Within the workflow, access previous step results:

```ruby
step :validate, ValidatorAgent

# In routing lambda
step :process, on: -> { validate.tier } do |route|
  # validate.tier returns validate step's result[:tier]
end

# In condition methods
def should_notify?
  validate.valid? && input.callback_url.present?
end
```

### Workflow Result API

```ruby
result = MyWorkflow.call(order_id: "123")

# Status
result.success?    # All steps succeeded
result.partial?    # Some optional steps failed
result.error?      # Required step failed
result.status      # "success", "partial", or "error"

# Content
result.content     # Final step output

# Step results
result.steps                      # Hash of all step results
result.steps[:validate]           # Specific step result
result.steps[:validate].content   # Step output content

# Metrics
result.total_cost      # Combined cost of all steps
result.input_tokens    # Total input tokens
result.output_tokens   # Total output tokens
result.duration_ms     # Total workflow duration

# Errors
result.errors          # Hash of step errors
```

### Dry Run / Validation

Validate workflow configuration without executing:

```ruby
validation = MyWorkflow.dry_run(order_id: "123")

validation[:valid]         # true/false
validation[:input_errors]  # Array of validation errors
validation[:steps]         # List of step names
validation[:agents]        # List of agent classes
validation[:parallel_groups]  # Parallel group info
```

## Creating Workflows (Legacy Patterns)

### Pipeline (Sequential)

Execute agents in order, passing each step's output to the next:

```ruby
module Workflows
  class ContentPipeline < RubyLLM::Agents::Workflow::Pipeline
    version "1.0"
    timeout 120
    max_cost 0.50

    step :extract,  agent: ExtractorAgent
    step :validate, agent: ValidatorAgent
    step :format,   agent: FormatterAgent
  end
end
```

### Parallel (Concurrent)

Execute multiple agents simultaneously:

```ruby
module Workflows
  class ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
    version "1.0"

    branch :sentiment,  agent: SentimentAgent
    branch :summary,    agent: SummaryAgent
    branch :categories, agent: CategoryAgent

    def aggregate(results)
      {
        sentiment: results[:sentiment]&.content,
        summary: results[:summary]&.content,
        categories: results[:categories]&.content
      }
    end
  end
end
```

### Router (Conditional)

Route to different agents based on classification:

```ruby
module Workflows
  class SupportRouter < RubyLLM::Agents::Workflow::Router
    version "1.0"
    classifier ClassificationAgent

    route :billing,   agent: BillingAgent
    route :technical, agent: TechnicalAgent
    route :general,   agent: GeneralAgent

    default_route :general
  end
end
```

## DSL Reference

### Shared Options

```ruby
version "1.0"        # Version for tracking changes
timeout 120          # Total workflow timeout in seconds
max_cost 0.50        # Maximum allowed cost in USD
description "..."    # Human-readable description
```

### Pipeline DSL

```ruby
# Define steps
step :name, agent: AgentClass

# Conditional skipping
step :validate, agent: Validator, skip_on: ->(ctx) { ctx[:skip_validation] }

# Optional steps (failures won't stop pipeline)
step :enrich, agent: Enricher, optional: true

# Continue on error
step :notify, agent: Notifier, continue_on_error: true
```

### Parallel DSL

```ruby
# Define branches
branch :name, agent: AgentClass

# Optional branches
branch :extra, agent: ExtraAgent, optional: true

# Custom input transformation
branch :process, agent: Processor, input: ->(opts) { { text: opts[:content] } }

# Fail-fast (stop all on first required failure)
fail_fast true

# Limit concurrency
concurrency 3
```

### Router DSL

```ruby
# Set classifier
classifier ClassificationAgent

# Define routes
route :category, agent: AgentClass

# Default route
default_route :fallback

# Custom routing logic
def select_route(classification)
  case classification[:type]
  when "urgent" then :priority
  else :standard
  end
end
```

## Using Workflows

### Basic Execution

```ruby
result = Workflows::ContentPipeline.call(text: "raw input")

result.success?      # All steps succeeded
result.partial?      # Some steps succeeded
result.error?        # Workflow failed
result.content       # Final output
result.total_cost    # Combined cost
result.duration_ms   # Total duration
```

### Pipeline Results

```ruby
result = Workflows::ContentPipeline.call(text: "input")

result.steps                     # Hash of all step results
result.steps[:extract].content   # Specific step output
result.errors                    # Hash of step errors
```

### Parallel Results

```ruby
result = Workflows::ReviewAnalyzer.call(text: "Great product!")

result.branches                     # Hash of branch results
result.branches[:sentiment].content # Specific branch output
```

### Router Results

```ruby
result = Workflows::SupportRouter.call(question: "How do I pay?")

result.classification  # What route was selected
result.route          # Which agent handled it
result.content        # Response from routed agent
```

## Advanced Patterns

### Input Transformation

Transform data between pipeline steps:

```ruby
module Workflows
  class TransformPipeline < RubyLLM::Agents::Workflow::Pipeline
    step :analyze, agent: AnalyzerAgent
    step :enrich,  agent: EnricherAgent

    # Called before :enrich step
    def before_enrich(context)
      {
        data: context[:analyze].content,
        extra_field: "additional context"
      }
    end
  end
end
```

### Custom Aggregation

Combine parallel results:

```ruby
module Workflows
  class SafetyChecker < RubyLLM::Agents::Workflow::Parallel
    branch :toxicity, agent: ToxicityAgent
    branch :spam,     agent: SpamAgent
    branch :pii,      agent: PiiAgent

    def aggregate(results)
      {
        is_safe: results.values.none? { |r| r&.content == "flagged" },
        flags: results.select { |_, r| r&.content == "flagged" }.keys
      }
    end
  end
end
```

### Error Handling

Handle step failures:

```ruby
module Workflows
  class ResilientPipeline < RubyLLM::Agents::Workflow::Pipeline
    step :primary, agent: PrimaryAgent
    step :backup,  agent: BackupAgent, optional: true

    # Called when :primary fails
    def on_primary_failure(error, context)
      Rails.logger.warn("Primary failed: #{error.message}")
      :skip  # Continue to backup
      # :abort would stop the pipeline
    end
  end
end
```

### Cost Limits

Stop workflow if cost exceeds threshold:

```ruby
module Workflows
  class BudgetedWorkflow < RubyLLM::Agents::Workflow::Pipeline
    max_cost 1.00  # Stop if workflow exceeds $1.00

    step :expensive_analysis, agent: DeepAnalysisAgent
    step :synthesis,          agent: SynthesisAgent
  end
end
```

## Testing Workflows

```ruby
RSpec.describe Workflows::ContentPipeline do
  describe ".call" do
    it "processes content through all steps" do
      result = described_class.call(text: "test input")

      expect(result.success?).to be true
      expect(result.steps.keys).to eq([:extract, :validate, :format])
    end

    it "handles step failures" do
      allow(ExtractorAgent).to receive(:call).and_raise("Network error")

      result = described_class.call(text: "test")

      expect(result.error?).to be true
      expect(result.errors[:extract]).to be_present
    end
  end
end
```

## Best Practices

### General

1. **Version your workflows** - Track changes for debugging and rollback
2. **Set timeouts** - Prevent runaway workflows at both workflow and step level
3. **Use max_cost** - Control spending on expensive operations
4. **Handle errors gracefully** - Use optional steps, defaults, and error handlers
5. **Keep workflows focused** - One workflow, one purpose
6. **Test step interactions** - Unit test agents, integration test workflows

### DSL Workflows (Recommended)

1. **Use input schemas** - Validate inputs early with `required`/`optional` declarations
2. **Prefer DSL over legacy patterns** - The new DSL is more flexible and composable
3. **Use parallel for independent operations** - Group unrelated steps for concurrent execution
4. **Use routing for classification** - Clean syntax for conditional agent selection
5. **Leverage step result access** - Use `step_name.field` syntax in conditions/routing
6. **Add lifecycle hooks** - Log, track, and handle errors at appropriate points
7. **Use dry_run for validation** - Check workflow configuration before execution

### Legacy Patterns

1. **Use Pipeline for sequential data processing** - Data flows naturally between steps
2. **Use Parallel for fan-out operations** - Independent operations with aggregation
3. **Use Router for classification-based dispatch** - When route selection depends on LLM classification
