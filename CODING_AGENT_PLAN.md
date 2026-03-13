# Coding Agent Features — Implementation Plan

## Status Quo

The gem already has:

- **Tool DSL** — `tools [SomeTool]` on agents, resolved via `resolved_tools` in `BaseAgent`
- **Tool loop** — handled by RubyLLM's `Chat` object internally (tool_use → tool_result → continue)
- **Tool tracking** — `on_tool_call`/`on_tool_result` callbacks capture tool calls to `@tracked_tool_calls`, stored in `execution_details.tool_calls` as JSON
- **Agent-as-tool** — `AgentTool.for(agent_class)` wraps agent classes as `RubyLLM::Tool` subclasses
- **LLM response streaming** — `streaming true` DSL, `stream_block` on `Pipeline::Context`
- **Execution tracking** — full pipeline with `Instrumentation` middleware, `Execution` + `ExecutionDetail` models
- **Agent params** — `param` DSL defines named parameters, stored in `@options`, recorded in `execution_details.parameters`
- **Messages input** — `messages:` option or `#messages` method override allows passing conversation history
- **Thread-local context** — `BaseAgent#execute` already sets `Thread.current[:ruby_llm_agents_caller_context]` so AgentTool can access the pipeline context

What doesn't exist: tool base class with context access, per-tool timeouts, separate tool execution records, or cancellation.

### Key design decisions

1. **Work WITH RubyLLM's loop, don't replace it.** RubyLLM manages the tool loop (tool_use → execute → tool_result → repeat). We override `call()` on our Tool subclass to wrap each tool execution with our features. Zero loop duplication.

2. **Override `call()`, not `execute()`.** RubyLLM's flow: `tool.call(args)` → validates args → `tool.execute(**kwargs)`. Users implement `execute()` — the standard RubyLLM convention. We override `call()` and use `super` to get validation for free.

3. **`Tool::Halt` for loop control.** RubyLLM's `Halt` mechanism stops the tool loop gracefully. We use it for cancellation.

---

## Build Order

