# RubyLLM::Agents – Retries/Fallbacks/Circuit Breakers and Governance Plan

Status: Draft (Revised)
Owner: Core Maintainers
Target Version: 0.3.x
Last Updated: 2025-11-26

---

## Architectural Corrections (Added After Code Review)

After reviewing the existing codebase implementation, the following critical corrections were identified:

### 1. Execution Flow Architecture (CRITICAL)

**Original (incorrect):** "Retry/fallback loop runs inline inside `Base#uncached_call`, governed by DSL options."

**Corrected:** The retry/fallback loop must WRAP `instrument_execution`, not run inside it. The current flow is:
- `call` → `uncached_call` → `instrument_execution { LLM call }`

If the retry loop ran inside `instrument_execution`, each retry would create a new execution record. Instead:
- Create a new `instrument_execution_with_attempts` method that creates ONE execution record
- The retry loop yields to an `AttemptTracker` that records attempts without creating new executions
- Only when all attempts complete (success or exhausted) does the execution record get finalized

### 2. Redaction Unification

**Original:** Proposed new redaction rules as a separate system.

**Corrected:** The codebase already has `sanitized_parameters` (instrumentation.rb:247-269) that removes sensitive keys:
```ruby
sensitive_keys = %i[password token api_key secret credential auth key]
```

The new `Redactor` module must:
- Extend (not replace) the existing sensitive_keys list
- Add configurable `redaction.fields` that merge with defaults
- Add pattern-based redaction on top of key-based removal

### 3. Cache Key with Fallback Models

**Original:** Not addressed.

**Corrected:** When model A fails and model B succeeds:
- Cache key remains based on the ORIGINALLY REQUESTED model (ensures consistency)
- Store `chosen_model_id` in execution to track which model actually responded
- This allows cache hits even if the fallback model was previously used

### 4. `dry_run` Mode Interaction

**Original:** Not mentioned.

**Corrected:** When `dry_run: true` is passed:
- Skip the entire reliability loop
- Return the dry_run_response immediately (existing behavior)
- Retries/fallbacks/circuit breakers do not apply to dry runs

### 5. Decisions Made

Based on implementation review:
- **Single execution with JSONB attempts** (confirmed) - one execution row, multiple attempts in array
- **Best-effort budget enforcement** - use cache counters (fast), accept slight overruns in race conditions
- **Per agent-model circuit breakers** - breaker scoped to specific agent+model combination

## Overview

This document proposes and details the implementation of two production-grade capabilities for RubyLLM::Agents:

1) Reliability
- Built-in retries with backoff and jitter
- Fallback model chains
- Circuit breaker (per agent/model) with rolling window and cooldown

2) Governance
- Global and per-agent budgets with soft/hard caps
- Alerts (Slack/Webhook/Custom proc) for thresholds and anomalies
- PII redaction policies for persisted prompts/parameters/responses

The goal is to keep the synchronous agent API intact while making executions more resilient and governable, and ensuring a trustworthy audit trail for every attempt.

---

## Goals

- Preserve the existing agent API: `MyAgent.call(params)` remains synchronous and blocks until success or failure.
- Log every attempt (retries and fallbacks) as part of the same execution record for complete cost and failure analysis.
- Provide a clean DSL and configuration for reliability and governance features.
- Keep backwards compatibility; defaults should not change current behavior unless explicitly configured.
- Keep initial implementation self-contained and database-compatible with current schema (JSONB attempts), with a path to normalization later if needed.

## Non-goals

- Full-blown workflow orchestration
- Batch scheduling or async execution of agent “calls”
- Provider-specific custom logic beyond model/fallback selection
- Streaming UI changes (streaming is future work; this plan is compatible with it)

---

## High-level Design

- Execution remains a single row in `ruby_llm_agents_executions`, with a new `attempts` JSONB array capturing per-attempt details.
- **CORRECTED:** Retry/fallback loop runs via `execute_with_reliability` which wraps `instrument_execution_with_attempts` (see Architectural Corrections above).
- Circuit breaker state uses the app cache (Rails.cache/Redis) for counters and “open” flags.
- Costs: sum across attempts using each attempt’s model pricing; total costs persisted on the execution row (for continuity with dashboard and analytics).
- Budgets: track and enforce in-process at call-time using configuration; raise or short-circuit when exceeding soft/hard caps.
- Alerts: fire notifications on budget exceedance, breaker open, and anomalous execution patterns; use adapters (Slack/Webhook/Custom).

