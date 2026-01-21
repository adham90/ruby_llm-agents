# Action-Style Workflow DSL Improvements

> **Goal:** Enhance the workflow DSL with an Action-Style approach that maximizes readability, debuggability, and testability while maintaining Rails conventions.

## Background

This plan builds on [01_initial_dsl_design.md](./01_initial_dsl_design.md) which established the foundation. After comparing multiple DSL approaches (Action-Style, Hybrid, Fluent Builder, Minimal Convention, Pipe Operator), we selected **Action-Style** as the best fit because:

1. **Testability**: Steps are methods - call them directly in tests
2. **Debuggability**: Standard Ruby debugging, clear stack traces
3. **IDE Support**: Full autocomplete and refactoring tools
4. **Rails Familiarity**: Developers already know how to write methods
5. **Flexibility**: Full Ruby power when needed

---

## Design Principles

1. **Steps are Methods** - Each step is a regular Ruby instance method
2. **Flow is Explicit** - Declare execution order at the top of the class
3. **Convention with Escape Hatches** - Sensible defaults, full customization available
4. **Rich Context Access** - Dot notation for results, clear error messages
5. **First-Class Testing** - Built-in helpers for isolated step testing
6. **Comprehensive Tracing** - Every execution is inspectable

---

## Phase 1: Core Action-Style DSL

### 1.1 Flow Declaration

Replace arrow syntax with explicit `flow` block.

**Current:**
```ruby
flow :validate -> :enrich -> :process
```

**New:**
```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  flow do
    run :validate
    run :enrich
    run :process, :analyze, parallel: true
    run :notify
  end

  def validate
    agent ValidatorAgent
  end

  def enrich
    agent EnricherAgent
  end

  # ...
end
```

**Implementation:**

```ruby
module RubyLLM
  module Agents
    class Workflow
      class FlowBuilder
        def initialize
          @steps = []
        end

        def run(*step_names, parallel: false)
          if parallel || step_names.size > 1
            @steps << { type: :parallel, steps: step_names }
          else
            @steps << { type: :sequential, step: step_names.first }
          end
        end

        def sequence(name, &block)
          builder = FlowBuilder.new
          builder.instance_eval(&block)
          @steps << { type: :sequence, name: name, steps: builder.build }
        end

        def build
          @steps
        end
      end

      class_methods do
        def flow(&block)
          builder = FlowBuilder.new
          builder.instance_eval(&block)
          @flow_definition = builder.build
        end

        def flow_definition
          @flow_definition || []
        end
      end
    end
  end
end
```

### 1.2 Results Proxy (Dot Notation Access)

Replace hash access with method-based access that provides better errors.

**Current:**
```ruby
def process
  data = results[:enrich][:customer]  # Returns nil on typo
end
```

**New:**
```ruby
def process
  data = enrich.customer              # Raises clear error on typo

  # Also available:
  results.enrich.customer             # Explicit results prefix
  results[:enrich][:customer]         # Hash access still works
end
```

**Implementation:**

```ruby
class ResultsProxy
  def initialize(results_hash, workflow_class)
    @results = results_hash.transform_keys(&:to_sym)
    @workflow_class = workflow_class
    @available_steps = workflow_class.flow_definition.flat_map { |s|
      s[:type] == :parallel ? s[:steps] : s[:step]
    }
  end

  def [](key)
    @results[key.to_sym]
  end

  def method_missing(name, *)
    name = name.to_sym

    if @results.key?(name)
      wrap(@results[name])
    elsif @available_steps.include?(name)
      raise StepNotExecutedError,
        "Step :#{name} has not been executed yet.\n" \
        "Executed steps: #{@results.keys.join(', ')}\n" \
        "Hint: Check your flow declaration order."
    else
      raise UndefinedStepError,
        "Unknown step :#{name} in #{@workflow_class.name}.\n" \
        "Available steps: #{@available_steps.join(', ')}"
    end
  end

  def respond_to_missing?(name, *)
    @results.key?(name.to_sym) || @available_steps.include?(name.to_sym)
  end

  private

  def wrap(value)
    case value
    when Hash then ResultsProxy.new(value, @workflow_class)
    when RubyLLM::Agents::Result then wrap(value.content)
    else value
    end
  end
end

# Make step results available as instance methods
class Workflow
  private

  def method_missing(name, *)
    if results.respond_to?(name)
      results.send(name)
    else
      super
    end
  end

  def respond_to_missing?(name, *)
    results.respond_to?(name) || super
  end
end
```

