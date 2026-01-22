# Refined Agent Declaration DSL

> **Goal:** Simplify and enhance the Action-Style DSL with cleaner syntax for the most common patterns while maintaining full flexibility for complex workflows.

## Background

This plan refines the Action-Style DSL from [02_action_style_dsl_improvements.md](./02_action_style_dsl_improvements.md). The key insight is that **90% of workflow steps just call an agent**, so we optimize for that case while providing escape hatches for complex logic.

## Design Principles

1. **Simple things simple** - One line for common cases
2. **Complex things possible** - Full Ruby power when needed
3. **Implicit flow** - Steps run in definition order (no separate `flow` declaration)
4. **Smart defaults** - Convention over configuration
5. **Readable at a glance** - Scan a workflow and understand it immediately

---

## Core Syntax

### Minimal Workflow

```ruby
class SimpleWorkflow < RubyLLM::Agents::Workflow
  step :fetch, FetcherAgent
  step :process, ProcessorAgent
  step :save, SaverAgent
end
```

That's it. No `flow` declaration needed. Steps execute in definition order.

### Full-Featured Workflow

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  description "Process customer orders end-to-end"

  input do
    required :order_id, String
    optional :priority, String, default: "normal"
    optional :callback_url, String
  end

  step :fetch, FetcherAgent, timeout: 1.minute

  step :validate, ValidatorAgent

  step :enrich, EnricherAgent,
       input: -> { { customer_id: validate.customer_id } },
       retry: 3, on: Timeout::Error

  step :process, on: -> { enrich.tier } do |route|
    route.premium  PremiumAgent
    route.standard StandardAgent
    route.default  DefaultAgent
  end

  parallel do
    step :analyze, AnalyzerAgent
    step :summarize, SummarizerAgent
  end

  step :store, StorageAgent,
       critical: true,
       fallback: BackupStorageAgent

  step :notify, NotifierAgent, if: :should_notify?

  private

  def should_notify?
    input.callback_url.present?
  end
end
```

---

## Step Parameter Reference

Complete reference of all parameters a step can accept:

```ruby
step :process, ProcessorAgent, "Human-readable description",

     # ─────────────────────────────────────────────────────────
     # INPUT
     # ─────────────────────────────────────────────────────────
     input: -> { { order: validate.order, user: input.user_id } },
     # OR
     pick: [:order_id, :status],           # Pick fields from previous step
     from: :validate,                       # Source step for pick (default: previous)

     # ─────────────────────────────────────────────────────────
     # CONDITIONS
     # ─────────────────────────────────────────────────────────
     if: :should_process?,                  # Symbol (predicate method)
     # OR
     if: -> { enrich.customer.active? },    # Lambda
     unless: :skip_processing?,             # Negative condition

     # ─────────────────────────────────────────────────────────
     # TIMING
     # ─────────────────────────────────────────────────────────
     timeout: 2.minutes,

     # ─────────────────────────────────────────────────────────
     # RETRY
     # ─────────────────────────────────────────────────────────
     retry: 3,                              # Simple count (retries on any error)
     # OR
     retry: 3, on: Timeout::Error,          # Retry only on specific error
     # OR
     retry: 3, on: [Timeout::Error, ApiError],  # Multiple error types
     # OR
     retry: {                               # Full config
       max: 3,
       on: [Timeout::Error, ApiError],
       backoff: :exponential,               # :none, :linear, :exponential
       delay: 1.second                      # Base delay
     },

     # ─────────────────────────────────────────────────────────
     # ERROR HANDLING
     # ─────────────────────────────────────────────────────────
     fallback: BackupAgent,                 # Single fallback
     # OR
     fallback: [BackupAgent, LastResortAgent],  # Fallback chain

     on_error: :handle_error,               # Error handler method
     # OR
     on_error: -> (e) { { error: e.message, status: :failed } },

     # ─────────────────────────────────────────────────────────
     # BEHAVIOR
     # ─────────────────────────────────────────────────────────
     critical: true,                        # Workflow fails if step fails (default)
     optional: true,                        # Workflow continues if step fails
     default: { status: :skipped },         # Default value when optional step fails

     # ─────────────────────────────────────────────────────────
     # METADATA
     # ─────────────────────────────────────────────────────────
     desc: "Process the validated order",   # Description (for tracing/debugging)
     tags: [:billing, :critical]            # Tags (for filtering/grouping)
```

### Routing Variant

When step routes to different agents based on a value:

```ruby
step :process,
     desc: "Route to appropriate processor",
     timeout: 2.minutes,
     critical: true,
     on: -> { enrich.customer.tier } do |route|
       route.premium  PremiumAgent,  input: -> { { vip: true } }
       route.standard StandardAgent
       route.basic    BasicAgent,    timeout: 5.minutes
       route.default  DefaultAgent
     end
```

### Block Variant

When step needs custom logic:

```ruby
step :process,
     desc: "Custom processing logic",
     timeout: 2.minutes,
     retry: 3, on: Timeout::Error,
     critical: true do

  skip! "Already processed" if already_done?
  fail! "Invalid state" if invalid?

  result = agent ProcessorAgent, order: validate.order

  # Transform result
  {
    processed: true,
    data: result.data,
    processed_at: Time.current
  }
end
```

### Quick Reference Table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `agent` | Class | (required)* | Agent class to execute |
| `desc` | String | nil | Human-readable description |
| `input` | Lambda | auto | Input data for agent |
| `pick` | Array | nil | Fields to pick from previous step |
| `from` | Symbol | previous | Source step for `pick` |
| `if` | Symbol/Lambda | nil | Execute only if truthy |
| `unless` | Symbol/Lambda | nil | Execute only if falsy |
| `timeout` | Duration | nil | Max execution time |
| `retry` | Integer/Hash | 0 | Retry configuration |
| `on` | Class/Array | StandardError | Error types to retry/route on |
| `fallback` | Class/Array | nil | Fallback agent(s) |
| `on_error` | Symbol/Lambda | nil | Error handler |
| `critical` | Boolean | true | Fail workflow on error |
| `optional` | Boolean | false | Continue workflow on error |
| `default` | Any | nil | Default value for optional steps |
| `tags` | Array | [] | Metadata tags |

*Agent is not required when using a block with custom logic.

### Usage Patterns

```ruby
# Minimal
step :validate, ValidatorAgent

# With timeout
step :fetch, FetcherAgent, timeout: 30.seconds

# With retry
step :api_call, ApiAgent, retry: 3, on: Timeout::Error

# Conditional
step :premium, PremiumAgent, if: :premium_customer?

# Optional with default
step :enrich, EnricherAgent, optional: true, default: {}

# Full options
step :process, ProcessorAgent, "Main processing",
     input: -> { { order: validate.order } },
     timeout: 2.minutes,
     retry: 3, on: [Timeout::Error, ApiError],
     fallback: BackupAgent,
     critical: true

# Routing
step :route, on: -> { classify.type } do |r|
  r.typeA AgentA
  r.typeB AgentB
  r.default DefaultAgent
end

# Custom block
step :custom do
  skip! "No data" if input.data.empty?
  agent CustomAgent, data: transform(input.data)
