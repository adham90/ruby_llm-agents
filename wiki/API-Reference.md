# API Reference

Complete class and method documentation for RubyLLM::Agents.

## RubyLLM::Agents::Base

The base class for all agents. Supports two DSL styles: Simplified (recommended) and Traditional.

### Class Methods — Core Settings

#### `.model(name)`

Set the LLM model.

```ruby
model "gpt-4o"
```

#### `.temperature(value)`

Set response randomness (0.0-2.0).

```ruby
temperature 0.7
```

#### `.timeout(seconds)`

Set request timeout.

```ruby
timeout 60
```

#### `.description(text)`

Document agent purpose (displayed in dashboard).

```ruby
description "Extracts search intent from user queries"
```

#### `.aliases(*names)`

Declare previous class names for execution tracking continuity.

```ruby
aliases "OldAgentName", "AncientAgentName"
```

#### `.all_agent_names`

Returns all known names (current + aliases).

```ruby
SupportBot.all_agent_names
# => ["SupportBot", "CustomerSupportAgent", "HelpDeskAgent"]
```

#### `.streaming(boolean)`

Enable/disable streaming.

```ruby
streaming true
```

#### `.thinking(effort:, budget:)`

Enable extended thinking for supported models.

```ruby
thinking effort: :high, budget: 10000
```

### Class Methods — Simplified DSL (v2.0+)

#### `.user(template)` / `.user(&block)` (v2.2+)

Define the user prompt with `{placeholder}` syntax. Parameters are auto-registered as required.

```ruby
user "Search for {query} in {category}"
user { "Dynamic: #{some_method}" }
```

#### `.user_config` (v2.2+)

Hash of options applied to the user prompt (e.g. `cache_control`):

```ruby
user_config cache_control: { type: "ephemeral" }
```

#### `.prompt(template)` / `.prompt(&block)` (deprecated)

**Deprecated alias for `.user`.** Still works but emits a deprecation warning. Prefer `.user` in new code.

```ruby
# Deprecated -- use `user` instead
prompt "Search for {query} in {category}"
```

#### `.assistant(text)` / `.assistant(&block)` (v2.2+)

Pre-fill the assistant turn. Useful for forcing JSON output or steering the response format.

```ruby
assistant "{"
```

When an `assistant` prefill is set, the LLM continues from that text rather than generating from scratch. This is particularly effective for ensuring JSON output:

```ruby
class JsonExtractor < ApplicationAgent
  model "claude-sonnet-4-20250514"

  system "Extract entities as JSON."
  user   "{text}"
  assistant "{"

  returns do
    array :entities, of: :string
  end
end
```

#### `.assistant_config` (v2.2+)

Hash of options applied to the assistant prefill (e.g. `cache_control`):

```ruby
assistant_config cache_control: { type: "ephemeral" }
```

#### `.system(text)` / `.system(&block)`

Define system instructions.

```ruby
system "You are a helpful assistant."
```

#### `.ask(text, **params)` / `.ask(&block)` (v2.2+)

One-shot convenience method. Sends a user message, calls the agent, and returns the result -- all in one step. Ideal for quick, ad-hoc queries without defining a full agent class.

```ruby
# On any agent class
result = MyAgent.ask("Summarize this article: #{text}")

# With parameters
result = MyAgent.ask("Translate {text} to {language}", text: article, language: "French")

# Block form for dynamic prompts
result = MyAgent.ask { "Current time is #{Time.current}. What day is it?" }
```

`.ask` is equivalent to temporarily setting the `user` prompt and calling `.call`:

```ruby
# These are equivalent:
MyAgent.ask("Hello world")
MyAgent.call  # when `user "Hello world"` is set on the class
```

#### `.returns(&block)`

Define structured output schema (alias for `schema`).

```ruby
returns do
  string :title, description: "Article title"
  array :tags, of: :string
  number :confidence
  boolean :needs_review
end
```

#### `.on_failure(&block)`

Group all error handling (alias for `reliability`).

```ruby
on_failure do
  retries times: 3, backoff: :exponential
  fallback to: ["gpt-4o-mini", "claude-3-haiku"]
  timeout 30
  circuit_breaker after: 5, cooldown: 5.minutes
end
```