### 1.3 Input Contract

Strong parameter-style input validation with method access.

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  input do
    required :order_id, String, desc: "The order ID to process"
    required :user_id, Integer
    optional :priority, String, default: "normal", in: %w[low normal high]
    optional :options, Hash, default: {}

    validate :order_id, ->(v) { v.start_with?("ORD-") }, "must start with ORD-"
  end

  def validate
    # Access via input object
    agent ValidatorAgent, order_id: input.order_id
  end
end
```

**Implementation:**

```ruby
class InputSchema
  Field = Struct.new(:name, :type, :required, :default, :validations, :desc, keyword_init: true)

  def initialize
    @fields = {}
  end

  def required(name, type, desc: nil, **validations)
    @fields[name] = Field.new(
      name: name, type: type, required: true,
      default: nil, validations: validations, desc: desc
    )
  end

  def optional(name, type, default: nil, desc: nil, **validations)
    @fields[name] = Field.new(
      name: name, type: type, required: false,
      default: default, validations: validations, desc: desc
    )
  end

  def validate(name, validator, message)
    @fields[name].validations[:custom] ||= []
    @fields[name].validations[:custom] << { validator: validator, message: message }
  end

  def validate!(data)
    errors = []
    validated = {}

    @fields.each do |name, field|
      value = data[name]

      # Required check
      if field.required && value.nil?
        errors << "#{name} is required"
        next
      end

      # Apply default
      value = field.default.is_a?(Proc) ? field.default.call : field.default if value.nil?
      next if value.nil?

      # Type check
      unless value.is_a?(field.type)
        errors << "#{name} must be a #{field.type}, got #{value.class}"
        next
      end

      # Inclusion check
      if field.validations[:in] && !field.validations[:in].include?(value)
        errors << "#{name} must be one of: #{field.validations[:in].join(', ')}"
      end

      # Custom validations
      field.validations[:custom]&.each do |custom|
        unless custom[:validator].call(value)
          errors << "#{name} #{custom[:message]}"
        end
      end

      validated[name] = value
    end

    raise InputValidationError.new(errors) if errors.any?
    InputProxy.new(validated)
  end
end

class InputProxy
  def initialize(data)
    @data = data
  end

  def [](key)
    @data[key.to_sym]
  end

  def to_h
    @data.dup
  end

  def method_missing(name, *)
    if @data.key?(name.to_sym)
      @data[name.to_sym]
    else
      raise NoMethodError, "Unknown input field: #{name}"
    end
  end

  def respond_to_missing?(name, *)
    @data.key?(name.to_sym)
  end
end
```

### 1.4 Output Contract

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  output do
    required :status, String, in: %w[success failed]
    required :order_id, String
    optional :tracking_number, String
    optional :error, String
  end

  def finalize
    {
      status: "success",
      order_id: input.order_id,
      tracking_number: store.tracking
    }
  end

  def on_failure(error, failed_step)
    {
      status: "failed",
      order_id: input.order_id,
      error: "#{failed_step}: #{error.message}"
    }
  end
end
```

---

## Phase 2: Step Metadata & Control

### 2.1 Step Declaration with Metadata

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  # Simple description
  step :validate, "Validate order data and inventory"
  def validate
    agent ValidatorAgent
  end

  # Full metadata block
  step :process do
    desc "Process the validated order"
    timeout 2.minutes
    retry_on Timeout::Error, max: 3, backoff: :exponential
    critical  # Workflow fails if this fails
  end
  def process
    agent ProcessorAgent
  end

  # Shorthand options
  step :notify, "Send notifications", timeout: 30.seconds, optional: true
  def notify
    agent NotificationAgent
  end
end
```

**Implementation:**

```ruby
class StepMetadata
  attr_accessor :description, :timeout, :retries, :retry_errors,
                :backoff, :critical, :optional

  def initialize
    @retries = 0
    @retry_errors = [StandardError]
    @backoff = :none
    @critical = false
    @optional = false
  end

  def desc(text)
    @description = text
  end

  def timeout(duration)
    @timeout = duration
  end

  def retry_on(*errors, max: 3, backoff: :none)
    @retry_errors = errors.flatten
    @retries = max
    @backoff = backoff
  end

  def critical
    @critical = true
  end

  def optional
    @optional = true
  end