end
```

---

## Output Schema

Define the expected output structure and finalization logic:

```ruby
output do
  required :status, String, in: %w[success failed]
  required :order_id, String
  optional :tracking_number, String
  optional :error, String
end

def finalize
  { status: "success", order_id: input.order_id, tracking_number: store.tracking }
end

def on_failure(error, failed_step)
  { status: "failed", order_id: input.order_id, error: "#{failed_step}: #{error.message}" }
end
```

---

## Lifecycle Hooks

Workflow and step lifecycle hooks for cross-cutting concerns:

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  # Workflow-level hooks
  before_workflow :load_context
  after_workflow :cleanup
  around_workflow :with_transaction

  # Step-level hooks (all steps)
  before_step :log_start
  after_step :log_complete

  # Targeted step hooks
  before_step :process, :prepare_processing
  after_step :process, :cache_result

  # Error hooks
  on_step_failure :handle_failure
  on_step_failure :process, :handle_process_failure

  step :validate, ValidatorAgent
  step :process, ProcessorAgent

  private

  def load_context
    @order = Order.find(input.order_id)
  end

  def handle_failure(step_name, error, context)
    notify_admin(error)
    :skip  # or :abort, or return a Result
  end
end
```

---

## Result Object

The result object provides comprehensive information about workflow execution:

```ruby
result = OrderWorkflow.call(order_id: "ORD-123")

# Status
result.success?        # => true/false
result.error?          # => true/false
result.partial?        # => true/false (some optional steps failed)
result.status          # => "success", "partial", "error", "timeout"

# Content
result.content         # => { status: "success", order_id: "ORD-123", ... }

# Step Results
result.steps                    # => { validate: Result, process: Result, ... }
result.steps[:validate].content # => { valid: true, ... }

# Metrics (aggregated across all steps)
result.input_tokens    # => 1500
result.output_tokens   # => 800
result.total_tokens    # => 2300
result.total_cost      # => 0.0045
result.duration_ms     # => 2340

# Error Details
result.error_class     # => "Timeout::Error"
result.error_message   # => "Step :process timed out after 30s"
result.errors          # => { process: { class: "...", message: "..." } }

# Step Analysis
result.failed_steps    # => [:notify]
result.skipped_steps   # => [:enrich]
result.all_steps_successful?  # => false

# Workflow Metadata
result.workflow_id     # => "wf_abc123"
result.workflow_type   # => "pipeline"
result.started_at      # => Time
result.completed_at    # => Time
```

---

## Error Types

Structured error hierarchy for precise error handling:

```ruby
module RubyLLM::Agents
  class Error < StandardError; end

  # Workflow Errors
  class WorkflowError < Error; end
  class StepFailedError < WorkflowError; end
  class WorkflowHaltedError < WorkflowError; end
  class NoRouteError < WorkflowError; end

  # Validation Errors
  class InputValidationError < WorkflowError
    attr_reader :errors
  end
  class OutputValidationError < WorkflowError
    attr_reader :errors
  end

  # Execution Errors
  class WorkflowTimeoutError < WorkflowError
    attr_reader :step_name, :timeout
  end
  class WorkflowCostExceededError < WorkflowError
    attr_reader :accumulated_cost, :max_cost
  end

  # Retry Errors
  class RetryableError < Error; end
  class AllRetriesExhaustedError < WorkflowError; end
end

# Usage in workflows:
step :process do
  fail! "Invalid state"  # Raises StepFailedError
end

# Rescue specific errors:
begin
  result = MyWorkflow.call(order_id: "123")
rescue InputValidationError => e
  puts "Invalid input: #{e.errors.join(', ')}"
rescue WorkflowTimeoutError => e
  puts "Timed out at step :#{e.step_name}"
end
```

---

## Sub-Workflows

Compose workflows by using them as steps:

```ruby
# Sub-workflows are just workflows used as steps
class ShippingWorkflow < RubyLLM::Agents::Workflow
  step :calculate, ShippingCalculatorAgent
  step :reserve, ShippingReserveAgent
end

class OrderWorkflow < RubyLLM::Agents::Workflow
  step :validate, ValidatorAgent
  step :process, ProcessorAgent

  # Use workflow as a step (same syntax as agent)
  step :shipping, ShippingWorkflow,
       input: -> { { address: process.shipping_address, items: process.items } }

  step :finalize, FinalizerAgent,
       input: -> { { shipping: shipping.content } }
end

# Sub-workflow results are nested:
result = OrderWorkflow.call(order_id: "123")
result.steps[:shipping].steps[:calculate]  # => nested Result
result.steps[:shipping].content            # => final sub-workflow output

# Sub-workflows respect parent:
# - Timeout budget
# - Cost budget
# - Tracing/instrumentation
```

---

## Debugging & Tracing

Tools for understanding workflow execution:

```ruby
# Enable debug mode
class MyWorkflow < RubyLLM::Agents::Workflow
  debug_mode true  # Or: debug_mode Rails.env.development?
end

# Or per-call
result = MyWorkflow.call(order_id: "123", __debug: true)

# Execution Trace
result.trace
# => [
#   { step: :validate, status: :success, duration_ms: 45, agent: "ValidatorAgent" },
#   { step: :enrich, status: :skipped, reason: "cached", duration_ms: 1 },
#   { step: :process, status: :success, duration_ms: 230, agent: "ProcessorAgent" },
# ]

# Visual Timeline
puts result.timeline
# ┌─────────────────────────────────────────────────────────────────┐
# │ OrderWorkflow #wf_abc123 (276ms total)                          │
# ├─────────────────────────────────────────────────────────────────┤
# │ :validate    ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  45ms ✓        │
# │ :enrich      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   1ms ⊘ cached │
# │ :process     ░░░░████████████████████░░░░░░░░░░ 230ms ✓        │
# └─────────────────────────────────────────────────────────────────┘

# Dry Run (validate without executing)
result = MyWorkflow.dry_run(order_id: "123")
# => {
#   valid: true,
#   input_errors: [],
#   steps: [:validate, :enrich, :process],
#   agents: ["ValidatorAgent", "EnricherAgent", "ProcessorAgent"],
#   parallel_groups: [],
#   warnings: ["Step :notify has no agent defined"]
# }

# Debug Hooks
class MyWorkflow < RubyLLM::Agents::Workflow
  on_step_start do |step_name, input|
    Rails.logger.debug "[#{workflow_id}] Starting :#{step_name}"
  end

  on_step_complete do |step_name, result, duration_ms|
    Rails.logger.debug "[#{workflow_id}] Completed :#{step_name} in #{duration_ms}ms"
  end

  on_step_error do |step_name, error|
    Sentry.capture_exception(error, extra: { step: step_name, workflow_id: workflow_id })
  end
end
```

---

## Progress Tracking

Real-time progress tracking for displaying workflow status in your application:

### Progress Callbacks

