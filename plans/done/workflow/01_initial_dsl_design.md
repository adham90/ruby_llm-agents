# Workflow DSL Improvements Plan

> **Goal:** Create a comprehensive, Rails-like DSL for building agent workflows that covers all patterns found in visual workflow builders like n8n, while keeping the simplicity and convention-over-configuration philosophy of Rails.

## Current State Analysis

### Existing Workflow Classes

| Class | Purpose | DSL |
|-------|---------|-----|
| `Pipeline` | Sequential execution | `step :name, agent: Class` |
| `Parallel` | Concurrent branches | `branch :name, agent: Class` |
| `Router` | Conditional dispatch | `route :name, to: Class` |

### Existing Features
- `version`, `timeout`, `max_cost`, `description` class methods
- `before_<step>` hooks for input transformation
- `on_<step>_failure` error handlers
- `skip_on:` lambda for conditional skipping
- `optional:` / `continue_on_error:` flags
- `aggregate` method for parallel results

### Gaps Identified

| Gap | n8n Equivalent | Priority |
|-----|----------------|----------|
| Inline Ruby code blocks | Code Node | P1 |
| Conditional branching (if/case) | IF/Switch Node | P1 |
| Step-level callbacks | — | P1 |
| Input/output validation | — | P1 |
| Loops/iteration | Loop Node | P2 |
| Sub-workflow composition | Execute Workflow | P2 |
| Per-step retry/fallback | Retry on Fail | P2 |
| Map/reduce patterns | Split in Batches | P2 |
| Wait/delay | Wait Node | P3 |
| Human-in-the-loop | Manual Approval | P3 |
| HTTP request helper | HTTP Request Node | P3 |

---

## Design Principles

1. **Convention over Configuration** - Sensible defaults, minimal boilerplate
2. **Declarative over Imperative** - Describe what, not how
3. **Composability** - Small pieces that combine well
4. **Rails Familiarity** - Follow patterns Ruby developers know
5. **Type Safety** - Optional but encouraged input/output schemas
6. **Debuggability** - Easy to inspect, test, and trace

---

## Phase 1: Core DSL Enhancements (P1)

### 1.1 Inline Ruby Code Blocks

Allow steps that execute Ruby code without requiring an agent class.

```ruby
class DataWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :fetch, agent: FetcherAgent

  # Block-based step - no agent needed
  step :transform do |ctx|
    data = ctx[:fetch].content
    {
      name: data[:full_name].titleize,
      email: data[:email].downcase,
      processed_at: Time.current
    }
  end

  step :save, agent: SaverAgent
end
```

**Implementation:**

```ruby
# In Pipeline class
def step(name, agent: nil, **options, &block)
  if block_given? && agent.nil?
    steps[name] = {
      type: :ruby,
      block: block,
      **options
    }
  elsif agent
    steps[name] = {
      type: :agent,
      agent: agent,
      **options
    }
  else
    raise ArgumentError, "Step requires either agent: or a block"
  end
end

# In execute_pipeline
def execute_step(name, config, context, &stream_block)
  case config[:type]
  when :agent
    execute_agent(config[:agent], step_input, step_name: name, &stream_block)
  when :ruby
    execute_ruby_block(name, config[:block], context)
  end
end

def execute_ruby_block(name, block, context)
  result = instance_exec(context, &block)

  # Wrap in Result-like object for consistency
  RubyBlockResult.new(
    content: result,
    step_name: name,
    duration_ms: elapsed
  )
end
```

### 1.2 Conditional Steps

Add `if:`, `unless:`, and `case:` options to steps.

```ruby
class ConditionalWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :classify, agent: ClassifierAgent

  # Simple conditions
  step :premium, agent: PremiumAgent,
       if: -> { ctx[:classify].content[:tier] == "premium" }

  step :standard, agent: StandardAgent,
       unless: -> { ctx[:classify].content[:tier] == "premium" }

  # Case/switch pattern
  step :process do
    case_on -> { ctx[:classify].content[:type] }

    when_eq "text", agent: TextAgent
    when_eq "image", agent: ImageAgent
    when_in ["audio", "video"], agent: MediaAgent
    otherwise agent: DefaultAgent
  end
end
```

**Implementation:**