end

class_methods do
  def step(name, description = nil, **options, &block)
    metadata = StepMetadata.new
    metadata.desc(description) if description
    metadata.timeout(options[:timeout]) if options[:timeout]
    metadata.optional if options[:optional]

    if block_given?
      metadata.instance_eval(&block)
    end

    @step_metadata ||= {}
    @step_metadata[name] = metadata
  end

  def step_metadata
    @step_metadata || {}
  end
end
```

### 2.2 Step Control Methods

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  def enrich
    # Skip with reason (logged, continues to next step)
    skip! "Customer already cached" if customer_cached?

    agent EnricherAgent
  end

  def process
    # Halt entire workflow (success, no error)
    halt! status: :already_processed if already_processed?

    # Fail entire workflow (error)
    fail! "Invalid state detected" if invalid_state?

    agent ProcessorAgent
  end

  def external_call
    result = ExternalService.call

    # Retry current step
    retry! "Transient error, retrying" if result.transient_failure?

    result
  end
end
```

**Implementation:**

```ruby
class Workflow
  class SkipStep < StandardError
    attr_reader :reason
    def initialize(reason); @reason = reason; end
  end

  class HaltWorkflow < StandardError
    attr_reader :result
    def initialize(result); @result = result; end
  end

  class FailWorkflow < StandardError; end
  class RetryStep < StandardError; end

  private

  def skip!(reason = nil)
    throw :skip_step, { skipped: true, reason: reason }
  end

  def halt!(result = {})
    throw :halt_workflow, result
  end

  def fail!(message)
    raise FailWorkflow, message
  end

  def retry!(reason = nil)
    raise RetryStep, reason
  end
end
```

---

## Phase 3: Debugging & Tracing

### 3.1 Execution Trace

```ruby
result = OrderWorkflow.call(order_id: "ORD-123")

# Access trace
result.trace
# => [
#   { step: :validate, status: :success, duration_ms: 45, agent: "ValidatorAgent" },
#   { step: :enrich, status: :skipped, reason: "Customer cached", duration_ms: 2 },
#   { step: :process, status: :success, duration_ms: 230, agent: "ProcessorAgent" },
# ]

# Visual timeline
puts result.timeline
# ┌─────────────────────────────────────────────────────────────────┐
# │ OrderWorkflow #wf_abc123 (277ms total)                          │
# ├─────────────────────────────────────────────────────────────────┤
# │ :validate    ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  45ms ✓  │
# │ :enrich      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   2ms ⊘  │
# │ :process     ░░░░████████████████████░░░░░░░░░░░░░░░░ 230ms ✓  │
# └─────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```ruby
class WorkflowTrace
  StepTrace = Struct.new(:step, :status, :duration_ms, :agent, :error, :reason, keyword_init: true)

  def initialize(workflow_id)
    @workflow_id = workflow_id
    @steps = []
    @start_time = nil
    @end_time = nil
  end

  def start!
    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def finish!
    @end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def record(step:, status:, duration_ms:, agent: nil, error: nil, reason: nil)
    @steps << StepTrace.new(
      step: step, status: status, duration_ms: duration_ms,
      agent: agent, error: error, reason: reason
    )
  end

  def to_a
    @steps.map(&:to_h)
  end

  def total_duration_ms
    ((@end_time - @start_time) * 1000).round if @end_time && @start_time
  end

  def timeline
    max_name_length = @steps.map { |s| s.step.to_s.length }.max
    bar_width = 40

    lines = []
    lines << "┌#{'─' * 65}┐"
    lines << "│ #{@workflow_id} (#{total_duration_ms}ms total)".ljust(65) + "│"
    lines << "├#{'─' * 65}┤"

    @steps.each do |step|
      ratio = step.duration_ms.to_f / total_duration_ms
      filled = (ratio * bar_width).round
      bar = '█' * filled + '░' * (bar_width - filled)
      status_icon = { success: '✓', skipped: '⊘', failed: '✗' }[step.status]

      line = "│ :#{step.step.to_s.ljust(max_name_length)} #{bar} #{step.duration_ms.to_s.rjust(4)}ms #{status_icon} │"
      lines << line
    end

    lines << "└#{'─' * 65}┘"
    lines.join("\n")
  end