---

## Public API (DSL and Configuration) – Proposal

### Reliability DSL (per-agent)
- `retries max:, backoff:, base:, max_delay:, on: []`
- `fallback_models [...]`
- `total_timeout seconds` (overall ceiling for retries+fallbacks)
- `circuit_breaker errors:, within:, cooldown:`

Example:
```ruby
class MyAgent < ApplicationAgent
  retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [Timeout::Error]
  fallback_models ["gpt-4o-mini", "gpt-4o"]
  total_timeout 20
  circuit_breaker errors: 10, within: 60, cooldown: 300
end
```

Notes:
- `backoff` accepted values: `:constant`, `:exponential`. Jitter added automatically.
- `on:` default includes timeout/network/transient provider errors. Agents can override.

### Governance Configuration (global)

Extend `RubyLLM::Agents.configure` with:

- Budgets:
  - `budgets.global_daily` Float (USD)
  - `budgets.global_monthly` Float (USD)
  - `budgets.per_agent_daily` Hash[String => Float]
  - `budgets.per_agent_monthly` Hash[String => Float]
  - `budgets.enforcement` Symbol: `:none | :soft | :hard`
    - `:soft` = allow but alert; `:hard` = raise and abort
- Alerts:
  - `alerts.slack_webhook_url` String | nil
  - `alerts.webhook_url` String | nil
  - `alerts.on_events` Array of symbols (e.g., `[:budget_soft_cap, :budget_hard_cap, :breaker_open]`)
  - `alerts.custom` -> Proc(event, payload)
- Redaction/Persistence:
  - `persist_prompts` Boolean (default true)
  - `persist_responses` Boolean (default true)
  - `redaction.fields` Array[String] (case-insensitive match on JSON keys)
  - `redaction.patterns` Array[Regexp] (apply to string values)
  - `redaction.placeholder` String, default `"[REDACTED]"`
  - `redaction.max_value_length` Integer (truncate very long strings before persisting)
  - `encrypt_prompts` / `encrypt_responses`: Optional pluggable encryptor interface in future

Example:
```ruby
RubyLLM::Agents.configure do |c|
  c.budgets = {
    global_daily: 25.0,
    global_monthly: 300.0,
    per_agent_daily: { "ContentAgent" => 5.0 },
    per_agent_monthly: { "ContentAgent" => 120.0 },
    enforcement: :soft
  }

  c.alerts = {
    slack_webhook_url: ENV["SLACK_WEBHOOK"],
    webhook_url: ENV["AGENTS_WEBHOOK"],
    on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open],
    custom: ->(event, payload) { Rails.logger.info("[Agents Alert] #{event}: #{payload.inspect}") }
  }

  c.persist_prompts = true
  c.persist_responses = true
  c.redaction = {
    fields: %w[password api_key access_token email phone ssn],
    patterns: [/\b\d{3}-\d{2}-\d{4}\b/], # SSN
    placeholder: "[REDACTED]",
    max_value_length: 5000
  }
end
```

---

## Data Model Changes

Phase 1 (JSONB approach – faster ship)
- Add columns to `ruby_llm_agents_executions`:
  - `attempts` JSONB NOT NULL DEFAULT []  (each attempt is a hash)
  - `attempts_count` integer NOT NULL DEFAULT 0
  - `chosen_model_id` string NULL
  - `fallback_chain` JSONB NOT NULL DEFAULT []

Indexes:
- `attempts_count`
- `chosen_model_id`

Attempt schema (example):
```json
{
  "model_id": "gpt-4o-mini",
  "started_at": "2025-11-26T12:00:00Z",
  "completed_at": "2025-11-26T12:00:02Z",
  "duration_ms": 2000,
  "input_tokens": 1234,
  "output_tokens": 4321,
  "cached_tokens": 0,
  "error_class": null,
  "error_message": null,
  "short_circuited": false
}
```