```ruby
# Add to step options
def step(name, agent: nil, if: nil, unless: nil, **options, &block)
  steps[name] = {
    agent: agent,
    condition_if: binding.local_variable_get(:if),
    condition_unless: binding.local_variable_get(:unless),
    **options
  }

  if block_given? && agent.nil?
    # Case block DSL
    case_builder = CaseBuilder.new
    case_builder.instance_eval(&block)
    steps[name][:case] = case_builder.build
  end
end

class CaseBuilder
  def initialize
    @condition = nil
    @branches = []
    @default = nil
  end

  def case_on(condition)
    @condition = condition
  end

  def when_eq(value, agent:)
    @branches << { match: :eq, value: value, agent: agent }
  end

  def when_in(values, agent:)
    @branches << { match: :in, value: values, agent: agent }
  end

  def when_match(pattern, agent:)
    @branches << { match: :regex, value: pattern, agent: agent }
  end

  def otherwise(agent:)
    @default = agent
  end

  def build
    { condition: @condition, branches: @branches, default: @default }
  end
end

# In execute_pipeline
def should_execute_step?(config, context)
  return false if config[:condition_if] && !evaluate_condition(config[:condition_if], context)
  return false if config[:condition_unless] && evaluate_condition(config[:condition_unless], context)
  true
end

def evaluate_condition(condition, context)
  case condition
  when Proc then instance_exec(context, &condition)
  when Symbol then send(condition, context)
  else condition
  end
end
```

### 1.3 Step-Level Callbacks

Rails-style callbacks for workflow and step lifecycle.

```ruby
class CallbackWorkflow < RubyLLM::Agents::Workflow::Pipeline
  # Workflow-level callbacks
  before_workflow :log_start
  after_workflow :log_complete
  around_workflow :with_transaction

  # Step-level callbacks
  before_step :validate_input
  after_step :record_metrics
  around_step :with_timing

  # Targeted callbacks
  before_step :extract, :prepare_extraction
  after_step :extract, :cache_result, if: -> { result.success? }

  step :extract, agent: ExtractorAgent
  step :process, agent: ProcessorAgent

  private

  def log_start
    Rails.logger.info "Starting #{self.class.name}"
  end

  def with_timing
    start = Time.current
    yield
    @duration = Time.current - start
  end

  def validate_input
    raise ArgumentError, "Missing text" unless options[:text].present?
  end
end
```

**Implementation:**

```ruby
module DSL
  module Callbacks
    extend ActiveSupport::Concern

    included do
      class_attribute :_workflow_callbacks, default: { before: [], after: [], around: [] }
      class_attribute :_step_callbacks, default: Hash.new { |h, k| h[k] = { before: [], after: [], around: [] } }
    end

    class_methods do
      def before_workflow(method_name = nil, &block)
        _workflow_callbacks[:before] << (block || method_name)
      end

      def after_workflow(method_name = nil, &block)
        _workflow_callbacks[:after] << (block || method_name)
      end

      def around_workflow(method_name)
        _workflow_callbacks[:around] << method_name
      end

      def before_step(step_name = :all, method_name = nil, **options, &block)
        callback = { handler: block || method_name, options: options }
        _step_callbacks[step_name][:before] << callback
      end

      def after_step(step_name = :all, method_name = nil, **options, &block)
        callback = { handler: block || method_name, options: options }
        _step_callbacks[step_name][:after] << callback
      end

      def around_step(step_name = :all, method_name)
        _step_callbacks[step_name][:around] << method_name
      end
    end

    private

    def run_callbacks(type, kind, context = nil, &block)
      callbacks = case type
      when :workflow then self.class._workflow_callbacks[kind]
      when :step then collect_step_callbacks(context[:step_name], kind)
      end

      if kind == :around
        run_around_callbacks(callbacks, &block)
      else
        callbacks.each { |cb| run_callback(cb, context) }
      end
    end

    def run_callback(callback, context)
      handler = callback.is_a?(Hash) ? callback[:handler] : callback
      options = callback.is_a?(Hash) ? callback[:options] : {}

      # Check conditions
      return if options[:if] && !evaluate_condition(options[:if], context)
      return if options[:unless] && evaluate_condition(options[:unless], context)

      case handler
      when Symbol then send(handler, context)
      when Proc then instance_exec(context, &handler)
      end
    end

    def run_around_callbacks(callbacks, &block)
      if callbacks.empty?
        yield
      else
        callback = callbacks.first
        remaining = callbacks[1..]
        send(callback) { run_around_callbacks(remaining, &block) }
      end
    end

    def collect_step_callbacks(step_name, kind)
      all_callbacks = self.class._step_callbacks[:all][kind] || []
      step_callbacks = self.class._step_callbacks[step_name][kind] || []
      all_callbacks + step_callbacks
    end
  end
end
```