end
```

### 3.2 Debug Hooks

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  # Class-level debug mode
  debug_mode Rails.env.development?

  # Custom hooks
  on_step_start do |step_name, input|
    Rails.logger.debug "[#{workflow_id}] Starting :#{step_name}"
  end

  on_step_complete do |step_name, result, duration_ms|
    Rails.logger.debug "[#{workflow_id}] Completed :#{step_name} in #{duration_ms}ms"
  end

  on_step_error do |step_name, error|
    Sentry.capture_exception(error, extra: {
      workflow_id: workflow_id,
      step: step_name
    })
  end
end

# Per-call debug
OrderWorkflow.call(order_id: "123", __debug: true)
```

### 3.3 Rich Error Messages

```ruby
class StepExecutionError < StandardError
  attr_reader :step_name, :workflow_class, :workflow_id,
              :original_error, :input_snapshot, :results_snapshot

  def initialize(step_name:, workflow:, original_error:)
    @step_name = step_name
    @workflow_class = workflow.class.name
    @workflow_id = workflow.workflow_id
    @original_error = original_error
    @input_snapshot = workflow.input.to_h
    @results_snapshot = workflow.results.to_h

    super(build_message)
  end

  def build_message
    <<~MSG

      ═══════════════════════════════════════════════════════════════
      Step :#{step_name} failed in #{workflow_class}
      ═══════════════════════════════════════════════════════════════

      Error: #{original_error.class} - #{original_error.message}

      Workflow ID: #{workflow_id}

      Input:
      #{format_hash(input_snapshot, indent: 2)}

      Results at failure:
      #{format_results}

      Trace:
      #{format_trace}

      Original backtrace:
        #{original_error.backtrace.first(8).join("\n    ")}

      ═══════════════════════════════════════════════════════════════
    MSG
  end

  private

  def format_hash(hash, indent: 0)
    hash.map { |k, v| "#{' ' * indent}#{k}: #{v.inspect}" }.join("\n")
  end

  def format_results
    results_snapshot.map do |step, result|
      status = step == step_name ? '✗' : '✓'
      "  #{status} :#{step}"
    end.join("\n")
  end

  def format_trace
    # Would use actual trace from workflow
    "  (trace available via error.workflow_trace)"
  end
end
```

### 3.4 Dry Run Mode

```ruby
# Validate flow without executing agents
result = OrderWorkflow.dry_run(order_id: "ORD-123")

# => {
#   valid: true,
#   input_valid: true,
#   steps: [:validate, :enrich, :process, :notify],
#   agents: ["ValidatorAgent", "EnricherAgent", "ProcessorAgent", "NotificationAgent"],
#   parallel_groups: [[:process, :analyze]],
#   estimated_cost: nil,  # If cost estimation is available
#   warnings: []
# }

# Implementation
class_methods do
  def dry_run(**input)
    # Validate input
    input_result = begin
      input_schema&.validate!(input)
      { valid: true, errors: [] }
    rescue InputValidationError => e
      { valid: false, errors: e.errors }
    end

    # Analyze flow
    steps = flow_definition.flat_map do |item|
      case item[:type]
      when :sequential then item[:step]
      when :parallel then item[:steps]
      end
    end

    agents = steps.map do |step_name|
      step_metadata[step_name]&.agent || infer_agent(step_name)
    end.compact

    {
      valid: input_result[:valid],
      input_valid: input_result[:valid],
      input_errors: input_result[:errors],
      steps: steps,
      agents: agents.map(&:name),
      parallel_groups: flow_definition.select { |i| i[:type] == :parallel }.map { |i| i[:steps] },
      warnings: collect_warnings
    }
  end
end
```

---

## Phase 4: Testing Infrastructure

### 4.1 Test Helpers Module