```ruby
# Simple progress callback
result = MyWorkflow.call(
  order_id: "123",
  on_progress: ->(progress) {
    puts "[#{progress.percent}%] Step #{progress.step_index + 1}/#{progress.total_steps}: #{progress.step_name}"
  }
)

# Progress object properties
on_progress: ->(p) {
  p.workflow_id     # => "wf_abc123"
  p.step_name       # => :process
  p.step_index      # => 2 (0-based)
  p.total_steps     # => 5
  p.percent         # => 40
  p.status          # => :running, :completed, :failed, :skipped
  p.completed_steps # => [:validate, :enrich]
  p.pending_steps   # => [:notify, :finalize]
  p.current_agent   # => "ProcessorAgent"
  p.started_at      # => Time
  p.elapsed_ms      # => 1250
}
```

### Real-Time UI Updates (ActionCable/WebSocket)

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  # Broadcast progress to connected clients
  on_step_start do |step_name, input|
    broadcast_progress(
      step: step_name,
      status: :in_progress,
      message: "Processing #{step_name.to_s.humanize}..."
    )
  end

  on_step_complete do |step_name, result, duration_ms|
    broadcast_progress(
      step: step_name,
      status: :completed,
      duration_ms: duration_ms
    )
  end

  on_step_error do |step_name, error|
    broadcast_progress(
      step: step_name,
      status: :failed,
      error: error.message
    )
  end

  step :validate, ValidatorAgent
  step :process, ProcessorAgent
  step :notify, NotifierAgent

  private

  def broadcast_progress(data)
    ActionCable.server.broadcast(
      "workflow_#{workflow_id}",
      data.merge(
        workflow_id: workflow_id,
        progress: progress_info
      )
    )
  end

  def progress_info
    {
      completed: completed_steps.count,
      total: total_steps,
      percent: (completed_steps.count.to_f / total_steps * 100).round
    }
  end
end
```

### Async Execution with Progress Polling

```ruby
# Start workflow asynchronously
job = MyWorkflow.call_async(order_id: "123")

# Poll for progress
job.workflow_id     # => "wf_abc123"
job.status          # => :running, :completed, :failed
job.current_step    # => :process
job.progress        # => { completed: 2, total: 5, percent: 40 }
job.completed_steps # => [:validate, :enrich]
job.pending_steps   # => [:process, :notify, :finalize]
job.elapsed_ms      # => 2500

# Wait for completion
result = job.wait    # Blocks until done
result = job.wait(timeout: 30.seconds)  # With timeout

# Check if done
job.completed?      # => false
job.failed?         # => false

# Get result when done
job.result          # => Result object (nil if still running)
```

### Progress in Controllers/API

```ruby
# Rails controller example
class WorkflowsController < ApplicationController
  def create
    job = OrderWorkflow.call_async(order_id: params[:order_id])
    render json: { workflow_id: job.workflow_id }
  end

  def show
    job = WorkflowJob.find(params[:id])
    render json: {
      workflow_id: job.workflow_id,
      status: job.status,
      current_step: job.current_step,
      progress: job.progress,
      completed_steps: job.completed_steps,
      result: job.completed? ? job.result.content : nil
    }
  end
end

# Frontend polling
# GET /workflows/wf_abc123
# {
#   "workflow_id": "wf_abc123",
#   "status": "running",
#   "current_step": "process",
#   "progress": { "completed": 2, "total": 5, "percent": 40 },
#   "completed_steps": ["validate", "enrich"],
#   "result": null
# }
```

### Step Descriptions for UI

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  step :validate, ValidatorAgent,
       desc: "Validating order details",
       ui_label: "Validation"

  step :process, ProcessorAgent,
       desc: "Processing payment",
       ui_label: "Payment"

  step :shipping, ShippingAgent,
       desc: "Calculating shipping options",
       ui_label: "Shipping"

  step :notify, NotifierAgent,
       desc: "Sending confirmation email",
       ui_label: "Confirmation"
end

# Access step metadata for UI
OrderWorkflow.step_metadata
# => [
#   { name: :validate, ui_label: "Validation", desc: "Validating order details" },
#   { name: :process, ui_label: "Payment", desc: "Processing payment" },
#   { name: :shipping, ui_label: "Shipping", desc: "Calculating shipping options" },
#   { name: :notify, ui_label: "Confirmation", desc: "Sending confirmation email" }
# ]

# In progress callback
on_progress: ->(p) {
  step_info = OrderWorkflow.step_metadata[p.step_index]
  update_ui(
    label: step_info[:ui_label],
    description: step_info[:desc],
    percent: p.percent
  )
}
```

### Server-Sent Events (SSE) Streaming

```ruby
# Rails controller with SSE
class WorkflowsController < ApplicationController
  include ActionController::Live

  def stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    OrderWorkflow.call(
      order_id: params[:order_id],
      on_progress: ->(progress) {
        response.stream.write "data: #{progress.to_json}\n\n"
      }
    )

    response.stream.write "data: {\"status\": \"completed\"}\n\n"
  rescue => e
    response.stream.write "data: {\"status\": \"error\", \"message\": \"#{e.message}\"}\n\n"
  ensure
    response.stream.close
  end
end

# Frontend consumption
const eventSource = new EventSource('/workflows/stream?order_id=123');
eventSource.onmessage = (event) => {
  const progress = JSON.parse(event.data);
  updateProgressBar(progress.percent);
  updateCurrentStep(progress.step_name);
};
```

---

## Step Inspection & Execution History

Dashboard-friendly inspection of step inputs, outputs, and errors:

```ruby
# ═══════════════════════════════════════════════════════════════
# Per-Step Inspection (from Result object)
# ═══════════════════════════════════════════════════════════════

result = OrderWorkflow.call(order_id: "ORD-123")

# Access individual step details
step_result = result.steps[:process]

step_result.name           # => :process
step_result.status         # => :success, :failed, :skipped, :pending
step_result.input          # => { order: { id: "ORD-123", ... } }
step_result.output         # => { processed: true, tracking: "TRK-456" }
step_result.content        # => alias for output

# Error details (when step failed)
step_result.error          # => {
                           #      class: "Timeout::Error",
                           #      message: "Request timed out after 30s",
                           #      backtrace: ["app/agents/...", ...],
                           #      occurred_at: Time
                           #    }

# Step metrics
step_result.started_at     # => Time
step_result.completed_at   # => Time
step_result.duration_ms    # => 245
step_result.input_tokens   # => 150
step_result.output_tokens  # => 80
step_result.cost           # => 0.0012
step_result.retries        # => 2 (number of retry attempts)
step_result.agent_class    # => "ProcessorAgent"

# ═══════════════════════════════════════════════════════════════
# Execution History (Persistent Storage)
# ═══════════════════════════════════════════════════════════════

# Enable execution history
RubyLLM::Agents::Workflow.configure do |config|
  config.store_executions = true
  config.execution_store = :active_record  # or :redis, :custom
  config.execution_retention = 30.days
end

# Query past executions
execution = WorkflowExecution.find("wf_abc123")
execution = WorkflowExecution.find_by(order_id: "ORD-123")

# Execution metadata
execution.workflow_id      # => "wf_abc123"
execution.workflow_class   # => "OrderWorkflow"
execution.status           # => :completed, :failed, :running, :paused
execution.input            # => { order_id: "ORD-123", priority: "high" }
execution.output           # => { status: "success", ... }
execution.started_at       # => Time
execution.completed_at     # => Time
execution.duration_ms      # => 2450
execution.total_cost       # => 0.0089

# Iterate over steps
execution.steps.each do |step|
  step.name                # => :validate
  step.status              # => :success
  step.input               # => { order_id: "ORD-123" }
  step.output              # => { valid: true, customer_id: 456 }
  step.error               # => nil or { class: "...", message: "...", backtrace: [...] }
  step.started_at          # => Time
  step.completed_at        # => Time
  step.duration_ms         # => 45
  step.input_tokens        # => 120
  step.output_tokens       # => 60
  step.cost                # => 0.0008
  step.agent_class         # => "ValidatorAgent"
  step.retry_count         # => 0
end

# Filter executions
WorkflowExecution.where(workflow_class: "OrderWorkflow")
                 .where(status: :failed)
                 .where("started_at > ?", 1.day.ago)
                 .order(started_at: :desc)

# ═══════════════════════════════════════════════════════════════
# Dashboard API Example
# ═══════════════════════════════════════════════════════════════

class WorkflowExecutionsController < ApplicationController
  # GET /executions/:id
  def show
    execution = WorkflowExecution.find(params[:id])

    render json: {
      workflow_id: execution.workflow_id,
      workflow_class: execution.workflow_class,
      status: execution.status,
      input: execution.input,
      output: execution.output,
      started_at: execution.started_at,
      completed_at: execution.completed_at,
      duration_ms: execution.duration_ms,
      total_cost: execution.total_cost,
      steps: execution.steps.map do |step|
        {
          name: step.name,
          status: step.status,
          agent: step.agent_class,
          input: step.input,
          output: step.output,
          error: step.error,
          started_at: step.started_at,
          completed_at: step.completed_at,
          duration_ms: step.duration_ms,
          tokens: { input: step.input_tokens, output: step.output_tokens },
          cost: step.cost
        }
      end
    }
  end

  # GET /executions
  def index
    executions = WorkflowExecution
      .where(workflow_class: params[:workflow_class])
      .where(status: params[:status])
      .order(started_at: :desc)
      .page(params[:page])

    render json: executions.map { |e| execution_summary(e) }
  end
end

# ═══════════════════════════════════════════════════════════════
# Custom Execution Store
# ═══════════════════════════════════════════════════════════════

class CustomExecutionStore
  def save(execution)
    # Save to your preferred storage
  end

  def find(workflow_id)
    # Retrieve from storage
  end

  def update_step(workflow_id, step_name, data)
    # Update step in real-time
  end
end

RubyLLM::Agents::Workflow.configure do |config|
  config.execution_store = CustomExecutionStore.new
end
```

---

## Resumable Workflows

Resume failed or paused workflows from where they stopped:

```ruby
# ═══════════════════════════════════════════════════════════════
# Basic Resume
# ═══════════════════════════════════════════════════════════════

# Original execution fails at step :process
result = OrderWorkflow.call(order_id: "ORD-123")
result.status        # => :failed
result.failed_step   # => :process
result.resumable?    # => true
result.workflow_id   # => "wf_abc123"

# Resume from the failed step
resumed_result = OrderWorkflow.resume(result.workflow_id)
# OR
resumed_result = OrderWorkflow.resume(result)

# Resume skips completed steps, continues from :process
resumed_result.status           # => :success
resumed_result.resumed_from     # => :process
resumed_result.original_run_id  # => "wf_abc123"

# ═══════════════════════════════════════════════════════════════
# Resume with Modified Input
# ═══════════════════════════════════════════════════════════════

# Override input for the resumed step
resumed_result = OrderWorkflow.resume(
  result.workflow_id,
  step_input: { process: { retry_payment: true } }
)

# Or override workflow-level input
resumed_result = OrderWorkflow.resume(
  result.workflow_id,
  input: { order_id: "ORD-123", priority: "urgent" }
)

# ═══════════════════════════════════════════════════════════════
# Resume from Specific Step
# ═══════════════════════════════════════════════════════════════

# Re-run from a specific step (even if it succeeded)
resumed_result = OrderWorkflow.resume(
  result.workflow_id,
  from_step: :enrich  # Re-run :enrich and all subsequent steps
)

# Skip certain steps on resume
resumed_result = OrderWorkflow.resume(
  result.workflow_id,
  skip_steps: [:notify]  # Skip notification on retry
)

# ═══════════════════════════════════════════════════════════════
# Pause & Resume
# ═══════════════════════════════════════════════════════════════

class ApprovalWorkflow < RubyLLM::Agents::Workflow
  step :validate, ValidatorAgent
  step :analyze, AnalyzerAgent

  # Pause for human approval
  step :approval, wait_for: :human_approval

  step :execute, ExecutorAgent
  step :notify, NotifierAgent
end

# Workflow pauses at :approval step
result = ApprovalWorkflow.call(request_id: "REQ-123")
result.status       # => :paused
result.paused_at    # => :approval
result.resumable?   # => true

# Later, after human approval
resumed_result = ApprovalWorkflow.resume(
  result.workflow_id,
  approval_data: { approved: true, approver_id: 42 }
)

# ═══════════════════════════════════════════════════════════════
# Programmatic Pause
# ═══════════════════════════════════════════════════════════════

class LongRunningWorkflow < RubyLLM::Agents::Workflow
  step :fetch, FetcherAgent

  step :process do
    # Pause if processing will take too long
    pause! reason: "Large dataset requires batch processing" if large_dataset?

    agent ProcessorAgent, data: fetch.data
  end

  step :finalize, FinalizerAgent
end

# In controller - check for pause and handle
result = LongRunningWorkflow.call(dataset_id: "DS-123")

if result.paused?
  # Queue for background processing
  LongRunningWorkflowJob.perform_later(result.workflow_id)
end

# ═══════════════════════════════════════════════════════════════
# Checkpoint-Based Resume
# ═══════════════════════════════════════════════════════════════

class ExpensiveWorkflow < RubyLLM::Agents::Workflow
  # Auto-checkpoint after each step
  checkpoint_strategy :after_each_step

  # Or checkpoint at specific steps
  step :expensive_analysis, AnalysisAgent, checkpoint: true

  step :transform, TransformAgent
  step :load, LoadAgent, checkpoint: true
end

# Workflow automatically saves state after checkpointed steps
# If it fails, resume picks up from last checkpoint

# ═══════════════════════════════════════════════════════════════
# Resume Hooks
# ═══════════════════════════════════════════════════════════════

class OrderWorkflow < RubyLLM::Agents::Workflow
  # Called before resuming
  before_resume do |context|
    Rails.logger.info "Resuming workflow #{workflow_id} from #{context.resume_step}"
    # Reload any stale data
    @order = Order.find(input.order_id).reload
  end

  # Called after successful resume
  after_resume do |result|
    notify_admin("Workflow #{workflow_id} resumed successfully")
  end

  # Called when resume fails
  on_resume_failure do |error, context|
    notify_admin("Workflow #{workflow_id} resume failed: #{error.message}")
  end

  step :validate, ValidatorAgent
  step :process, ProcessorAgent
  step :notify, NotifierAgent
end

# ═══════════════════════════════════════════════════════════════
# Resume State Management
# ═══════════════════════════════════════════════════════════════

# Check if workflow can be resumed
execution = WorkflowExecution.find("wf_abc123")
execution.resumable?          # => true
execution.resume_point        # => :process
execution.completed_steps     # => [:validate, :enrich]
execution.pending_steps       # => [:process, :notify, :finalize]

# Resume reasons
execution.pause_reason        # => "Awaiting human approval"
execution.failure_reason      # => "Timeout::Error: Request timed out"

# Time-based expiry
execution.expires_at          # => Time (when resume is no longer allowed)
execution.expired?            # => false

# Configure resume expiry
RubyLLM::Agents::Workflow.configure do |config|
  config.resume_expiry = 7.days  # Workflows can be resumed within 7 days
end

# ═══════════════════════════════════════════════════════════════
# Dashboard Integration
# ═══════════════════════════════════════════════════════════════

class WorkflowExecutionsController < ApplicationController
  # POST /executions/:id/resume
  def resume
    execution = WorkflowExecution.find(params[:id])

    unless execution.resumable?
      return render json: { error: "Workflow cannot be resumed" }, status: 422
    end

    # Queue resume job
    ResumeWorkflowJob.perform_later(
      execution.workflow_id,
      step_input: params[:step_input],
      resumed_by: current_user.id
    )

    render json: { status: "resume_queued", workflow_id: execution.workflow_id }
  end
end
```