### 1.4 Input/Output Validation

Strong parameter-style validation for workflow inputs and outputs.

```ruby
class ValidatedWorkflow < RubyLLM::Agents::Workflow::Pipeline
  # Input schema
  input do
    required :text, String
    required :user_id, Integer
    optional :language, String, default: "en", in: %w[en es fr de]
    optional :options, Hash, default: -> { {} }
    optional :callback_url, String, format: :url
  end

  # Output schema
  output do
    required :summary, String
    required :sentiment, String, in: %w[positive negative neutral]
    required :confidence, Float, range: 0.0..1.0
    optional :keywords, Array, of: String
  end

  step :analyze, agent: AnalyzerAgent

  # Map final context to output schema
  finalize do |ctx|
    {
      summary: ctx[:analyze].content[:summary],
      sentiment: ctx[:analyze].content[:sentiment],
      confidence: ctx[:analyze].content[:score],
      keywords: ctx[:analyze].content[:tags]
    }
  end
end
```

**Implementation:**

```ruby
module DSL
  module Schema
    extend ActiveSupport::Concern

    class SchemaBuilder
      def initialize
        @fields = {}
      end

      def required(name, type, **options)
        @fields[name] = { type: type, required: true, **options }
      end

      def optional(name, type, **options)
        @fields[name] = { type: type, required: false, **options }
      end

      def build
        Schema.new(@fields)
      end
    end

    class Schema
      def initialize(fields)
        @fields = fields
      end

      def validate!(data)
        errors = []

        @fields.each do |name, config|
          value = data[name]

          # Required check
          if config[:required] && value.nil? && !config.key?(:default)
            errors << "#{name} is required"
            next
          end

          # Apply default
          if value.nil? && config.key?(:default)
            data[name] = config[:default].is_a?(Proc) ? config[:default].call : config[:default]
            value = data[name]
          end

          next if value.nil?

          # Type check
          unless value.is_a?(config[:type])
            errors << "#{name} must be a #{config[:type]}"
          end

          # Inclusion check
          if config[:in] && !config[:in].include?(value)
            errors << "#{name} must be one of: #{config[:in].join(', ')}"
          end

          # Range check
          if config[:range] && !config[:range].cover?(value)
            errors << "#{name} must be in range #{config[:range]}"
          end

          # Format check
          if config[:format]
            validate_format!(name, value, config[:format], errors)
          end
        end

        raise ValidationError.new(errors) if errors.any?
        data
      end

      private

      def validate_format!(name, value, format, errors)
        case format
        when :url
          errors << "#{name} must be a valid URL" unless value.match?(URI::DEFAULT_PARSER.make_regexp)
        when :email
          errors << "#{name} must be a valid email" unless value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
        when Regexp
          errors << "#{name} format is invalid" unless value.match?(format)
        end
      end
    end

    class_methods do
      def input(&block)
        builder = SchemaBuilder.new
        builder.instance_eval(&block)
        @input_schema = builder.build
      end

      def output(&block)
        builder = SchemaBuilder.new
        builder.instance_eval(&block)
        @output_schema = builder.build
      end

      def input_schema
        @input_schema
      end

      def output_schema
        @output_schema
      end
    end
  end
end

# In Workflow base class
def initialize(**kwargs)
  @options = self.class.input_schema&.validate!(kwargs.dup) || kwargs
  # ...
end

def finalize_result(context)
  content = if self.class.method_defined?(:finalize_output)
    finalize_output(context)
  else
    extract_final_content(context)
  end

  self.class.output_schema&.validate!(content) || content
end
```

---

## Phase 2: Composition Patterns (P2)

### 2.1 Loops and Iteration