```ruby
module RubyLLM::Agents::WorkflowTestHelpers
  extend ActiveSupport::Concern

  # Stub prior step results for isolated testing
  def stub_results(workflow, results_hash)
    proxy = ResultsProxy.new(results_hash, workflow.class)
    workflow.instance_variable_set(:@results_proxy, proxy)
  end

  # Stub a specific agent
  def stub_agent(agent_class)
    AgentStub.new(agent_class)
  end

  # Stub all agents in workflow
  def stub_all_agents(workflow, default_response: {})
    workflow.class.step_metadata.each do |step_name, metadata|
      agent = metadata.agent || workflow.class.send(:infer_agent, step_name)
      next unless agent

      allow(agent).to receive(:call).and_return(
        mock_result(default_response)
      )
    end
  end

  # Create a mock result object
  def mock_result(content, success: true)
    RubyLLM::Agents::Result.new(
      success: success,
      content: content.is_a?(Hash) ? content : { value: content },
      agent_class: "MockAgent",
      duration_ms: 1
    )
  end

  # Run workflow up to (and including) a specific step
  def run_until(workflow, step_name)
    workflow.call(__until: step_name)
  end

  # Run a single step with provided context
  def run_step(workflow, step_name, context: {})
    stub_results(workflow, context)
    workflow.send(step_name)
  end

  class AgentStub
    def initialize(agent_class)
      @agent_class = agent_class
      @stub = nil
    end

    def to_return(content, success: true)
      @stub = allow(@agent_class).to receive(:call).and_return(
        RubyLLM::Agents::Result.new(
          success: success,
          content: content,
          agent_class: @agent_class.name,
          duration_ms: 1
        )
      )
      self
    end

    def to_raise(error)
      allow(@agent_class).to receive(:call).and_raise(error)
      self
    end

    def with(expected_args)
      @stub&.with(hash_including(expected_args))
      self
    end
  end
end
```

### 4.2 Example Test Patterns

```ruby
RSpec.describe OrderWorkflow do
  include RubyLLM::Agents::WorkflowTestHelpers

  let(:valid_input) { { order_id: "ORD-123", user_id: 1 } }
  let(:workflow) { described_class.new(**valid_input) }

  # ─────────────────────────────────────────────────────────────
  # Input Validation Tests
  # ─────────────────────────────────────────────────────────────

  describe "input validation" do
    it "requires order_id" do
      expect { described_class.new(user_id: 1) }
        .to raise_error(InputValidationError, /order_id is required/)
    end

    it "validates order_id format" do
      expect { described_class.new(order_id: "BAD", user_id: 1) }
        .to raise_error(InputValidationError, /must start with ORD-/)
    end

    it "applies defaults" do
      wf = described_class.new(**valid_input)
      expect(wf.input.priority).to eq("normal")
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Individual Step Tests
  # ─────────────────────────────────────────────────────────────

  describe "#validate" do
    it "calls ValidatorAgent with order_id" do
      stub_agent(ValidatorAgent)
        .to_return(valid: true, order: { id: "ORD-123" })
        .with(order_id: "ORD-123")

      result = workflow.validate

      expect(result.content[:valid]).to be true
    end
  end

  describe "#enrich" do
    before do
      stub_results(workflow,
        validate: { customer_id: "cust_1", valid: true }
      )
    end

    it "fetches customer data from validate result" do
      stub_agent(EnricherAgent)
        .to_return(customer: { name: "John", tier: "premium" })
        .with(customer_id: "cust_1")

      result = workflow.enrich

      expect(result.content[:customer][:tier]).to eq("premium")
    end

    it "skips when customer is cached" do
      allow(workflow).to receive(:customer_cached?).and_return(true)

      expect(EnricherAgent).not_to receive(:call)

      expect { workflow.enrich }.to throw_symbol(:skip_step)
    end
  end

  describe "#process" do
    context "when customer is premium" do
      before do
        stub_results(workflow,
          validate: { valid: true },
          enrich: { customer: { tier: "premium" } }
        )
      end

      it "uses PremiumAgent" do
        expect(PremiumAgent).to receive(:call)
        expect(StandardAgent).not_to receive(:call)

        workflow.process
      end
    end

    context "when customer is standard" do
      before do
        stub_results(workflow,
          validate: { valid: true },
          enrich: { customer: { tier: "standard" } }
        )
      end

      it "uses StandardAgent" do
        expect(StandardAgent).to receive(:call)
        expect(PremiumAgent).not_to receive(:call)

        workflow.process
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Partial Workflow Tests
  # ─────────────────────────────────────────────────────────────

  describe "partial execution" do
    it "can run up to a specific step" do
      stub_all_agents(workflow)

      result = workflow.call(__until: :enrich)

      expect(result.trace.map { |t| t[:step] }).to eq([:validate, :enrich])
      expect(result.results[:process]).to be_nil
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Full Workflow Tests
  # ─────────────────────────────────────────────────────────────

  describe "full workflow" do
    before { stub_all_agents(workflow) }

    it "executes all steps in order" do
      result = workflow.call

      expect(result).to be_success
      expect(result.trace.map { |t| t[:step] })
        .to eq([:validate, :enrich, :process, :notify])
    end

    it "returns expected output structure" do
      result = workflow.call

      expect(result.content).to include(
        status: "success",
        order_id: "ORD-123"
      )
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Error Handling Tests
  # ─────────────────────────────────────────────────────────────

  describe "error handling" do
    it "captures step failures in trace" do
      stub_agent(ValidatorAgent).to_return(valid: true)
      stub_agent(EnricherAgent).to_raise(Timeout::Error.new("timeout"))

      result = workflow.call

      expect(result).to be_failure
      expect(result.failed_step).to eq(:enrich)
      expect(result.error).to be_a(Timeout::Error)
    end

    it "retries on configured errors" do
      stub_agent(ValidatorAgent).to_return(valid: true)

      call_count = 0
      allow(EnricherAgent).to receive(:call) do
        call_count += 1
        raise Timeout::Error if call_count < 3
        mock_result(customer: {})
      end

      result = workflow.call

      expect(call_count).to eq(3)
      expect(result).to be_success
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Dry Run Tests
  # ─────────────────────────────────────────────────────────────

  describe ".dry_run" do
    it "validates input without executing" do
      result = described_class.dry_run(**valid_input)

      expect(result[:valid]).to be true
      expect(result[:steps]).to eq([:validate, :enrich, :process, :notify])
    end

    it "reports input errors" do
      result = described_class.dry_run(order_id: "BAD", user_id: 1)

      expect(result[:valid]).to be false
      expect(result[:input_errors]).to include(/must start with ORD-/)
    end
  end
end
```