---

## Context & State Management

Managing state across steps:

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  step :validate, ValidatorAgent
  step :process, ProcessorAgent

  private

  # Instance variables persist across steps
  def load_order
    @order ||= Order.find(input.order_id)
  end

  # Available in steps via methods
  step :enrich do
    agent EnricherAgent, order: load_order, customer: load_order.customer
  end

  # Context hash for cross-step data
  step :calculate do
    context[:discount] = calculate_discount(load_order)
    agent CalculatorAgent, discount: context[:discount]
  end

  step :finalize do
    agent FinalizerAgent, discount: context[:discount]
  end
end

# Context is also available in hooks
before_step :process do
  context[:started_processing_at] = Time.current
end
```

---

## Configuration

Global and per-workflow configuration options:

```ruby
# Global configuration
RubyLLM::Agents::Workflow.configure do |config|
  # Defaults
  config.default_timeout = 30.seconds
  config.default_retry = 0

  # Limits
  config.max_cost = 1.0  # USD
  config.max_steps = 50

  # Logging
  config.logger = Rails.logger
  config.log_level = :debug

  # Instrumentation
  config.instrument = true
  config.on_complete = ->(result) { StatsD.timing("workflow", result.duration_ms) }
end

# Per-workflow overrides
class ExpensiveWorkflow < RubyLLM::Agents::Workflow
  max_cost 10.0
  timeout 5.minutes

  step :expensive, ExpensiveAgent
end

# Per-call overrides
MyWorkflow.call(
  order_id: "123",
  __timeout: 1.minute,
  __max_cost: 0.50
)
```

---

## Testing

Comprehensive testing patterns and helpers:

```ruby
RSpec.describe OrderWorkflow do
  include RubyLLM::Agents::WorkflowTestHelpers

  let(:valid_input) { { order_id: "ORD-123", user_id: 1 } }
  let(:workflow) { described_class.new(**valid_input) }

  # ─────────────────────────────────────────────────────────────
  # Input Validation
  # ─────────────────────────────────────────────────────────────

  describe "input validation" do
    it "requires order_id" do
      expect { described_class.new(user_id: 1) }
        .to raise_error(InputValidationError, /order_id is required/)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Individual Step Tests
  # ─────────────────────────────────────────────────────────────

  describe "step :validate" do
    it "calls ValidatorAgent" do
      stub_agent(ValidatorAgent).to_return(valid: true)

      result = workflow.run_step(:validate)

      expect(result.content[:valid]).to be true
    end
  end

  describe "step :process" do
    before do
      stub_results(workflow,
        validate: { valid: true },
        enrich: { customer: { tier: "premium" } }
      )
    end

    it "routes premium to PremiumAgent" do
      expect(PremiumAgent).to receive(:call)
      workflow.run_step(:process)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Predicate Tests
  # ─────────────────────────────────────────────────────────────

  describe "#premium_customer?" do
    it "returns true for premium tier" do
      stub_results(workflow, enrich: { customer: { tier: "premium" } })
      expect(workflow.send(:premium_customer?)).to be true
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Full Workflow Tests
  # ─────────────────────────────────────────────────────────────

  describe "full workflow" do
    before { stub_all_agents(workflow) }

    it "executes all steps" do
      result = workflow.call

      expect(result).to be_success
      expect(result.steps.keys).to eq([:validate, :enrich, :process, :notify])
    end

    it "handles errors gracefully" do
      stub_agent(ProcessorAgent).to_raise(Timeout::Error)

      result = workflow.call

      expect(result).to be_error
      expect(result.failed_steps).to eq([:process])
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Partial Execution
  # ─────────────────────────────────────────────────────────────

  describe "partial execution" do
    it "runs until specified step" do
      stub_all_agents(workflow)

      result = workflow.call(__until: :enrich)

      expect(result.steps.keys).to eq([:validate, :enrich])
    end
  end
end

# ═══════════════════════════════════════════════════════════════
# Test Helpers
# ═══════════════════════════════════════════════════════════════

module RubyLLM::Agents::WorkflowTestHelpers
  # Stub prior results for isolated testing
  def stub_results(workflow, results_hash)
    # ...
  end

  # Stub an agent to return specific content
  def stub_agent(agent_class)
    AgentStub.new(agent_class)
  end

  # Stub all agents in workflow
  def stub_all_agents(workflow, default: {})
    # ...
  end

  # Run single step with context
  def run_step(workflow, step_name, context: {})
    # ...
  end

  # Create mock result
  def mock_result(content, success: true)
    # ...
  end
end
```

---

## Feature Reference

### 1. Basic Step Declaration

```ruby
# Minimal - just agent
step :name, AgentClass

# With description
step :name, AgentClass, "Human-readable description"

# With timeout
step :name, AgentClass, timeout: 30.seconds

# With multiple options
step :name, AgentClass,
     timeout: 30.seconds,
     optional: true
```

**Implementation:**

```ruby
class_methods do
  def step(name, agent = nil, desc = nil, **options, &block)
    @steps ||= []
    @step_configs ||= {}

    config = StepConfig.new(
      name: name,
      agent: agent,
      description: desc.is_a?(String) ? desc : nil,
      options: desc.is_a?(Hash) ? desc.merge(options) : options,
      block: block
    )

    @steps << name
    @step_configs[name] = config
  end

  def steps
    @steps || []
  end

  def step_configs
    @step_configs || {}
  end
end
```

---

### 2. Input Mapping

Steps need data from previous steps or original input.

```ruby
# Auto-forward: step receives previous step's output + original input
step :process, ProcessorAgent

# Explicit input mapping with lambda
step :enrich, EnricherAgent,
     input: -> { { customer_id: validate.customer_id } }

# Pick specific fields from previous step
step :notify, NotifierAgent,
     pick: [:order_id, :status]