```ruby
class BatchWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :fetch, agent: FetcherAgent

  # Process each item
  step :process_items, each: -> { ctx[:fetch].content[:items] } do |item, index|
    agent ProcessorAgent, input: { item: item, position: index }
  end

  # Process in batches
  step :batch_upload, each: -> { ctx[:process_items] }, batch_size: 10 do |batch|
    agent BatchUploaderAgent, input: { items: batch }
  end

  # Collect/reduce results
  step :summarize do |ctx|
    ctx[:process_items].map(&:content).reduce(&:merge)
  end
end
```

**Implementation:**

```ruby
def step(name, each: nil, batch_size: nil, **options, &block)
  if each
    steps[name] = {
      type: :loop,
      collection: each,
      batch_size: batch_size,
      block: block,
      **options
    }
  else
    # ... existing step logic
  end
end

def execute_loop_step(name, config, context, &stream_block)
  collection = evaluate_condition(config[:collection], context)
  batch_size = config[:batch_size]

  results = if batch_size
    collection.each_slice(batch_size).map.with_index do |batch, batch_idx|
      execute_loop_iteration(name, config, context, batch, batch_idx, &stream_block)
    end
  else
    collection.map.with_index do |item, index|
      execute_loop_iteration(name, config, context, item, index, &stream_block)
    end
  end

  LoopResult.new(content: results, step_name: name)
end

def execute_loop_iteration(name, config, context, item, index, &stream_block)
  loop_context = LoopContext.new(context, item, index)
  instance_exec(item, index, &config[:block])
end

class LoopContext
  attr_reader :item, :index

  def initialize(parent_context, item, index)
    @parent = parent_context
    @item = item
    @index = index
  end

  def agent(klass, input: {})
    # Execute agent with loop item context
    klass.call(**input)
  end
end
```

### 2.2 Sub-Workflow Composition

```ruby
class MasterWorkflow < RubyLLM::Agents::Workflow::Pipeline
  # Simple sub-workflow
  step :preprocess, workflow: PreprocessingWorkflow

  # With input transformation
  step :analyze, workflow: AnalysisWorkflow,
       input: -> { { text: ctx[:preprocess].content[:cleaned] } }

  # Conditional sub-workflow
  step :special, workflow: SpecialWorkflow,
       if: -> { ctx[:analyze].content[:needs_special] }

  # Parallel sub-workflows
  step :multi_analyze, parallel: true do
    workflow SentimentWorkflow, as: :sentiment
    workflow TopicWorkflow, as: :topics
    workflow EntityWorkflow, as: :entities
  end
end
```

**Implementation:**

```ruby
def step(name, workflow: nil, **options, &block)
  if workflow
    steps[name] = {
      type: :workflow,
      workflow_class: workflow,
      **options
    }
  else
    # ... existing logic
  end
end

def execute_workflow_step(name, config, context, &stream_block)
  workflow_class = config[:workflow_class]

  # Build input
  input = if config[:input]
    evaluate_condition(config[:input], context)
  else
    extract_step_input(context)
  end

  # Execute sub-workflow with parent context
  result = workflow_class.call(
    **input,
    execution_metadata: {
      parent_workflow_id: workflow_id,
      parent_step: name.to_s
    },
    &stream_block
  )

  result
end
```

### 2.3 Per-Step Retry and Fallback

```ruby
class ResilientWorkflow < RubyLLM::Agents::Workflow::Pipeline
  # Global retry policy
  retry_policy max: 3, backoff: :exponential, on: [RateLimitError, TimeoutError]

  step :fetch, agent: FetcherAgent

  # Per-step retry
  step :process, agent: ProcessorAgent,
       retry: { max: 5, delay: 2.seconds, on: ApiError }

  # Fallback chain
  step :generate, agent: PrimaryAgent,
       fallback: [SecondaryAgent, TertiaryAgent]

  # Both retry and fallback
  step :critical, agent: CriticalAgent,
       retry: { max: 3 },
       fallback: [BackupAgent]
end
```

**Implementation:**

