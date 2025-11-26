# Execution Model Enhancements Plan

Purpose: enhance RubyLLM::Agents::Execution observability and analytics while preserving privacy and performance.

Guiding principle: Only add fields that provide clear, immediate value. Costs are already calculated and stored.

Non-goals
- Storing full prompts/outputs by default
- Speculative fields for "future use"
- Complex JSONB structures for niche use cases

Phase 0: Inventory current columns
Confirm presence of: agent_type, agent_version, model_id, temperature, status, started_at, completed_at, duration_ms, input_tokens, output_tokens, total_tokens, input_cost, output_cost, total_cost, parameters (JSONB), metadata (JSONB), error_class, error_message, attempts (JSONB), attempts_count (int), chosen_model_id (string).

Phase 1a: Tracing (high impact - enables distributed tracing)
- request_id: string, index
- trace_id: string, index
- span_id: string
- parent_execution_id: bigint (FK to executions), index
- root_execution_id: bigint (FK to executions), index

Why: Links executions across services. Essential for debugging production issues.

Phase 1b: Routing and retries (high impact - reliability insights)
- fallback_reason: string (price_limit, quality_fail, rate_limit, timeout, safety, other)
- retryable: boolean
- rate_limited: boolean

Why: Understand why fallbacks happen and which errors are retryable.

Phase 1c: Finish and streaming (high impact - latency analysis)
- finish_reason: string (stop, length, content_filter, tool_calls, other)
- streaming: boolean, default false
- time_to_first_token_ms: integer

Why: Critical for understanding completion behavior and user-perceived latency.

Phase 1d: Caching (medium impact - cost savings visibility)
- cache_hit: boolean, default false
- cache_key: string, index
- cached_at: datetime

Why: Track cache effectiveness and cost savings.

Phase 1e: Context (medium impact - filtering and multi-tenancy)
- source: string (web, api, job, cli)
- user_id: bigint, index (nullable)
- organization_id: bigint, index (nullable)

Why: Filter executions by source and enable per-user/org analytics.

Phase 2: Hyperparameters (lower priority - add if needed for debugging)
- max_tokens: integer
- top_p: float
- frequency_penalty: float
- presence_penalty: float
- prompt_hash: string (sha256 of effective prompt), index

Why: Useful for reproducing executions but not critical for day-to-day analytics.

Phase 3: Tools metrics (add only if using function calling heavily)
- tools_used_count: integer
- tools_total_time_ms: integer
- tools_failures_count: integer

Why: Understand tool call performance. Skip if tools are rarely used.

Indexing strategy
Start minimal, add based on actual query patterns:
- (trace_id) - trace lookups
- (request_id) - request correlation
- (status, started_at) - status dashboards
- (user_id, started_at) - only if user_id is populated

Use `algorithm: :concurrently` for all indexes.

Phase 4: Model updates
- Validations
  - finish_reason in allowed set (allow nil)
  - fallback_reason in allowed set (allow nil)
  - source in allowed set (allow nil)
- Scopes
  - by_trace(trace_id), by_request(request_id), by_user(user_id)
  - with_fallback, with_retries, cached

Phase 5: Instrumentation
- Propagate request_id, trace_id, span_id from web/worker entrypoints.
- Record time_to_first_token_ms and streaming=true for streamed runs.
- On retries/fallbacks, set fallback_reason.
- On cache hit, set cache_hit, cache_key, cached_at.

Migrations
- One migration per sub-phase (1a, 1b, 1c, 1d, 1e).
- All new columns nullable.
- Use concurrent indexes.
- Test rollback in staging.

Dashboard updates
- Show indicators for fallback, retries, cache hit
- Show finish_reason, time_to_first_token_ms
- Add trace_id/request_id links
- Add filters for status, agent_type, model_id, user_id, trace_id

Testing plan
- Unit tests for validations and scopes
- Integration tests for instrumentation populating fields
- Migration reversibility tests

Success criteria
- 95% of new executions include trace_id
- Time-to-first-token captured for 90% of streaming requests
- Dashboard queries p99 < 500ms

Rollout
- Phase 1a-1e: Ship one sub-phase at a time over 1-2 weeks
- Phase 2-3: Add only when actually needed
- Validate each phase before proceeding to next
