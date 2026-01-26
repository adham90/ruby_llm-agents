# Implement Sub-workflow, Iteration, and Recursion for Workflow DSL

## Goal

Implement three advanced composition features in the Workflow DSL, then create example workflows demonstrating all possible use cases.

---

## Phase 1: Sub-workflow Composition

### What
Allow `step :name, SomeWorkflow` where `SomeWorkflow` is another Workflow class.

### Syntax
```ruby
step :shipping, ShippingWorkflow,
     input: -> { { address: process.shipping_address } }
```

### Files to Modify

**1. `lib/ruby_llm/agents/workflow/dsl/step_config.rb`**
- Add `workflow?` method to detect Workflow subclass:
```ruby
def workflow?
  agent.present? && agent < RubyLLM::Agents::Workflow
end
```

**2. `lib/ruby_llm/agents/workflow/dsl/step_executor.rb`**
- Add `execute_workflow_step` method
- Modify `execute_agent_or_block` to dispatch to workflow execution
- Add budget calculation helpers (`calculate_remaining_timeout`, `calculate_remaining_cost_budget`)

**3. `lib/ruby_llm/agents/workflow/orchestrator.rb`**
- Extract parent context from `execution_metadata` in `initialize`
- Respect inherited timeout/cost budgets

**4. `lib/ruby_llm/agents/workflow/result.rb`**
- Add `SubWorkflowResult` class for wrapping nested workflow results

---

## Phase 2: Loop/Iteration Support

### What
Allow `step :name, each: -> { items }` to process collections.

### Syntax
```ruby
# Block-based iteration
step :process_items, each: -> { input.items } do |item|
  agent ProcessorAgent, input: -> { { data: item } }
end

# Agent-based with concurrency
step :process_items, ProcessorAgent,
     each: -> { input.items },
     concurrency: 5,
     fail_fast: true
```

### Files to Create

**1. `lib/ruby_llm/agents/workflow/dsl/iteration_executor.rb`**
- `IterationExecutor` class for sequential/parallel iteration
- `IterationContext` class extending `BlockContext` with `item` and `index`

### Files to Modify

**1. `lib/ruby_llm/agents/workflow/dsl/step_config.rb`**
- Add `iteration?`, `each_source`, `iteration_concurrency`, `iteration_fail_fast?`, `continue_on_error?`

**2. `lib/ruby_llm/agents/workflow/dsl/step_executor.rb`**
- Add `execute_iteration_step` dispatch

**3. `lib/ruby_llm/agents/workflow/result.rb`**
- Add `IterationResult` class with item-level tracking and aggregation

**4. `lib/ruby_llm/agents/workflow/dsl.rb`**
- Require new `iteration_executor.rb`

---

## Phase 3: Recursion Support

### What
Allow workflows to call themselves with termination safeguards.

### Syntax
```ruby
class TreeProcessorWorkflow < RubyLLM::Agents::Workflow
  max_recursion_depth 10

  step :process_node, NodeProcessorAgent

  step :process_children, TreeProcessorWorkflow,
       each: -> { process_node.children },
       if: -> { process_node.children.present? }
end
```

### Files to Modify

**1. `lib/ruby_llm/agents/workflow/orchestrator.rb`**
- Add `max_recursion_depth` class method (default: 10)
- Add `RecursionDepthExceededError`
- Add `check_recursion_depth!` validation in `initialize`
- Track `@recursion_depth` from execution_metadata

**2. `lib/ruby_llm/agents/workflow/dsl/step_executor.rb`**
- Increment recursion depth for self-referential workflow calls

---

## Phase 4: Example Workflows

Create these example workflows in `example/app/workflows/`:

### 1. `order_processing_workflow.rb` (Sub-workflow Demo)
Demonstrates:
- Calling other workflows as steps
- Input transformation for sub-workflows
- Budget inheritance (timeout, cost)
- Accessing nested step results

### 2. `batch_processor_workflow.rb` (Iteration Demo)
Demonstrates:
- Sequential iteration with `each:`
- Parallel iteration with `concurrency:`
- `fail_fast:` behavior
- `continue_on_error:` behavior
- Agent-based iteration
- Block-based iteration

### 3. `tree_processor_workflow.rb` (Recursion Demo)
Demonstrates:
- Self-referential workflow calls
- `max_recursion_depth` setting
- Termination conditions with `if:`
- Recursive result aggregation

### 4. `document_pipeline_workflow.rb` (Combined Patterns Demo)
Demonstrates:
- Iteration + sub-workflows combined
- Processing document sections in parallel
- Each section triggers a sub-workflow
- All features working together

---

## Phase 5: New Agents Required

Create in `example/app/agents/`:

1. `shipping_calculator_agent.rb` - For order workflow
2. `shipping_reserve_agent.rb` - For order workflow
3. `item_processor_agent.rb` - For batch processor
4. `node_processor_agent.rb` - For tree processor
5. `section_analyzer_agent.rb` - For document pipeline