---

## Phase 5: Composable Concerns

### 5.1 Standard Concerns

```ruby
# lib/ruby_llm/agents/workflow/concerns/auditable.rb
module RubyLLM::Agents::Workflow::Concerns::Auditable
  extend ActiveSupport::Concern

  included do
    before_workflow :create_audit_record
    after_workflow :complete_audit_record
    on_step_complete :record_step_audit
  end

  private

  def create_audit_record
    @audit = WorkflowAudit.create!(
      workflow_class: self.class.name,
      workflow_id: workflow_id,
      input: input.to_h.except(*sensitive_input_fields),
      started_at: Time.current
    )
  end

  def complete_audit_record
    @audit&.update!(
      completed_at: Time.current,
      status: @workflow_result&.success? ? :completed : :failed,
      output: @workflow_result&.content&.except(*sensitive_output_fields)
    )
  end

  def record_step_audit(step_name, result, duration_ms)
    @audit&.step_records&.create!(
      step_name: step_name,
      status: result.success? ? :success : :failed,
      duration_ms: duration_ms
    )
  end

  def sensitive_input_fields
    []  # Override in workflow
  end

  def sensitive_output_fields
    []  # Override in workflow
  end
end

# lib/ruby_llm/agents/workflow/concerns/measurable.rb
module RubyLLM::Agents::Workflow::Concerns::Measurable
  extend ActiveSupport::Concern

  included do
    around_workflow :measure_total_duration
    on_step_complete :record_step_metrics
  end

  private

  def measure_total_duration
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    record_workflow_metric(duration * 1000)
  end

  def record_workflow_metric(duration_ms)
    metric_name = "workflow.#{self.class.name.underscore}.duration"
    StatsD.timing(metric_name, duration_ms) if defined?(StatsD)
  end

  def record_step_metrics(step_name, _result, duration_ms)
    metric_name = "workflow.#{self.class.name.underscore}.step.#{step_name}"
    StatsD.timing(metric_name, duration_ms) if defined?(StatsD)
  end
end

# lib/ruby_llm/agents/workflow/concerns/notifiable.rb
module RubyLLM::Agents::Workflow::Concerns::Notifiable
  extend ActiveSupport::Concern

  included do
    class_attribute :notification_config, default: {}

    after_workflow :send_completion_notification, if: :should_notify?
    on_step_error :send_error_notification
  end

  class_methods do
    def notify_on_complete(channel:, **options)
      self.notification_config = { channel: channel, **options }
    end
  end

  private

  def should_notify?
    notification_config[:channel].present?
  end

  def send_completion_notification
    NotificationService.send(
      channel: notification_config[:channel],
      message: "#{self.class.name} completed",
      data: build_notification_data
    )
  end

  def send_error_notification(step_name, error)
    return unless notification_config[:notify_errors]

    NotificationService.send(
      channel: notification_config[:error_channel] || notification_config[:channel],
      message: "#{self.class.name} failed at :#{step_name}",
      data: { error: error.message, step: step_name, workflow_id: workflow_id }
    )
  end

  def build_notification_data
    {
      workflow_id: workflow_id,
      status: @workflow_result&.status,
      duration_ms: @trace&.total_duration_ms
    }
  end
end
```