Phase 2 (optional, later)
- Normalize attempts into `ruby_llm_agents_execution_attempts` with FK to executions for richer analytics and indexing.

Migration Strategy
- Provide an upgrade generator that checks for existing columns and creates them if missing.

---

## Reliability Implementation Details

### Retry + Fallback Loop

- **CORRECTED:** Entry point is `Base#uncached_call` which delegates to `execute_with_reliability` when reliability features are enabled. This method wraps `instrument_execution_with_attempts` which creates a SINGLE execution record and tracks attempts via `AttemptTracker`.
- Before first attempt, check circuit breaker state; if open, record a "short_circuited" attempt and raise with `CircuitBreakerOpenError`.
- Build a list of models to try: `[self.class.model, *self.class.fallback_models].uniq`.
- For each model:
  - Set retries_remaining = `self.class.retries[:max]`.
  - Attempt request in a loop:
    - Track attempt `started_at`.
    - Execute the call with per-attempt timeout (use `Timeout.timeout(self.class.timeout)` as today).
    - On success:
      - `capture_response(response)`.
      - Append attempt with metrics to `attempts` and persist partial attempts to the execution row.
      - Recompute totals across attempts and persist `chosen_model_id` and cost aggregates.
      - Return processed response.
    - On error:
      - Append failed attempt with error details.
      - Persist partial attempts and increment circuit breaker failure counter (see CB section).
      - If error is retryable AND retries_remaining > 0 AND not past `total_timeout`, compute backoff delay, sleep, decrement retries_remaining, and retry.
      - Otherwise break and move to next fallback model.
- If all models exhausted, raise last error.

Backoff
- `:constant` -> constant `base` seconds (with + jitter 0..base/2).
- `:exponential` -> `delay = [base * (2 ** attempt_index), max_delay].min + jitter`.

Retryable Errors
- Default list (timeouts, connection timeouts, provider 5xx).
- Extendable via `on: [...]` in DSL.
- Non-retryable errors (4xx validation) immediately break to next model.

### Circuit Breaker

State
- Use Rails.cache keys:
  - Count rolling window: `ruby_llm_agents:cb:cnt:{agent}:{model}`
  - Open flag: `ruby_llm_agents:cb:open:{agent}:{model}`
- On each failed attempt:
  - Increment count with TTL `within` seconds; if >= `errors`, set `open` with TTL `cooldown`.
- On each success:
  - Optional: reset counter to reduce false positives (not strictly required).
- At attempt start:
  - If `open` present, append “short_circuited” attempt (no tokens), persist, alert (optional), and raise immediately.

Alert
- When breaker transitions to open, fire `:breaker_open` alert with payload:
  - `agent`, `model_id`, `errors`, `within`, `cooldown`, `timestamp`.

---

## Governance Implementation Details

### Budgets

Counters
- Use Rails.cache counters to track spend for:
  - `global_daily`, `global_monthly`
  - `per_agent_daily[agent]`, `per_agent_monthly[agent]`
- Keys include dates for daily/monthly reset, e.g.:
  - `ruby_llm_agents:budget:global:YYYY-MM-DD`
  - `ruby_llm_agents:budget:global:YYYY-MM`
  - `ruby_llm_agents:budget:agent:{agent}:YYYY-MM-DD`
  - `ruby_llm_agents:budget:agent:{agent}:YYYY-MM`

Flow
- Pre-check (fast): If counters already exceed hard cap, abort before calling provider (save a “short_circuited” attempt with `error_class: "BudgetExceededError"` and zero tokens).
- Post-execution: After calculating costs for the final execution (sum of attempts), increment counters.
- If increment crosses soft/hard threshold:
  - Soft: allow execution but fire alert `:budget_soft_cap`.
  - Hard: error and raise `BudgetExceededError`. If we discover this post-facto (race), we still let the current execution finish but future executions will be blocked by pre-check.

Alert payload includes cap type, limit, new total, window (daily/monthly), agent type (if per agent).