# Pick from specific step
step :notify, NotifierAgent,
     from: :process, pick: [:order_id, :status]

# Merge multiple sources
step :final, FinalAgent,
     input: -> {
       {
         order: validate.order,
         customer: enrich.customer,
         analysis: analyze.result,
         priority: input.priority
       }
     }
```

**Implementation:**

```ruby
class StepConfig
  def resolve_input(workflow)
    case
    when options[:input]
      workflow.instance_exec(&options[:input])
    when options[:pick]
      source = options[:from] ? workflow.send(options[:from]) : workflow.previous_result
      source.to_h.slice(*options[:pick])
    else
      # Default: merge original input with previous step output
      workflow.input.to_h.merge(workflow.previous_result&.to_h || {})
    end
  end
end
```

---

### 3. Conditional Execution

```ruby
# Predicate method (recommended)
step :premium, PremiumAgent, if: :premium_customer?
step :standard, StandardAgent, unless: :premium_customer?

# Lambda
step :notify, NotifierAgent, if: -> { input.callback_url.present? }

# Multiple conditions (all must pass)
step :express, ExpressAgent,
     if: :rush_order?,
     unless: :international?
```

**Predicate methods are cleaner and testable:**

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  step :premium, PremiumAgent, if: :premium_customer?
  step :notify, NotifierAgent, if: :should_notify?

  private

  def premium_customer?
    enrich.customer.tier == "premium"
  end

  def should_notify?
    input.callback_url.present? && process.success?
  end
end

# In tests:
RSpec.describe OrderWorkflow do
  describe "#premium_customer?" do
    it "returns true for premium tier" do
      stub_results(workflow, enrich: { customer: { tier: "premium" } })
      expect(workflow.send(:premium_customer?)).to be true
    end
  end
end
```

**Implementation:**

```ruby
class StepExecutor
  def should_execute?(workflow, config)
    if_cond = config.options[:if]
    unless_cond = config.options[:unless]

    passes_if = if_cond.nil? || evaluate_condition(workflow, if_cond)
    passes_unless = unless_cond.nil? || !evaluate_condition(workflow, unless_cond)

    passes_if && passes_unless
  end

  def evaluate_condition(workflow, condition)
    case condition
    when Symbol then workflow.send(condition)
    when Proc then workflow.instance_exec(&condition)
    else condition
    end
  end
end
```

---

### 4. Routing / Branching

When a step should use different agents based on a value:

```ruby
# Route based on a value
step :process, on: -> { enrich.tier } do |route|
  route.premium  PremiumAgent
  route.standard StandardAgent
  route.basic    BasicAgent
  route.default  DefaultAgent  # fallback
end

# Shorthand for simple cases
step :process, route: -> { enrich.tier }, to: {
  premium:  PremiumAgent,
  standard: StandardAgent,
  _default: DefaultAgent
}

# Route with custom input per branch
step :process, on: -> { enrich.tier } do |route|
  route.premium  PremiumAgent,  input: -> { { vip: true, **enrich.to_h } }
  route.standard StandardAgent, input: -> { enrich.to_h }
  route.default  DefaultAgent
end
```

**Implementation:**

```ruby
class RouteBuilder
  def initialize
    @routes = {}
    @default = nil
  end

  def method_missing(name, agent = nil, **options)
    if name == :default
      @default = { agent: agent, options: options }
    else
      @routes[name.to_sym] = { agent: agent, options: options }
    end
  end

  def resolve(value)
    key = value.to_sym
    @routes[key] || @default || raise(NoRouteError, "No route for: #{value}")
  end
end

class StepConfig
  def routing?
    options[:on].present? && block.present?
  end

  def resolve_route(workflow)
    value = workflow.instance_exec(&options[:on])
    builder = RouteBuilder.new
    block.call(builder)
    builder.resolve(value)
  end
end
```

---

### 5. Parallel Execution

Group steps that can run concurrently:

```ruby
class AnalysisWorkflow < RubyLLM::Agents::Workflow
  step :fetch, FetcherAgent

  parallel do
    step :sentiment, SentimentAgent
    step :keywords, KeywordAgent
    step :entities, EntityAgent
  end

  step :combine, CombinerAgent,
       input: -> {
         {
           sentiment: sentiment.result,
           keywords: keywords.result,
           entities: entities.result
         }
       }
end
```

**Named parallel groups (for complex workflows):**

```ruby
parallel :analysis do
  step :sentiment, SentimentAgent
  step :keywords, KeywordAgent
end

parallel :enrichment do
  step :customer, CustomerAgent
  step :inventory, InventoryAgent
end

# Access via group name
step :final, FinalAgent,
     input: -> { { analysis: analysis, enrichment: enrichment } }
```

**Implementation:**

```ruby
class_methods do
  def parallel(name = nil, &block)
    @steps ||= []
    @parallel_groups ||= []

    # Capture steps defined in block
    previous_steps = @steps.dup
    instance_eval(&block)
    parallel_steps = @steps - previous_steps

    # Replace individual steps with parallel group
    @steps = previous_steps
    group = ParallelGroup.new(name: name, steps: parallel_steps)
    @steps << group
    @parallel_groups << group
  end
end

class ParallelGroup
  attr_reader :name, :steps

  def initialize(name:, steps:)
    @name = name
    @steps = steps
  end
end
```

---

### 6. Retry & Error Handling

```ruby
# Simple retry count
step :fetch, FetcherAgent, retry: 3

# Retry with specific errors
step :fetch, FetcherAgent,
     retry: 3, on: Timeout::Error

# Retry with multiple errors
step :fetch, FetcherAgent,
     retry: 3, on: [Timeout::Error, ConnectionError]

# Retry with backoff
step :fetch, FetcherAgent,
     retry: { max: 3, backoff: :exponential, on: Timeout::Error }

# Fallback agent
step :process, ProcessorAgent,
     fallback: BackupAgent

# Fallback chain
step :process, ProcessorAgent,
     fallback: [BackupAgent, LastResortAgent]

# Custom error handler
step :process, ProcessorAgent,
     on_error: :handle_process_error

step :process, ProcessorAgent,
     on_error: -> (error) { { status: :degraded, error: error.message } }
```

**Implementation:**

```ruby
class StepExecutor
  def execute_with_retry(workflow, config)
    retry_config = normalize_retry_config(config.options)
    attempts = 0
    max_attempts = retry_config[:max] || 1

    begin
      attempts += 1
      execute_agent(workflow, config)
    rescue *retry_config[:on] => e
      if attempts < max_attempts
        sleep calculate_backoff(retry_config, attempts)
        retry
      elsif config.options[:fallback]
        execute_fallback_chain(workflow, config, e)
      elsif config.options[:on_error]
        execute_error_handler(workflow, config, e)
      else
        raise
      end
    end
  end

  def normalize_retry_config(options)
    case options[:retry]
    when Integer
      { max: options[:retry], on: [StandardError], backoff: :none }
    when Hash
      { max: 3, on: [StandardError], backoff: :none }.merge(options[:retry])
    else
      { max: 1, on: [StandardError], backoff: :none }
    end.tap do |config|
      config[:on] = Array(options[:on]) if options[:on]
    end
  end

  def calculate_backoff(config, attempt)
    base = config[:delay] || 1
    case config[:backoff]
    when :exponential then base * (2 ** (attempt - 1))
    when :linear then base * attempt
    else base
    end
  end
end
```