#### `.cache(for:, key:)`

Enable caching with keyword syntax.

```ruby
cache for: 1.hour
cache for: 30.minutes, key: [:query]
```

#### `.before(&block)` / `.after(&block)`

Simplified callbacks (block-only).

```ruby
before { |ctx| ctx.params[:timestamp] = Time.current }
after { |ctx, result| Analytics.track(result) }
```

### Class Methods — Traditional DSL

#### `.cache_for(duration)`

Enable response caching.

```ruby
cache_for 1.hour
```

#### `.param(name, options = {})`

Define a parameter.

```ruby
param :query, required: true
param :limit, default: 10
param :count, type: :integer
```

Options:
- `required: true` - Parameter must be provided
- `default: value` - Default value if not provided
- `type:` - Type validation (`:string`, `:integer`, `:float`, `:boolean`, `:array`, `:hash`)

#### `.tools(array)`

Register tools for the agent.

```ruby
tools [SearchTool, CalculatorTool]
```

#### `.retries(options)`

Configure retry behavior.

```ruby
retries max: 3, backoff: :exponential, base: 0.5, max_delay: 30.0
```

Options:
- `max:` - Maximum retry attempts
- `backoff:` - `:exponential` or `:constant`
- `base:` - Initial delay in seconds
- `max_delay:` - Maximum delay cap
- `on:` - Array of error classes to retry

#### `.fallback_models(*models)`

Set fallback model chain.

```ruby
fallback_models "gpt-4o-mini", "claude-3-haiku"
```

#### `.circuit_breaker(options)`

Configure circuit breaker.

```ruby
circuit_breaker errors: 10, within: 60, cooldown: 300
```

Options:
- `errors:` - Error count to trip breaker
- `within:` - Time window in seconds
- `cooldown:` - Cooldown period in seconds

#### `.total_timeout(seconds)`

Set maximum time for all attempts.

```ruby
total_timeout 30
```

#### `.reliability(&block)`

Block DSL for reliability configuration.

```ruby
reliability do
  retries max: 3, backoff: :exponential
  fallback_models "gpt-4o-mini"
  total_timeout 30
  circuit_breaker errors: 10, within: 60, cooldown: 300
end
```

#### `.before_call` / `.after_call`

Full callback API with method names or blocks.

```ruby
before_call :validate_input
after_call { |context, response| log(response) }
```

#### `.call(**params, &block)`

Execute the agent.

```ruby
result = MyAgent.call(query: "test")
result = MyAgent.call(query: "test", dry_run: true)
result = MyAgent.call(query: "test", skip_cache: true)
result = MyAgent.call(query: "test", with: "image.jpg")
```

#### `.stream(**params, &block)`

Execute with streaming.

```ruby
MyAgent.stream(query: "test") { |chunk| print chunk.content }
```

### Instance Methods

#### `#call`

Execute the agent (called by `.call`).

#### `#system_prompt` — Traditional (override)