Enforcement
- `:none` -> only track and emit alerts on request
- `:soft` -> alert when exceeding, no block
- `:hard` -> block new requests when over-cap

### Alerts

Adapters:
- Slack (Incoming Webhook): POST JSON with concise message including event and metadata.
- Webhook: POST JSON payload to configured URL (retry on failure with backoff or log warning).
- Custom Proc: `config.alerts.custom.call(event, payload)`

Events (non-exhaustive):
- `:budget_soft_cap`, `:budget_hard_cap`
- `:breaker_open`
- `:agent_anomaly` (reuse existing anomaly triggers)

### PII Redaction

Policy
- Apply redaction before persisting:
  - `parameters` (already sanitized; extend to use patterns)
  - `system_prompt`, `user_prompt` (if `persist_prompts`)
  - `response` (if `persist_responses`)
- Redaction rules:
  - Field-level: if JSON key in `redaction.fields` -> replace value with placeholder.
  - Pattern-level: if string value matches any `redaction.patterns`, replace matching segments with placeholder.
  - Truncation: if value length > `max_value_length`, truncate and append ellipsis.
- Avoid redacting numeric tokens unless matched by pattern (reduce false positives).
- Never log secrets in plain text; defaults include common key names.

Extensibility
- Provide a helper `Redactor.redact(obj, config)` used by Instrumentation.
- Future: plug-in encryptor for prompts/responses (if enabled).

---

## Persistence and Metrics

### Execution Row Updates

During attempts:
- Append attempt to `attempts` and update `attempts_count`.
- Persist `fallback_chain` for transparency.

On success:
- Aggregate tokens and costs across attempts; persist:
  - `input_tokens`, `output_tokens`, `total_tokens`
  - `input_cost`, `output_cost`, `total_cost`
  - `chosen_model_id` = model from last successful attempt
- Maintain existing `status` transitions managed by `instrument_execution`.

On failure / short-circuit:
- Final status remains `error` or `timeout` as today, with attempts recorded.

### Cost Aggregation

- For each successful attempt, compute cost using that attempt’s `model_id` pricing (RubyLLM pricing API).
- Sum across attempts; round to 6 decimals; update execution total fields.

---

## Dashboard Updates (Phase 1 minimal)

- Execution detail view:
  - Show attempts table: attempt index, model_id, status, duration, tokens, error (if any).
  - Show `chosen_model_id` and `attempts_count`.
- Agents show page:
  - Display breaker status per model (if any open) – lightweight indicator fetched from cache.
- Governance panel (optional in Phase 1):
  - Show current daily/monthly usage vs configured caps (read counters).

---

## Observability

- Wrap reliability loop with `ActiveSupport::Notifications`:
  - `agent.attempt.start` (payload: agent_type, model_id, attempt_index)
  - `agent.attempt.finish` (payload: duration_ms, tokens, success)
  - `agent.attempt.error` (payload: error_class, error_message)
  - `agent.breaker.open` (payload: agent_type, model_id)
  - `agent.budget.exceeded` (payload: scope, limit, total, enforcement)
- Optional OpenTelemetry spans (later): execution span with child spans per attempt.

---

## Edge Cases and Interactions

- Caching:
  - Cache only the final successful result. Do not cache errors.
  - Respect `skip_cache` as today.
- total_timeout:
  - Abort if wall-clock time exceeds total budget (raise and record last attempt).
- Streaming (future):
  - Attempts API is compatible; stream belongs to a single attempt. Retries/fallbacks would restart a stream (documented later).
- Providers returning partial token counts:
  - Store what’s available; costs computed best-effort.

---

## Backward Compatibility

- All new features are opt-in:
  - No retries/fallbacks/circuit breakers unless specified in agent.
  - No budgets unless configured.
  - Redaction defaults to current sanitization; adding fields/patterns enhances it without breaking behavior.
- Existing analytics continue to work; attempts enrich detail views.

---

## Security Considerations

- Redaction runs before persistence; do not rely solely on view-level filtering.
- Avoid leaking sensitive values to logs during alerts; sanitize payloads.
- Optionally sign webhook alerts (HMAC) in future iteration.
- Respect `persist_prompts`/`persist_responses` toggles for privacy in production.