---

## Implementation Order

1. **Core DSL changes** (step_config.rb, step_executor.rb)
2. **Sub-workflow support** (orchestrator.rb, result.rb)
3. **Iteration support** (iteration_executor.rb, IterationResult)
4. **Recursion support** (max_recursion_depth, depth checking)
5. **New agents** (5 agents)
6. **Example workflows** (4 workflows)
7. **Tests** (unit + integration specs)

---

## Files Summary

### Create
- `lib/ruby_llm/agents/workflow/dsl/iteration_executor.rb`
- `example/app/workflows/order_processing_workflow.rb`
- `example/app/workflows/batch_processor_workflow.rb`
- `example/app/workflows/tree_processor_workflow.rb`
- `example/app/workflows/document_pipeline_workflow.rb`
- `example/app/agents/shipping_calculator_agent.rb`
- `example/app/agents/shipping_reserve_agent.rb`
- `example/app/agents/item_processor_agent.rb`
- `example/app/agents/node_processor_agent.rb`
- `example/app/agents/section_analyzer_agent.rb`
- `spec/workflow/dsl/sub_workflow_spec.rb`
- `spec/workflow/dsl/iteration_spec.rb`
- `spec/workflow/dsl/recursion_spec.rb`

### Modify
- `lib/ruby_llm/agents/workflow/dsl/step_config.rb`
- `lib/ruby_llm/agents/workflow/dsl/step_executor.rb`
- `lib/ruby_llm/agents/workflow/orchestrator.rb`
- `lib/ruby_llm/agents/workflow/result.rb`
- `lib/ruby_llm/agents/workflow/dsl.rb`

---

## Edge Cases & Safeguards

| Concern | Safeguard |
|---------|-----------|
| Infinite recursion | `max_recursion_depth` (default 10), `RecursionDepthExceededError` |
| Timeout in sub-workflow | Inherit remaining timeout from parent |
| Cost exceeded in sub-workflow | Inherit remaining cost budget, raise `WorkflowCostExceededError` |
| Empty collection | Return `IterationResult.empty` with success status |
| Iteration failure | `fail_fast: true` stops, `continue_on_error: true` collects all |

---

## Verification

1. `bundle exec rspec spec/workflow/dsl/` - Run new unit tests
2. `bundle exec rspec` - Run full test suite
3. `cd example && rails s` - Start server
4. Visit `/ruby_llm/agents/workflows` - Verify all 7 workflows appear
5. Check workflow diagrams show sub-workflows, iterations, recursion indicators

---

## Detailed Implementation Code

### SubWorkflowResult (result.rb)

```ruby
class SubWorkflowResult
  attr_reader :workflow_result, :step_name

  delegate :content, :success?, :error?, :partial?,
           :input_tokens, :output_tokens, :total_tokens, :cached_tokens,
           :input_cost, :output_cost, :total_cost,
           :started_at, :completed_at, :duration_ms,
           to: :workflow_result

  def initialize(step_name, workflow_result)
    @step_name = step_name
    @workflow_result = workflow_result
  end

  def sub_workflow?
    true
  end

  def steps
    workflow_result.steps
  end

  def to_h
    {
      step_name: step_name,
      sub_workflow: true,
      workflow_type: workflow_result.workflow_type,
      workflow_id: workflow_result.workflow_id,
      content: content,
      status: workflow_result.status,
      steps: steps.transform_values { |r| r.respond_to?(:to_h) ? r.to_h : r },
      total_cost: total_cost,
      total_tokens: total_tokens
    }
  end
end
```

### IterationResult (result.rb)

```ruby
class IterationResult
  attr_reader :step_name, :items, :results, :errors

  def initialize(step_name:, items:, results:, errors: {})
    @step_name = step_name
    @items = items
    @results = results
    @errors = errors
  end

  def self.empty(step_name)
    new(step_name: step_name, items: [], results: [], errors: {})
  end

  def content
    @results.map { |r| r.respond_to?(:content) ? r.content : r }
  end

  def success?
    errors.empty?
  end

  def error?
    !success?
  end

  def partial?
    errors.any? && results.any?
  end

  def iteration?
    true
  end

  def size
    items.size
  end

  def successful_count
    results.size
  end

  def failed_count
    errors.size
  end

  # Token/cost aggregation
  def input_tokens
    results.sum { |r| r.respond_to?(:input_tokens) ? r.input_tokens : 0 }
  end

  def output_tokens
    results.sum { |r| r.respond_to?(:output_tokens) ? r.output_tokens : 0 }
  end

  def total_tokens
    input_tokens + output_tokens
  end

  def cached_tokens
    results.sum { |r| r.respond_to?(:cached_tokens) ? r.cached_tokens : 0 }
  end

  def total_cost
    results.sum { |r| r.respond_to?(:total_cost) ? r.total_cost : 0.0 }
  end

  def [](index)
    results[index]
  end

  def each(&block)
    results.each(&block)
  end

  def map(&block)
    results.map(&block)
  end

  def to_h
    {
      step_name: step_name,
      iteration: true,
      total_items: items.size,
      successful: successful_count,
      failed: failed_count,
      results: results.map { |r| r.respond_to?(:to_h) ? r.to_h : r },
      errors: errors.transform_values { |e| { class: e.class.name, message: e.message } },
      total_cost: total_cost,
      total_tokens: total_tokens
    }
  end
end
```