```ruby
class_methods do
  def retry_policy(**options)
    @default_retry_policy = options
  end

  def default_retry_policy
    @default_retry_policy || {}
  end
end

def execute_step_with_retry(name, config, context, &block)
  retry_config = config[:retry] || self.class.default_retry_policy
  fallbacks = config[:fallback] || []

  attempts = 0
  max_attempts = retry_config[:max] || 1

  begin
    attempts += 1
    execute_agent(config[:agent], step_input, step_name: name, &block)
  rescue *Array(retry_config[:on] || StandardError) => e
    if attempts < max_attempts
      delay = calculate_delay(retry_config, attempts)
      sleep(delay) if delay > 0
      retry
    elsif fallbacks.any?
      execute_fallback_chain(fallbacks, step_input, name, &block)
    else
      raise
    end
  end
end

def execute_fallback_chain(fallbacks, input, step_name, &block)
  fallbacks.each_with_index do |agent_class, index|
    begin
      return execute_agent(agent_class, input, step_name: "#{step_name}_fallback_#{index}", &block)
    rescue StandardError => e
      raise if index == fallbacks.size - 1
    end
  end
end

def calculate_delay(config, attempt)
  base = config[:delay] || 1
  case config[:backoff]
  when :exponential
    base * (2 ** (attempt - 1))
  when :linear
    base * attempt
  else
    base
  end
end
```

---

## Phase 3: Advanced Features (P3)

### 3.1 Wait/Delay/Polling

```ruby
class AsyncWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :submit_job, agent: JobSubmitterAgent

  # Simple delay
  step :wait_processing do
    wait 5.seconds
  end

  # Poll until condition
  step :wait_completion, poll: true do
    check -> { JobService.status(ctx[:submit_job].content[:job_id]) == "complete" }
    interval 10.seconds
    timeout 5.minutes
    on_timeout { raise JobTimeoutError }
  end

  step :fetch_results, agent: ResultFetcherAgent
end
```

### 3.2 Human-in-the-Loop

```ruby
class ApprovalWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :generate, agent: ContentGeneratorAgent

  # Wait for external approval
  step :await_approval, wait_for: :approval_event do
    timeout 24.hours
    on_timeout { { approved: false, reason: "timeout" } }

    on_receive do |event|
      if event[:approved]
        :continue
      else
        :abort
      end
    end
  end

  step :publish, agent: PublisherAgent, if: -> { ctx[:await_approval][:approved] }
end
```

### 3.3 HTTP Request Helper

```ruby
class IntegrationWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :fetch_user, agent: UserFetcherAgent

  # Built-in HTTP helper
  step :enrich_from_api do |ctx|
    response = http.get("https://api.example.com/users/#{ctx[:fetch_user].content[:id]}",
      headers: { "Authorization" => "Bearer #{ENV['API_KEY']}" },
      timeout: 10.seconds
    )

    JSON.parse(response.body)
  end

  step :post_webhook do |ctx|
    http.post("https://hooks.example.com/notify",
      json: { user: ctx[:enrich_from_api] },
      retry: { max: 3, on: [Timeout::Error] }
    )
  end
end
```

---

## Shared Behaviors (Concerns)

```ruby
# app/workflows/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern

  included do
    before_workflow :create_audit_record
    after_workflow :complete_audit_record
    after_step :all, :log_step_to_audit
  end

  private

  def create_audit_record
    @audit = WorkflowAudit.create!(
      workflow_class: self.class.name,
      workflow_id: workflow_id,
      input: options.except(:sensitive_field),
      started_at: Time.current
    )
  end

  def complete_audit_record
    @audit.update!(
      completed_at: Time.current,
      status: @workflow_result.status
    )
  end

  def log_step_to_audit(context)
    @audit.steps.create!(
      name: context[:step_name],
      status: context[:result].success? ? "success" : "error"
    )
  end
end

# Usage
class AuditedWorkflow < RubyLLM::Agents::Workflow::Pipeline
  include Auditable
  include Measurable
  include Notifiable

  step :process, agent: ProcessorAgent
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── workflow.rb                    # Base Workflow class (enhanced)
├── workflow/
│   ├── dsl/
│   │   ├── callbacks.rb           # Callback DSL
│   │   ├── schema.rb              # Input/output validation
│   │   ├── conditions.rb          # if/unless/case DSL
│   │   ├── loops.rb               # each/batch iteration
│   │   └── retry.rb               # Retry/fallback configuration
│   ├── execution/
│   │   ├── step_executor.rb       # Unified step execution
│   │   ├── loop_executor.rb       # Loop/batch execution
│   │   ├── case_executor.rb       # Case/switch execution
│   │   └── workflow_executor.rb   # Sub-workflow execution
│   ├── results/
│   │   ├── ruby_block_result.rb   # Result for inline Ruby
│   │   ├── loop_result.rb         # Result for loop steps
│   │   └── case_result.rb         # Result for case steps
│   ├── helpers/
│   │   └── http.rb                # HTTP request helper
│   ├── pipeline.rb                # Sequential workflow (enhanced)
│   ├── parallel.rb                # Concurrent workflow (enhanced)
│   ├── router.rb                  # Routing workflow (enhanced)
│   ├── result.rb                  # Workflow result
│   └── errors.rb                  # Workflow-specific errors
```