---

## Testing Strategy

Unit
- Retry loop: verify retry counts, backoff timing (mock/simulated), fallback model order.
- Circuit breaker: open condition met, short-circuit on open, cooldown respected.
- Cost aggregation: multi-attempt sums across different models.
- Redaction: fields and regex patterns applied; truncation; edge cases.
- Budget counters: daily/monthly, soft vs hard enforcement behavior.

Integration
- End-to-end execution with configured retries and fallbacks; attempts persisted; final costs correct.
- Dashboard view shows attempts.
- Alerts triggered on breaker open and budgets exceeded (mock HTTP).

Performance
- Confirm minimal overhead in happy-path (no retries).
- Cache operations bounded and key TTLs set.

---

## Migration Plan

- Add an upgrade generator:
  - Creates migration to add `attempts`, `attempts_count`, `chosen_model_id`, `fallback_chain` if missing.
- Safe to run multiple times; generator checks prior existence.
- No data migration required; new fields default to empty.

---

## Rollout Plan

Phase 1 (0.3.0)
- DSL + inline attempt loop
- JSONB attempts persistence
- Circuit breaker with cache
- Budget counters and enforcement
- Alerts (Slack/Webhook/Custom)
- Redaction and persistence toggles
- Minimal dashboard updates (attempts table, breaker indicator)
- Docs + examples

Phase 2 (0.3.1+)
- Additional dashboard panels (budgets usage)
- More alert event types and templates
- Optional normalized attempts table generator
- OpenTelemetry integration

---

## Implementation Tasks

1) Core DSL and Config
- Add class methods to Base: `retries`, `fallback_models`, `total_timeout`, `circuit_breaker`.
- Extend global configuration for `budgets`, `alerts`, `persist_prompts`, `persist_responses`, `redaction`.

2) Schema and Generators
- Upgrade generator to add attempts-related columns.
- Documentation updates for generator usage.

3) Base changes
- **CORRECTED:** Implement `execute_with_reliability` that wraps `instrument_execution_with_attempts` (NOT inside it).
- Implement backoff helpers and retryable error checks.
- Circuit breaker helpers (cache keys, counters, open flag).
- Attempt persistence helpers (append and update via AttemptTracker).
- Aggregation of tokens and costs across attempts.

4) Instrumentation updates
- Include attempt partial updates safely.
- Integrate redactor before saving prompts/response.
- Invoke budget checks pre/post execution.

5) Governance
- Budget counters (increment/read with TTL) and enforcement.
- Alert adapters (Slack/Webhook/Custom).
- Redactor utility: field and regex-based redaction + truncation.

6) Dashboard/UI (minimal)
- Attempts list in execution view.
- Circuit breaker status indicator in agent page.

7) Tests
- Unit and integration as described.
- Mock HTTP clients for alerts.

8) Docs and Examples
- README and a dedicated section for Reliability and Governance.
- Example agents demonstrating features.

---

## Time Estimates (Rough)

- Core reliability loop + attempts persistence: 2–3 days
- Circuit breaker + alerts: 1.5–2 days
- Budgets + enforcement + counters: 1.5–2 days
- Redaction + persistence toggles: 1 day
- Generators + migrations + configs: 0.5–1 day
- Dashboard minimal updates: 1 day
- Tests + docs: 2–3 days

Total: ~10–12 engineering days for Phase 1

---

## Open Questions

- Should we reset circuit breaker failure counters on any success, or decay progressively? (Initial: on success, reset)
- Do we want a per-tenant budget dimension now or later? (Later; can be added via metadata + config)
- Should we support provider-level circuit breakers (not just model-level)? (Later)

---

## Appendix: Example Attempt Object

```json
{
  "model_id": "gemini-2.0-flash",
  "started_at": "2025-11-26T12:00:00Z",
  "completed_at": "2025-11-26T12:00:01Z",
  "duration_ms": 1023,
  "input_tokens": 950,
  "output_tokens": 1200,
  "cached_tokens": 0,
  "error_class": null,
  "error_message": null,
  "short_circuited": false
}
```

---