| Phase | Feature | Depends On |
|-------|---------|------------|
| 1 | [Tool Base Class](#phase-1--tool-base-class) | Nothing | **DONE** |
| 2 | [Tool Execution Tracking](#phase-2--tool-execution-tracking) | Phase 1 | **DONE** |
| 3 | [Cancellation](#phase-3--cancellation) | Phase 1 | **DONE** |

---

## Phase 1 — Tool Base Class

### Why

Tools need access to the agent's context (params, execution ID, tenant) and support for per-tool timeouts. RubyLLM's `Tool` has `description` and `param` DSL but no concept of the calling agent. We extend it.

### How it works

```
1. BaseAgent passes tool classes to RubyLLM via with_tools()
2. RubyLLM instantiates them (.new) and stores instances
3. BaseAgent sets Thread.current[:ruby_llm_agents_caller_context] = pipeline_context
4. Claude requests a tool → RubyLLM calls tool.call(args)
5. OUR call() override:
   a. Reads pipeline context from Thread.current
   b. Builds ToolContext (the `context` accessor)
   c. Wraps with timeout
   d. Calls super → RubyLLM validates args → calls execute(**kwargs) (user's code)
   e. Catches errors → returns error strings to Claude
6. Result goes back to RubyLLM → feeds it to Claude → loop continues
```

### What to build

**`RubyLLM::Agents::Tool`** — inherits from `RubyLLM::Tool`, overrides `call()`:

```ruby
class RubyLLM::Agents::Tool < RubyLLM::Tool
  # Inherits: description, param DSL, #name, #execute, #call
  # Adds: context accessor, timeout, error handling

  attr_reader :context

  class << self
    def timeout(value = nil)
      return @timeout unless value
      @timeout = value
    end
  end

  # RubyLLM's Chat calls tool.call(args).
  # We wrap it with our features, then super for validation + execute.
  def call(args)
    pipeline_context = Thread.current[:ruby_llm_agents_caller_context]
    @context = ToolContext.new(pipeline_context) if pipeline_context

    timeout = self.class.timeout
    timeout ||= RubyLLM::Agents.configuration.default_tool_timeout

    if timeout
      Timeout.timeout(timeout) { super }
    else
      super
    end
  rescue Timeout::Error
    "TIMEOUT: Tool did not complete within #{timeout}s."
  rescue RubyLLM::Agents::CancelledError
    raise  # Let cancellation propagate to BaseAgent
  rescue => e
    "ERROR (#{e.class}): #{e.message}"
  end
end
```

Users implement `execute()` — the standard RubyLLM way:

```ruby
class BashTool < RubyLLM::Agents::Tool
  description "Run a shell command"
  timeout 30

  param :command, desc: "The command to run", required: true

  def execute(command:)
    container_id = context.container_id  # method-style access
    tenant = context.tenant_id           # fixed attribute
    id = context[:some_key]              # hash-style also works

    # ... run command ...
    "output"
  end
end
```

**`RubyLLM::Agents::ToolContext`** — read-only wrapper around `Pipeline::Context`:

Supports both method-style (`context.container_id`) and hash-style (`context[:container_id]`) access to agent params.

```ruby
class RubyLLM::Agents::ToolContext
  def initialize(pipeline_context)
    @ctx = pipeline_context
    @agent_options = @ctx.agent_instance&.send(:options) || {}
  end

  # Hash-style access to agent params
  def [](key)
    @agent_options[key.to_sym] || @agent_options[key.to_s]
  end

  # Execution record ID — links tool calls to the agent execution
  def id
    @ctx.execution_id
  end

  def tenant_id
    @ctx.tenant_id
  end

  def agent_type
    @ctx.agent_class&.name
  end

  private

  # Method-style access to agent params: context.container_id
  def method_missing(method_name, *args)
    key = method_name.to_sym
    if @agent_options.key?(key) || @agent_options.key?(key.to_s)
      self[key]
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    key = method_name.to_sym
    @agent_options.key?(key) || @agent_options.key?(key.to_s) || super
  end
end
```

### Example

```ruby
class BashTool < RubyLLM::Agents::Tool
  description "Run a shell command"
  timeout 30

  param :command, desc: "The command to run", required: true

  def execute(command:)
    context.container_id  # reads agent param passed at call time
  end
end

class CodingAgent < ApplicationAgent
  param :container_id, required: true
  tools [BashTool]
end

CodingAgent.call(query: "list files", container_id: "abc123")
# → BashTool receives context.container_id == "abc123"
```

### What it touches

| Area | Change |
|------|--------|
| **New class** | `RubyLLM::Agents::Tool` — inherits `RubyLLM::Tool`, overrides `call()` |
| **New class** | `RubyLLM::Agents::ToolContext` — read-only context wrapper with method + hash access |
| **Configuration** | `config.default_tool_timeout` (default: nil) |

### Side effects

- **Backward compatible** — tools using plain `RubyLLM::Tool` still work unchanged. Only tools inheriting `RubyLLM::Agents::Tool` get the new features.
- **No BaseAgent changes** — the thread-local context pattern already exists for AgentTool. Our Tool just reads it too.
- **Users implement `execute()`** — the standard RubyLLM convention. No new method name to learn.
- **Errors don't kill the agent** — timeouts and exceptions become tool result strings. Claude sees the error and decides what to do. RubyLLM's `Chat#execute_tool` doesn't catch errors, so without our wrapper, any tool error would crash the entire agent.
- **`Tool::Halt` passes through** — if a tool returns `halt("message")`, it works correctly because `super` returns the `Halt` object and we don't convert it.
- **Arg validation is free** — `super` calls RubyLLM's `call()` which validates kwargs against the `execute()` method signature before calling it.

---

## Phase 2 — Tool Execution Tracking

### Why

The current `execution_details.tool_calls` JSON column stores tool calls as a flat array:

1. **No queryability** — can't find "all bash commands that took >10s" without parsing every execution's JSON
2. **No real-time tracking** — tool calls are stored after the agent finishes. During a long run, the dashboard shows nothing.
3. **No per-tool status** — can't see which tool is currently running

### What to build

A `ToolExecution` model with its own table, created/updated in real-time inside `Tool#call()`.

```ruby
class RubyLLM::Agents::ToolExecution < ActiveRecord::Base
  self.table_name = "ruby_llm_agents_tool_executions"

  belongs_to :execution, class_name: "RubyLLM::Agents::Execution"
end
```

### Schema

```ruby
create_table :ruby_llm_agents_tool_executions do |t|
  t.references :execution, null: false,
    foreign_key: { to_table: :ruby_llm_agents_executions, on_delete: :cascade }

  t.string   :tool_name,    null: false
  t.string   :tool_call_id                        # Claude's tool_use ID
  t.integer  :iteration,    null: false, default: 1
  t.string   :status,       null: false, default: "running"
  # statuses: running, success, error, timed_out, cancelled

  t.json     :input,        null: false, default: {}
  t.text     :output
  t.text     :error_message
  t.integer  :output_bytes, default: 0

  t.datetime :started_at
  t.datetime :completed_at
  t.integer  :duration_ms

  t.timestamps
end

add_index :ruby_llm_agents_tool_executions, [:execution_id, :iteration]
add_index :ruby_llm_agents_tool_executions, :tool_name
add_index :ruby_llm_agents_tool_executions, :status
```

### Integration with Tool#call()

Tracking wraps the existing call logic from Phase 1:

```ruby
def call(args)
  pipeline_context = Thread.current[:ruby_llm_agents_caller_context]
  @context = ToolContext.new(pipeline_context) if pipeline_context

  record = create_tool_execution_record(pipeline_context, args)

  timeout = self.class.timeout
  timeout ||= RubyLLM::Agents.configuration.default_tool_timeout

  result = if timeout
    Timeout.timeout(timeout) { super }
  else
    super
  end

  complete_tool_execution_record(record, result, status: "success")
  result
rescue Timeout::Error
  complete_tool_execution_record(record, nil, status: "timed_out", error: "Timed out after #{timeout}s")
  "TIMEOUT: Tool did not complete within #{timeout}s."
rescue RubyLLM::Agents::CancelledError
  complete_tool_execution_record(record, nil, status: "cancelled")
  raise
rescue => e
  complete_tool_execution_record(record, nil, status: "error", error: e.message)
  "ERROR (#{e.class}): #{e.message}"
end
```

### What it touches

| Area | Change |
|------|--------|
| **New model** | `RubyLLM::Agents::ToolExecution` |
| **New table** | `ruby_llm_agents_tool_executions` |
| **Execution model** | `has_many :tool_executions` |
| **Tool base class** | `call()` creates/updates records |
| **Migration template** | New migration |

### Side effects

- **New table** — additive. Existing users who don't use tools have an empty table.
- **Write amplification** — INSERT on start, UPDATE on complete per tool call. Tracking only happens for `RubyLLM::Agents::Tool` subclasses — plain `RubyLLM::Tool` is unaffected.
- **Data duplication** — tool calls exist in both `tool_executions` table and `execution_details.tool_calls` JSON. The JSON column stays for backward compatibility. The table is the source of truth when present.
- **Graceful without DB** — if there's no execution_id (e.g., tool used outside the pipeline), tracking is silently skipped.

---

## Phase 3 — Cancellation

### Why

Long-running agent executions with many tool calls need a way to stop cleanly.

### What to build

The gem accepts an `on_cancelled:` proc. The Tool base class checks it before executing.

```ruby
CodingAgent.call(
  query: "...",
  on_cancelled: -> { should_stop? }
)
```

### How it works

The `on_cancelled` proc is stored on `Pipeline::Context` metadata. The Tool checks it at the start of `call()`:

```ruby
# In RubyLLM::Agents::Tool#call()
def call(args)
  pipeline_context = Thread.current[:ruby_llm_agents_caller_context]
  @context = ToolContext.new(pipeline_context) if pipeline_context

  check_cancelled!(pipeline_context)

  # ... timeout, super, error handling ...
end

private

def check_cancelled!(pipeline_context)
  return unless pipeline_context
  on_cancelled = pipeline_context[:on_cancelled]
  return unless on_cancelled.respond_to?(:call)

  raise RubyLLM::Agents::CancelledError if on_cancelled.call
end
```

When `CancelledError` is raised:
1. It propagates through RubyLLM's loop back to `BaseAgent#execute`
2. `BaseAgent` catches it and returns a result with `cancelled? = true`

```ruby
# In BaseAgent#execute
def execute(context)
  # ... existing code ...
  response = execute_llm_call(client, context)
  # ...
rescue RubyLLM::Agents::CancelledError
  result = build_cancelled_result(context)
  context.output = result
end
```

### Cancellation flow

```
Tool loop (managed by RubyLLM):
  1. Claude requests BashTool
  2. RubyLLM calls tool.call(args)
  3. Our call() checks on_cancelled → not cancelled
  4. super runs → execute() runs → returns result
  5. RubyLLM feeds result to Claude
  6. Claude requests ReadFileTool
  7. RubyLLM calls tool.call(args)
  8. Our call() checks on_cancelled → CANCELLED
  9. Raises CancelledError
  10. Error propagates through RubyLLM back to BaseAgent
  11. BaseAgent catches it, returns Result with cancelled? = true
```

### What it touches

| Area | Change |
|------|--------|
| **Tool base class** | `call()` checks `on_cancelled` before running |
| **BaseAgent** | Catches `CancelledError` in `execute`, builds cancelled result |
| **New error** | `RubyLLM::Agents::CancelledError` |
| **Result** | `result.cancelled?` attribute |
| **Pipeline::Context** | Stores `on_cancelled` proc in metadata |

### Side effects

- **Graceful, not immediate** — checked before each tool call. A running tool finishes before cancellation takes effect. Per-tool timeouts (Phase 1) are the safety net for stuck tools.
- **Works only with `RubyLLM::Agents::Tool`** — plain `RubyLLM::Tool` subclasses don't check cancellation, so the loop continues until it hits one of our tools or finishes.
- **ToolExecution record** — if Phase 2 is active, the record gets status "cancelled".

---

## File map

```
New files:
  lib/ruby_llm/agents/tool.rb                               # Phase 1
  lib/ruby_llm/agents/tool_context.rb              # Phase 1
  app/models/ruby_llm/agents/tool_execution.rb               # Phase 2
  lib/generators/templates/add_tool_executions_migration.rb   # Phase 2

Modified files:
  lib/ruby_llm/agents/base_agent.rb                          # Phase 3 (catch CancelledError)
  lib/ruby_llm/agents/results/base.rb                        # Phase 3 (cancelled? attr)
  lib/ruby_llm/agents/core/configuration.rb                  # Phase 1 (default_tool_timeout)
  lib/ruby_llm/agents/core/errors.rb                         # Phase 3 (CancelledError)
  app/models/ruby_llm/agents/execution.rb                    # Phase 2 (has_many :tool_executions)
  spec/dummy/db/schema.rb                                    # Phase 2
```

---

## Risk summary

| Risk | Severity | Mitigation |
|------|----------|------------|
| Thread-local context not set (tool used outside pipeline) | Low | Graceful fallback — context accessor is nil, tracking skipped |
| Large tool outputs consume memory | Medium | Per-tool timeout; tools can cap their own output |
| CancelledError not caught by RubyLLM | Low | Error propagates cleanly through RubyLLM back to BaseAgent |
| Migration conflicts with existing installs | Low | Idempotent migration matching existing patterns |
| `Timeout.timeout` edge cases | Low | Document; tools doing heavy I/O should use own timeouts |