---

### 7. Step Behaviors

```ruby
# Critical: workflow fails if this fails (default behavior)
step :validate, ValidatorAgent, critical: true

# Optional: workflow continues if this fails
step :enrich, EnricherAgent, optional: true

# Optional with default value on failure
step :enrich, EnricherAgent,
     optional: true,
     default: { customer: nil }

# Timeout
step :slow_step, SlowAgent, timeout: 5.minutes

# Description (for debugging/tracing)
step :process, ProcessorAgent, desc: "Main order processing"
```

---

### 8. Custom Logic with Blocks

When you need more than just calling an agent:

```ruby
# Block with custom logic
step :notify do
  skip! "No callback URL" unless input.callback_url.present?

  agent NotifierAgent,
        url: input.callback_url,
        payload: build_payload
end

# Block that transforms agent output
step :process, ProcessorAgent do |result|
  # result is the agent's return value
  # return value becomes step result
  {
    processed: true,
    data: result.data.transform_keys(&:to_sym),
    processed_at: Time.current
  }
end

# Block with before/after logic
step :important, ImportantAgent do
  before { Rails.logger.info "Starting important step" }
  after { |result| cache_result(result) }
end
```

**Agent Call Syntax:**

Inside blocks, use the `agent` helper to invoke agents:

```ruby
# Inside blocks, use the `agent` helper:
step :process do
  result = agent ProcessorAgent, order: validate.order
  # `agent` returns the Result object

  # Transform and return
  { processed: true, data: result.content }
end

# The `agent` helper:
# - Instantiates the agent with given params
# - Calls it and returns the Result
# - Tracks metrics for aggregation
# - Respects workflow timeout/budget

# You can also call agents conditionally:
step :route do
  case enrich.tier
  when "premium"
    agent PremiumAgent, data: enrich
  when "standard"
    agent StandardAgent, data: enrich
  else
    agent DefaultAgent, data: enrich
  end
end
```

**Implementation:**

```ruby
class StepConfig
  def execute(workflow)
    if block && agent.nil?
      # Pure block step
      workflow.instance_exec(&block)
    elsif block && agent
      # Agent with transform block
      result = execute_agent(workflow)
      workflow.instance_exec(result, &block)
    else
      # Simple agent step
      execute_agent(workflow)
    end
  end
end
```

---

### 9. Step Control Methods

Available inside steps and blocks:

```ruby
step :enrich do
  # Skip this step (continues to next)
  skip! "Reason" if some_condition?

  # Skip with default value
  skip! default: { customer: nil } if cached?

  # Halt workflow (success, stops here)
  halt! status: :complete if already_done?

  # Fail workflow (error)
  fail! "Cannot proceed" if invalid_state?

  # Retry this step
  retry! if transient_error?

  agent EnricherAgent
end
```

**Implementation:**

```ruby
class Workflow
  private

  def skip!(reason = nil, default: nil)
    throw :skip_step, { skipped: true, reason: reason, default: default }
  end

  def halt!(result = {})
    throw :halt_workflow, { halted: true, result: result }
  end

  def fail!(message)
    raise StepFailedError, message
  end

  def retry!(reason = nil)
    raise RetryStep, reason
  end
end
```

---

### 10. Sections (Visual Organization)

For large workflows, group steps visually:

```ruby
class LargeWorkflow < RubyLLM::Agents::Workflow
  # ═══════════════════════════════════════════════════════════
  # VALIDATION
  # ═══════════════════════════════════════════════════════════

  step :fetch, FetcherAgent
  step :validate, ValidatorAgent

  # ═══════════════════════════════════════════════════════════
  # PROCESSING
  # ═══════════════════════════════════════════════════════════

  step :enrich, EnricherAgent
  step :process, ProcessorAgent, critical: true

  # ═══════════════════════════════════════════════════════════
  # COMPLETION
  # ═══════════════════════════════════════════════════════════

  step :store, StorageAgent
  step :notify, NotifierAgent, optional: true
end
```

**Or with DSL:**

```ruby
class LargeWorkflow < RubyLLM::Agents::Workflow
  section "Validation" do
    step :fetch, FetcherAgent
    step :validate, ValidatorAgent
  end

  section "Processing" do
    step :enrich, EnricherAgent
    step :process, ProcessorAgent, critical: true
  end

  section "Completion" do
    step :store, StorageAgent
    step :notify, NotifierAgent, optional: true
  end
end
```

---

## Complete Examples

### Example 1: Simple CRUD Workflow

```ruby
class CreateUserWorkflow < RubyLLM::Agents::Workflow
  input do
    required :email, String
    required :name, String
    optional :role, String, default: "user"
  end

  step :validate, UserValidatorAgent
  step :create, UserCreatorAgent
  step :notify, WelcomeEmailAgent, optional: true
end
```

### Example 2: E-commerce Order Processing

```ruby
class OrderProcessingWorkflow < RubyLLM::Agents::Workflow
  description "Process e-commerce orders from validation to fulfillment"

  input do
    required :order_id, String
    required :user_id, Integer
    optional :expedited, Boolean, default: false
  end

  # ═══════════════════════════════════════════════════════════
  # VALIDATION
  # ═══════════════════════════════════════════════════════════

  step :fetch_order, OrderFetcherAgent,
       timeout: 30.seconds

  step :validate_inventory, InventoryValidatorAgent,
       input: -> { { items: fetch_order.items } },
       on_error: -> (e) { fail! "Inventory check failed: #{e.message}" }

  step :validate_payment, PaymentValidatorAgent,
       input: -> { { amount: fetch_order.total, user_id: input.user_id } }

  # ═══════════════════════════════════════════════════════════
  # PROCESSING
  # ═══════════════════════════════════════════════════════════

  step :calculate_shipping, on: -> { input.expedited } do |route|
    route.true   ExpressShippingAgent
    route.false  StandardShippingAgent
    route.default StandardShippingAgent
  end

  step :process_payment, PaymentProcessorAgent,
       input: -> { { order: fetch_order, shipping: calculate_shipping } },
       retry: 3, on: PaymentGatewayError,
       critical: true

  parallel do
    step :reserve_inventory, InventoryReserveAgent
    step :create_shipping_label, ShippingLabelAgent
  end

  # ═══════════════════════════════════════════════════════════
  # COMPLETION
  # ═══════════════════════════════════════════════════════════

  step :finalize_order, OrderFinalizerAgent,
       input: -> {
         {
           order: fetch_order,
           payment: process_payment,
           inventory: reserve_inventory,
           shipping: create_shipping_label
         }
       }

  step :send_confirmation, ConfirmationEmailAgent,
       optional: true,
       input: -> { { email: fetch_order.customer_email, order: finalize_order } }

  step :notify_warehouse, WarehouseNotifierAgent,
       optional: true
end
```

### Example 3: Document Analysis Pipeline