## Appendix: Example Alert Payloads

Breaker Open
```json
{
  "event": "breaker_open",
  "agent_type": "MyAgent",
  "model_id": "gpt-4o-mini",
  "errors": 10,
  "within": 60,
  "cooldown": 300,
  "timestamp": "2025-11-26T12:00:00Z"
}
```

Budget Exceeded (Soft)
```json
{
  "event": "budget_soft_cap",
  "scope": "global_daily",
  "limit": 25.0,
  "total": 25.7,
  "timestamp": "2025-11-26",
  "agent_type": "ContentAgent"
}
```

---

## Appendix: Redaction Rules Examples

- Fields: `["password", "api_key", "access_token", "email", "phone", "ssn"]`
- Patterns:
  - SSN: `/\b\d{3}-\d{2}-\d{4}\b/`
  - Email: `/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i`
  - Bearer token: `/Bearer\s+[A-Za-z0-9\.\-\_]+/`

Behavior:
- Replace matches with `[REDACTED]`.
- Truncate string values longer than `max_value_length`.

---

End of document.

---

## Appendix: Corrected Code Flow

### Before (existing implementation)
```
Base.call(kwargs)
  → new(**kwargs).call
    → return dry_run_response if dry_run
    → return uncached_call if skip_cache || !cache_enabled?
    → cache_store.fetch(cache_key, expires_in: ttl) { uncached_call }
      → uncached_call:
        → instrument_execution {
            Timeout.timeout(timeout) {
              response = client.ask(user_prompt)
              process_response(capture_response(response))
            }
          }
```

### After (with reliability features)
```
Base.call(kwargs)
  → new(**kwargs).call
    → return dry_run_response if dry_run
    → return uncached_call if skip_cache || !cache_enabled?
    → cache_store.fetch(cache_key, expires_in: ttl) { uncached_call }
      → uncached_call:
        → if reliability_enabled?
            execute_with_reliability
          else
            instrument_execution { execute_single_attempt }
          end

execute_with_reliability:
  → check_budget! (pre-check)
  → instrument_execution_with_attempts(models_to_try) { |attempt_tracker|
      models_to_try.each do |model|
        → if circuit_breaker_open?(model)
            attempt_tracker.record_short_circuit(model)
            next
          end
        → retries_remaining = max_retries
        → loop do
            attempt = attempt_tracker.start_attempt(model)
            begin
              result = execute_single_attempt(model: model)
              attempt_tracker.complete_attempt(attempt, success: true)
              record_budget_spend!
              return result
            rescue *retryable_errors => e
              attempt_tracker.complete_attempt(attempt, success: false, error: e)
              circuit_breaker_failure!(model)
              if retries_remaining > 0 && !past_deadline?
                retries_remaining -= 1
                sleep(backoff_delay)
              else
                break  # try next model
              end
            rescue => e
              attempt_tracker.complete_attempt(attempt, success: false, error: e)
              break  # try next model
            end
          end
      end
      raise last_error  # all models exhausted
    }
```

### Key Classes

```ruby
# AttemptTracker - tracks attempts during execution
class AttemptTracker
  attr_reader :attempts
  def start_attempt(model_id) → Hash
  def complete_attempt(attempt, success:, response: nil, error: nil) → void
  def record_short_circuit(model_id) → void
  def successful_attempt → Hash or nil
  def total_tokens → Integer
end

# CircuitBreaker - cache-based breaker
class CircuitBreaker
  def initialize(agent_type, model_id, config)
  def open? → Boolean
  def record_failure! → void
  def record_success! → void
  def reset! → void
end

# BudgetTracker - cache-based budget tracking
class BudgetTracker
  def check_budget!(agent_type) → void (raises BudgetExceededError)
  def record_spend!(agent_type, amount) → void
  def current_spend(scope, period) → Float
  def remaining_budget(scope, period) → Float or nil
end

# Redactor - unified redaction utility
class Redactor
  def self.redact(obj, config = nil) → Object
  def self.redact_string(str, config = nil) → String
end

# AlertManager - notification dispatcher
class AlertManager
  def self.notify(event, payload) → void
end
```