### 5.2 Usage

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  include Concerns::Auditable
  include Concerns::Measurable
  include Concerns::Notifiable

  notify_on_complete channel: :slack, notify_errors: true

  flow do
    run :validate
    run :process
  end

  def validate
    agent ValidatorAgent
  end

  def process
    agent ProcessorAgent
  end

  private

  def sensitive_input_fields
    [:credit_card, :ssn]
  end
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── workflow.rb                           # Base class (enhanced)
├── workflow/
│   ├── dsl/
│   │   ├── flow_builder.rb               # Flow declaration DSL
│   │   ├── step_metadata.rb              # Step configuration
│   │   ├── input_schema.rb               # Input validation
│   │   └── output_schema.rb              # Output validation
│   ├── execution/
│   │   ├── executor.rb                   # Main execution engine
│   │   ├── step_runner.rb                # Individual step execution
│   │   └── parallel_runner.rb            # Parallel step execution
│   ├── results/
│   │   ├── results_proxy.rb              # Dot notation access
│   │   ├── input_proxy.rb                # Input access
│   │   └── workflow_result.rb            # Final result object
│   ├── debugging/
│   │   ├── trace.rb                      # Execution trace
│   │   ├── timeline.rb                   # Visual timeline
│   │   └── rich_errors.rb                # Enhanced error messages
│   ├── testing/
│   │   ├── helpers.rb                    # RSpec helpers
│   │   └── agent_stub.rb                 # Agent stubbing
│   ├── concerns/
│   │   ├── auditable.rb
│   │   ├── measurable.rb
│   │   └── notifiable.rb
│   └── errors.rb                         # Custom error classes
```

---

## Implementation Order

### Sprint 1: Core DSL (Week 1-2)
1. Flow builder (`flow do` block with `run`)
2. Results proxy (dot notation access)
3. Input schema and validation
4. Basic step execution

### Sprint 2: Step Features (Week 3-4)
5. Step metadata DSL
6. Step control methods (`skip!`, `halt!`, `fail!`)
7. Retry logic per step
8. Output schema

### Sprint 3: Debugging (Week 5-6)
9. Execution trace
10. Visual timeline
11. Rich error messages
12. Debug hooks
13. Dry run mode

### Sprint 4: Testing (Week 7-8)
14. Test helpers module
15. Agent stubbing
16. Partial execution (`__until:`)
17. Isolated step testing

### Sprint 5: Concerns & Polish (Week 9-10)
18. Auditable concern
19. Measurable concern
20. Notifiable concern
21. Documentation and examples

---

## Migration Path

All changes are **backwards compatible**. Existing workflows continue to work:

```ruby
# Old style - still works
class OldWorkflow < RubyLLM::Agents::Workflow::Pipeline
  step :process, agent: ProcessorAgent
end

# New style - opt-in to new features
class NewWorkflow < RubyLLM::Agents::Workflow
  flow do
    run :process
  end

  input do
    required :text, String
  end

  step :process, "Process the input"
  def process
    agent ProcessorAgent
  end
end
```

---

## Success Criteria

1. **All existing tests pass** - Zero breaking changes
2. **Steps are testable in isolation** - Can call `workflow.step_name` directly
3. **Clear error messages** - Include context, trace, and suggestions
4. **Visual debugging** - Timeline and trace available on every result
5. **IDE support** - Autocomplete works for `input.field` and `step_name.field`
6. **Documentation** - YARD docs for all public methods
7. **Performance** - <5% overhead vs current implementation