### IterationExecutor (iteration_executor.rb)

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        class IterationExecutor
          attr_reader :workflow, :config, :previous_result

          def initialize(workflow, config, previous_result)
            @workflow = workflow
            @config = config
            @previous_result = previous_result
          end

          def execute(&block)
            items = resolve_items
            return IterationResult.empty(config.name) if items.empty?

            if config.iteration_concurrency && config.iteration_concurrency > 1
              execute_parallel(items, &block)
            else
              execute_sequential(items, &block)
            end
          end

          private

          def resolve_items
            source = config.each_source
            items = workflow.instance_exec(&source)
            items.respond_to?(:to_a) ? items.to_a : [items]
          end

          def execute_sequential(items, &block)
            results = []
            errors = {}

            items.each_with_index do |item, index|
              begin
                result = execute_item(item, index, &block)
                results << result
              rescue StandardError => e
                errors[index] = e

                if config.iteration_fail_fast?
                  break
                elsif !config.continue_on_error?
                  raise
                end
              end
            end

            IterationResult.new(
              step_name: config.name,
              items: items,
              results: results,
              errors: errors
            )
          end

          def execute_parallel(items, &block)
            pool = create_executor_pool(config.iteration_concurrency)
            results = Array.new(items.size)
            errors = {}
            mutex = Mutex.new
            aborted = false

            items.each_with_index do |item, index|
              pool.post do
                next if aborted

                begin
                  result = execute_item(item, index, &block)
                  mutex.synchronize { results[index] = result }
                rescue StandardError => e
                  mutex.synchronize do
                    errors[index] = e
                    aborted = true if config.iteration_fail_fast?
                  end
                end
              end
            end

            pool.wait_for_completion
            pool.shutdown

            IterationResult.new(
              step_name: config.name,
              items: items,
              results: results.compact,
              errors: errors
            )
          end

          def execute_item(item, index, &block)
            if config.block
              context = IterationContext.new(workflow, config, previous_result, item, index)
              context.instance_exec(item, &config.block)
            else
              input = resolve_item_input(item, index)
              workflow.send(:execute_agent, config.agent, input, step_name: "#{config.name}[#{index}]", &block)
            end
          end

          def resolve_item_input(item, index)
            if config.input_mapper
              if config.input_mapper.arity > 0
                workflow.instance_exec(item, &config.input_mapper)
              else
                workflow.instance_exec(&config.input_mapper).merge(item: item)
              end
            else
              { item: item, index: index }
            end
          end

          def create_executor_pool(size)
            RubyLLM::Agents.configuration.async_context? ?
              AsyncExecutor.new(max_concurrent: size) :
              ThreadPool.new(size: size)
          end
        end

        class IterationContext < BlockContext
          attr_reader :item, :index

          def initialize(workflow, config, previous_result, item, index)
            super(workflow, config, previous_result)
            @item = item
            @index = index
          end
        end
      end
    end
  end
end
```

### execute_workflow_step (step_executor.rb addition)

```ruby
def execute_workflow_step(previous_result, &block)
  step_input = config.resolve_input(workflow, previous_result)

  # Detect self-referential call for recursion tracking
  is_recursive = config.agent == workflow.class

  context = {
    parent_workflow_id: workflow.workflow_id,
    parent_execution_id: workflow.execution_id,
    remaining_timeout: calculate_remaining_timeout,
    remaining_cost_budget: calculate_remaining_cost_budget,
    recursion_depth: is_recursive ?
      workflow_recursion_depth + 1 :
      workflow_recursion_depth
  }

  merged_input = step_input.merge(
    execution_metadata: context.merge(step_input[:execution_metadata] || {})
  )

  config.agent.call(**merged_input, &block)
end

private

def calculate_remaining_timeout
  return nil unless workflow.class.timeout

  started_at = workflow.instance_variable_get(:@workflow_started_at)
  return nil unless started_at

  elapsed = Time.current - started_at
  remaining = workflow.class.timeout - elapsed
  [remaining, 0].max
end

def calculate_remaining_cost_budget
  return nil unless workflow.class.max_cost

  accumulated = workflow.instance_variable_get(:@accumulated_cost) || 0.0
  workflow.class.max_cost - accumulated
end

def workflow_recursion_depth
  workflow.instance_variable_get(:@recursion_depth) || 0
end
```