---

## Migration Path

### Phase 1 (Non-breaking)
All new features are additive. Existing workflows continue to work unchanged.

```ruby
# Old style - still works
class OldWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :process, agent: ProcessorAgent
end

# New style - opt-in to new features
class NewWorkflow < RubyLLM::Agents::Workflow::Pipeline
  input { required :text, String }

  before_step :validate

  step :process, agent: ProcessorAgent, retry: { max: 3 }

  step :transform do |ctx|
    ctx[:process].content.transform_keys(&:to_sym)
  end
end
```

### Future Consideration: Unified Workflow Class

Eventually consider merging Pipeline/Parallel/Router into a single `Workflow` class where the execution pattern is determined by step configuration:

```ruby
class UnifiedWorkflow < RubyLLM::Agents::Workflow
  # Sequential by default
  step :fetch, agent: FetcherAgent

  # Inline parallel block
  step :analyze, parallel: true do
    branch :sentiment, agent: SentimentAgent
    branch :keywords, agent: KeywordAgent
  end

  # Inline routing
  step :route do
    case_on -> { ctx[:analyze][:sentiment].content }
    when_eq "positive", agent: PositiveAgent
    when_eq "negative", agent: NegativeAgent
    otherwise agent: NeutralAgent
  end

  step :finalize, agent: FinalizerAgent
end
```

---

## Implementation Order

### Sprint 1 (Week 1-2)
1. Inline Ruby code blocks
2. Conditional `if:` / `unless:`
3. Basic callbacks (`before_step`, `after_step`)

### Sprint 2 (Week 3-4)
4. Input validation schema
5. Output validation schema
6. Case/switch DSL

### Sprint 3 (Week 5-6)
7. Each/loop iteration
8. Batch processing
9. Sub-workflow composition

### Sprint 4 (Week 7-8)
10. Per-step retry configuration
11. Fallback chains
12. Workflow-level callbacks

### Sprint 5 (Week 9-10)
13. HTTP helper
14. Wait/delay
15. Polling steps

### Future
16. Human-in-the-loop (requires persistence layer)
17. Unified Workflow class
18. Visual representation export (for debugging)

---

## Testing Strategy

```ruby
# spec/workflow/dsl/callbacks_spec.rb
RSpec.describe "Workflow Callbacks" do
  let(:workflow_class) do
    Class.new(RubyLLM::Agents::Workflow::Pipeline) do
      before_workflow :setup
      after_step :all, :log_step

      step :process, agent: MockAgent

      attr_reader :setup_called, :steps_logged

      def setup
        @setup_called = true
        @steps_logged = []
      end

      def log_step(ctx)
        @steps_logged << ctx[:step_name]
      end
    end
  end

  it "calls before_workflow callback" do
    instance = workflow_class.new(text: "test")
    instance.call

    expect(instance.setup_called).to be true
  end

  it "calls after_step for each step" do
    instance = workflow_class.new(text: "test")
    instance.call

    expect(instance.steps_logged).to eq([:process])
  end
end
```

---

## Success Criteria

1. **Backwards Compatible** - All existing workflows work without changes
2. **Rails-y Feel** - Developers familiar with Rails feel at home
3. **Comprehensive** - Covers 90% of n8n node patterns
4. **Testable** - Each DSL feature has clear testing patterns
5. **Documented** - Full YARD documentation with examples
6. **Performant** - No significant overhead vs current implementation