```ruby
class DocumentAnalysisWorkflow < RubyLLM::Agents::Workflow
  description "Analyze documents for content extraction and classification"

  input do
    required :document_url, String
    optional :analysis_depth, String, default: "standard", in: %w[quick standard deep]
  end

  step :fetch, DocumentFetcherAgent,
       timeout: 2.minutes,
       retry: 3, on: [Timeout::Error, FetchError]

  step :validate do
    content = fetch.content
    fail! "Document too large" if content.bytesize > 50.megabytes
    fail! "Empty document" if content.bytesize.zero?

    { size: content.bytesize, type: detect_type(content) }
  end

  step :classify, ClassifierAgent,
       input: -> { { content: fetch.content, metadata: validate } }

  # Parallel analysis
  parallel :analysis do
    step :extract, ExtractionAgent,
         input: -> { { content: fetch.content, schema: classify.schema } }

    step :summarize, on: -> { input.analysis_depth } do |route|
      route.quick    QuickSummaryAgent
      route.standard StandardSummaryAgent
      route.deep     DeepSummaryAgent
    end

    step :entities, EntityExtractionAgent, optional: true
  end

  step :compile, ResultCompilerAgent,
       input: -> { analysis.to_h }

  step :store, StorageAgent,
       fallback: BackupStorageAgent

  private

  def detect_type(content)
    MimeMagic.by_magic(content)&.type || "application/octet-stream"
  end
end
```

### Example 4: Multi-Stage Approval Workflow

```ruby
class ApprovalWorkflow < RubyLLM::Agents::Workflow
  description "Multi-stage document approval process"

  input do
    required :document_id, String
    required :submitter_id, Integer
    optional :fast_track, Boolean, default: false
  end

  step :fetch, DocumentFetcherAgent

  step :initial_review, InitialReviewAgent,
       input: -> { { document: fetch, submitter: input.submitter_id } }

  # Skip detailed review for fast-track
  step :detailed_review, DetailedReviewAgent,
       unless: :fast_track?,
       input: -> { { document: fetch, initial: initial_review } }

  step :compliance_check, ComplianceAgent,
       retry: 2, on: ComplianceServiceError,
       critical: true

  # Route to appropriate approver
  step :approval, on: -> { determine_approval_level } do |route|
    route.manager   ManagerApprovalAgent
    route.director  DirectorApprovalAgent
    route.executive ExecutiveApprovalAgent
  end

  step :finalize, on: -> { approval.decision } do |route|
    route.approved ApprovalFinalizeAgent
    route.rejected RejectionFinalizeAgent
    route.default  PendingFinalizeAgent
  end

  step :notify, NotificationAgent,
       optional: true

  private

  def fast_track?
    input.fast_track && initial_review.risk_score < 0.3
  end

  def determine_approval_level
    score = compliance_check.risk_score
    case
    when score < 0.3 then :manager
    when score < 0.7 then :director
    else :executive
    end
  end
end
```

---

## Comparison: Before & After

### Before (Verbose)

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  flow :validate -> :enrich -> :process -> :notify

  step :validate do
    desc "Validate the order"
    timeout 30.seconds
  end
  def validate
    agent ValidatorAgent, order_id: options[:order_id]
  end

  step :enrich do
    desc "Enrich with customer data"
    retry_on Timeout::Error, max: 3
  end
  def enrich
    agent EnricherAgent, customer_id: results[:validate][:customer_id]
  end

  step :process do
    desc "Process the order"
    critical
  end
  def process
    tier = results[:enrich][:customer][:tier]
    case tier
    when "premium" then agent PremiumAgent
    when "standard" then agent StandardAgent
    else agent DefaultAgent
    end
  end

  def notify
    return unless options[:callback_url]
    agent NotifierAgent, url: options[:callback_url]
  end
end
```

### After (Clean)

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  input do
    required :order_id, String
    optional :callback_url, String
  end

  step :validate, ValidatorAgent, timeout: 30.seconds

  step :enrich, EnricherAgent,
       input: -> { { customer_id: validate.customer_id } },
       retry: 3, on: Timeout::Error

  step :process, critical: true, on: -> { enrich.customer.tier } do |r|
    r.premium  PremiumAgent
    r.standard StandardAgent
    r.default  DefaultAgent
  end

  step :notify, NotifierAgent, if: :has_callback?

  private

  def has_callback? = input.callback_url.present?
end
```

**Lines of code: 35 → 18 (49% reduction)**

---

## Implementation Phases

### Phase 1: Core Step DSL
1. Basic `step :name, Agent` syntax
2. Implicit flow (definition order)
3. Options: `timeout`, `optional`, `critical`
4. Simple `input:` lambda

### Phase 2: Conditions & Routing
5. `if:` / `unless:` with symbols and lambdas
6. `on:` routing with block builder
7. `route:` / `to:` shorthand

### Phase 3: Parallel & Control
8. `parallel do` blocks
9. Named parallel groups
10. Control methods: `skip!`, `halt!`, `fail!`

### Phase 4: Error Handling
11. `retry:` with count and error types
12. `fallback:` agent chains
13. `on_error:` handlers

### Phase 5: Input Mapping
14. `pick:` field selection
15. `from:` source step
16. Smart defaults and merging

---

## Migration Guide

All changes are backwards compatible:

```ruby
# Old syntax still works
class OldWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :process, agent: ProcessorAgent
end

# New syntax available
class NewWorkflow < RubyLLM::Agents::Workflow
  step :process, ProcessorAgent
end

# Gradual migration
class HybridWorkflow < RubyLLM::Agents::Workflow
  # Old-style step with agent: keyword
  step :legacy, agent: LegacyAgent

  # New-style step
  step :modern, ModernAgent, retry: 3
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── workflow.rb                    # Base class
├── workflow/
│   ├── dsl/
│   │   ├── step_config.rb         # Step configuration
│   │   ├── route_builder.rb       # Routing DSL
│   │   ├── parallel_group.rb      # Parallel execution
│   │   └── section.rb             # Visual sections
│   ├── execution/
│   │   ├── executor.rb            # Main executor
│   │   ├── step_executor.rb       # Single step execution
│   │   ├── parallel_executor.rb   # Parallel step execution
│   │   └── retry_handler.rb       # Retry logic
│   ├── input/
│   │   ├── schema.rb              # Input validation
│   │   ├── proxy.rb               # Input access
│   │   └── resolver.rb            # Input mapping
│   └── results/
│       ├── proxy.rb               # Results access
│       └── workflow_result.rb     # Final result
```

---

## Success Criteria

1. **Simple workflows are simple** - 3 lines for basic workflow
2. **Complex workflows are readable** - Scan and understand in seconds
3. **Full backwards compatibility** - Existing workflows unchanged
4. **Testable** - Each feature easily unit tested
5. **Documented** - Clear examples for every feature
6. **Performant** - No overhead vs current implementation

---

## Verification

After implementing changes, verify:

1. **Code Examples** - All Ruby code examples are syntactically valid
2. **Section Ordering** - Logical flow from basic to advanced concepts
3. **No Duplicates** - No redundant content across sections
4. **Cross-References** - Internal links work correctly
5. **Completeness** - All DSL features are documented with examples