Override to define system prompt. **Prefer the class-level `system` DSL instead** (see [Simplified DSL](#class-methods--simplified-dsl-v20) above).

```ruby
# Preferred — class-level DSL
system "You are a helpful assistant."

# Traditional — instance method override
def system_prompt
  "You are a helpful assistant."
end
```

#### `#user_prompt` — Traditional (override)

Override to define user prompt. **Prefer the class-level `user` DSL instead** (see [Simplified DSL](#class-methods--simplified-dsl-v20) above).

```ruby
# Preferred — class-level DSL (v2.2+)
user "Process: {query}"

# Traditional — instance method override
def user_prompt
  "Process: #{query}"
end
```

#### `#assistant_prompt` — Traditional (override) (v2.2+)

Override to define assistant prefill. **Prefer the class-level `assistant` DSL instead** (see [Simplified DSL](#class-methods--simplified-dsl-v20) above).

```ruby
# Preferred — class-level DSL (v2.2+)
assistant "{"

# Traditional — instance method override
def assistant_prompt
  "{"
end
```

#### `#schema` (private)

Override to define structured output.

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result
  end
end
```

#### `#process_response(response)` (private)

Override to post-process response.

```ruby
def process_response(response)
  result = super(response)
  result[:processed_at] = Time.current
  result
end
```

#### `#metadata` (private)

Override to add custom metadata.

```ruby
def metadata
  { user_id: user_id }
end
```

#### `#cache_key_data` (private)

Override to customize cache key.

```ruby
def cache_key_data
  { query: query }
end
```

---

## RubyLLM::Agents::Result

Returned by agent calls.

### Content Access

```ruby
result.content            # Parsed response
result.content[:key]      # Hash-style access (recommended)
result.content.dig(:a, :b)
result[:key]              # Deprecated, use content[:key]
```

### Token Information

```ruby
result.input_tokens   # Input token count
result.output_tokens  # Output token count
result.total_tokens   # Total tokens
result.cached_tokens  # Cached tokens
```

### Cost Information

```ruby
result.input_cost     # Input cost (USD)
result.output_cost    # Output cost (USD)
result.total_cost     # Total cost (USD)
```

### Model Information

```ruby
result.model_id       # Requested model
result.chosen_model_id # Actual model used
result.temperature    # Temperature setting
```

### Timing Information

```ruby
result.duration_ms    # Execution duration
result.started_at     # Start timestamp
result.completed_at   # End timestamp
result.time_to_first_token_ms # TTFT (streaming)
```

### Status Information

```ruby
result.success?       # Did it succeed?
result.finish_reason  # "stop", "length", etc.
result.streaming?     # Was streaming used?
result.truncated?     # Was output truncated?
```

### Reliability Information

```ruby
result.attempts_count # Number of attempts
result.used_fallback? # Was fallback used?
```

### Tool Calls

```ruby
result.tool_calls     # Array of tool calls
result.tool_calls_count
result.has_tool_calls?
```

### Thinking Information

```ruby
result.thinking_text      # Reasoning content
result.thinking_tokens    # Tokens used for thinking
result.thinking_signature # Multi-turn signature (Claude)
result.has_thinking?      # Whether thinking was used
```

### Error Information

```ruby
result.success?       # true if no error
result.error?         # true if errored
result.error_class    # Exception class name
result.error_message  # Exception message
```

### Full Data

```ruby
result.to_h           # All data as hash
```

---

## RubyLLM::Agents::Execution

ActiveRecord model for execution records.

### Scopes

```ruby
# Time-based
.today
.yesterday
.this_week
.this_month
.last_7_days
.last_30_days
.between(start, finish)

# Status
.successful
.failed
.status_error
.status_timeout
.status_running

# Agent/Model
.by_agent("AgentName")
.by_model("gpt-4o")

# Performance
.expensive(threshold)
.slow(milliseconds)
.high_token_usage(count)

# Streaming
.streaming
.non_streaming
```

### Attributes

```ruby
execution.agent_type      # String
execution.model_id        # String
execution.status          # String: success, error, timeout
execution.input_tokens    # Integer
execution.output_tokens   # Integer
execution.cached_tokens   # Integer
execution.input_cost      # Decimal
execution.output_cost     # Decimal
execution.total_cost      # Decimal
execution.duration_ms     # Integer
execution.parameters      # Hash (JSONB)
execution.system_prompt   # Text
execution.user_prompt     # Text
execution.response        # Text
execution.error_message   # Text
execution.error_class     # String
execution.metadata        # Hash (JSONB)
execution.streaming       # Boolean
execution.time_to_first_token_ms # Integer (from metadata JSON)
execution.attempts        # Array (JSONB, from execution_details)
execution.chosen_model_id # String
execution.finish_reason   # String
execution.created_at      # DateTime
```

### Class Methods

```ruby
# Reports
Execution.daily_report
Execution.cost_by_agent(period: :today)
Execution.cost_by_model(period: :this_week)
Execution.stats_for("AgentName", period: :today)
Execution.trend_analysis(agent_type: "Agent", days: 7)

# Analytics
Execution.streaming_rate
Execution.avg_time_to_first_token
```

---

## RubyLLM::Agents::BudgetTracker

Budget management.

```ruby
# Check status
BudgetTracker.status
BudgetTracker.status(agent_type: "MyAgent")

# Check remaining
BudgetTracker.remaining_budget(:global, :daily)
BudgetTracker.remaining_budget(:per_agent, :daily, "MyAgent")

# Check exceeded
BudgetTracker.exceeded?(:global, :daily)
```

---

## RubyLLM::Agents::CircuitBreaker

Circuit breaker management.

```ruby
# Check status
CircuitBreaker.status("gpt-4o")
# => { state: :open, errors: 10, closes_at: Time }

# Manual control
CircuitBreaker.open!("gpt-4o")
CircuitBreaker.close!("gpt-4o")
CircuitBreaker.reset_all!
```

---

## RubyLLM::Agents.configure

Global configuration. As of v2.1.0, this is the single entry point for all settings, including LLM provider API keys.

```ruby
RubyLLM::Agents.configure do |config|
  # API Keys (v2.1+ — forwarded to RubyLLM automatically)
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.gemini_api_key = ENV["GOOGLE_API_KEY"]

  # Defaults
  config.default_model = "gpt-4o"
  config.default_temperature = 0.0
  config.default_timeout = 60
  config.default_streaming = false

  # Caching
  config.cache_store = Rails.cache

  # Logging
  config.async_logging = true
  config.retention_period = 30.days
  config.persist_prompts = true
  config.persist_responses = true

  # Anomaly Detection
  config.anomaly_cost_threshold = 5.00
  config.anomaly_duration_threshold = 10_000

  # Dashboard
  config.dashboard_auth = ->(c) { c.current_user&.admin? }
  config.dashboard_parent_controller = "ApplicationController"
  config.per_page = 25

  # Budgets
  config.budgets = {
    global_daily: 100.0,
    enforcement: :hard
  }

  # Alerts
  config.on_alert = ->(event, payload) {
    # Handle alerts (Slack, PagerDuty, etc.)
  }
end
```

See [Configuration](Configuration) for the full list of options including all 22 forwarded provider attributes.

---

## RubyLLM::Agents.rename_agent

Rename an agent in the database, updating execution records and tenant budget keys.

```ruby
# Rename permanently
RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent")
# => { executions_updated: 1432, tenants_updated: 3 }

# Dry run (no changes)
RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent", dry_run: true)
# => { executions_affected: 1432, tenants_affected: 3 }
```

Parameters:
- `old_name` (String) — The previous agent class name
- `to:` (String) — The new agent class name
- `dry_run:` (Boolean, default: false) — If true, returns counts without modifying data

---

## RubyLLM::Agents::DSL::Queryable

Module extended into all agent classes via `BaseAgent`. Provides class methods for querying execution history.

### `.executions`

Returns an `ActiveRecord::Relation` scoped to this agent's executions.

```ruby
SearchAgent.executions
SearchAgent.executions.successful.today
```

### `.last_run`

Returns the most recent execution.

```ruby
SearchAgent.last_run
# => #<RubyLLM::Agents::Execution ...>
```

### `.failures(since: 24.hours)`

Returns recent failed executions within the time window.

```ruby
SearchAgent.failures
SearchAgent.failures(since: 7.days)
```

### `.total_spent(since: nil)`

Returns total cost for this agent, optionally within a time window.

```ruby
SearchAgent.total_spent                 # => 12.50
SearchAgent.total_spent(since: 1.month) # => 3.25
```

### `.stats(since: nil)`

Returns a summary hash.

```ruby
SearchAgent.stats
# => { total:, successful:, failed:, success_rate:, avg_duration_ms:,
#      avg_cost:, total_cost:, total_tokens:, avg_tokens: }
```

### `.cost_by_model(since: nil)`

Returns cost breakdown grouped by model.

```ruby
SearchAgent.cost_by_model
# => { "gpt-4o" => { count: 100, total_cost: 5.00, avg_cost: 0.05 } }
```

### `.with_params(**params)`

Filters executions by parameter values in execution details.

```ruby
SearchAgent.with_params(user_id: "u123", category: "billing")
```

---

## RubyLLM::Agents::Execution::Replayable

Concern included in `Execution`. Adds replay capabilities.

### `#replay(model: nil, temperature: nil, **overrides)`

Re-executes the agent with original parameters. Accepts model/temperature overrides and parameter overrides.

```ruby
execution.replay
execution.replay(model: "gpt-4o-mini")
execution.replay(query: "new search term")
```

**Raises:** `RubyLLM::Agents::ReplayError` if the agent class is missing, detail record is absent, or `agent_type` is blank.

### `#replayable?`

Returns `true` if the execution has a valid agent class and detail record.

```ruby
execution.replayable?  # => true
```

### `#replay?`

Returns `true` if this execution is a replay of another.

```ruby
execution.replay?  # => false
```

### `#replay_source`

Returns the original execution this was replayed from, or `nil`.

```ruby
execution.replay_source  # => #<Execution ...> or nil
```

### `#replays`

Returns all executions that are replays of this one.

```ruby
execution.replays  # => ActiveRecord::Relation
```

---

## RubyLLM::Agents::Workflow

Base class for composing agents into multi-step workflows. Not a `BaseAgent` subclass — follows the `ImagePipeline` architectural pattern.

### Class Methods — DSL

#### `.step(name, agent_class, **options)`

Define a workflow step.

```ruby
step :research, ResearchAgent
step :draft, DraftAgent, after: :research, params: { tone: "formal" }
step :review, ReviewAgent, if: -> (ctx) { ctx[:needs_review] }
```

Options: `params:`, `after:`, `if:`, `unless:`

#### `.flow(chain)`

Declare sequential dependencies.

```ruby
flow :research >> :draft >> :edit
flow [:research, :draft, :edit]
```

#### `.pass(from_step, to:, as:)`

Map outputs from one step to inputs of another.

```ruby
pass :research, to: :draft, as: { notes: :content }
```

#### `.description(text)`

Set workflow description.

#### `.on_failure(strategy)`

Set error handling: `:stop` (default) or `:continue`.

#### `.budget(max_cost)`

Set maximum cost limit in USD.

#### `.dispatch(router_step, as: :handler, &block)`

Route to agents based on a classification step.

```ruby
dispatch :classify do |d|
  d.on :billing, agent: BillingAgent
  d.on_default agent: GeneralAgent
end
```

#### `.supervisor(agent_class, max_turns: 10)`

Configure a supervisor loop.

#### `.delegate(name, agent_class)`

Register a sub-agent for supervisor mode.

#### `.call(**params)`

Execute the workflow.

```ruby
result = ContentWorkflow.call(topic: "AI safety")
```

---

## RubyLLM::Agents::Workflow::WorkflowResult

Returned by `Workflow.call`. Aggregates results across all steps.

### Step Access

```ruby
result.step(:name)       # Agent Result for that step
result[:name]            # Same as step(:name)
result.final_result      # Last completed step's Result
result.content           # final_result.content
result.step_names        # [:research, :draft, :edit]
result.step_count        # 3
```

### Status

```ruby
result.success?              # All steps succeeded
result.error?                # Has errors
result.partial?              # Some succeeded, some failed
result.successful_step_count # Number of successful steps
result.failed_step_count     # Number of failed steps
```

### Cost Aggregation

```ruby
result.total_cost     # Sum of all step costs
result.input_cost     # Sum of input costs
result.output_cost    # Sum of output costs
```

### Token Aggregation

```ruby
result.total_tokens   # Sum of all tokens
result.input_tokens   # Sum of input tokens
result.output_tokens  # Sum of output tokens
```

### Timing

```ruby
result.duration_ms    # Wall-clock milliseconds
result.started_at     # Time
result.completed_at   # Time
```

### Serialization

```ruby
result.to_h  # Full hash representation
```

---

## Exceptions

```ruby
RubyLLM::Agents::BudgetExceededError  # Budget limit exceeded
RubyLLM::Agents::CircuitOpenError     # Circuit breaker is open
RubyLLM::Agents::ReplayError          # Replay validation failed
```

## Related Pages

- [Agent DSL](Agent-DSL) - DSL reference
- [Configuration](Configuration) - Configuration guide
- [Result Object](Result-Object) - Result details
- [Querying Executions](Querying-Executions) - Agent-centric queries and replay
