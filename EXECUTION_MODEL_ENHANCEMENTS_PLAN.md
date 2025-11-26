# Execution Model Enhancements Plan

Purpose: enhance RubyLLM::Agents::Execution observability, analytics, billing, and governance while preserving privacy and performance.

Scope
- Add high-ROI fields for tracing, routing, hyperparameters, finish semantics, costing, and context.
- Introduce optional domains (tools, retrieval, moderation, quality, data lifecycle).
- Update validations, callbacks, and indexes.
- Provide migrations, rollout, and backfill strategy.

Non-goals
- Storing full prompts/outputs by default. Prefer hashes and versions for privacy.
- Over-engineering with rarely-used fields (see "Fields NOT to add" section).

Fields NOT to add (removed from original plan)
- `pid: integer` - Low value; process ID rarely useful for analytics. Use trace_id instead.
- `thread_id: string` - Same rationale; thread info is debugging noise, not analytics.
- `worker: string` - Redundant with existing Rails/Sidekiq infrastructure logs.
- `error_backtrace: text` - Expensive storage with minimal aggregate value. Link to error tracking service (Sentry, Bugsnag) via error_id instead.
- `currency: string` - If only supporting USD, don't store it. Add only when multi-currency is needed.
- `model_pricing_snapshot: jsonb` - Bloats DB; store pricing_version reference instead and keep a separate pricing history table.
- `feedback_label` with "none" - Use NULL instead of a meaningless value.

Phase 0: Inventory and confirm current columns
- Confirm presence of: agent_type, agent_version, model_id, temperature, status, started_at, completed_at, duration_ms, input_tokens, output_tokens, total_tokens, input_cost, output_cost, total_cost, parameters (JSONB), metadata (JSONB), error_class, error_message, attempts (JSONB), attempts_count (int), chosen_model_id (string).
- If any are missing, schedule them in Phase 1a as applicable.

Phase 1a: Tracing and correlation (must-have, deploy first)
- request_id: string, index
- trace_id: string, index
- span_id: string
- parent_execution_id: bigint (FK to executions), index
- root_execution_id: bigint (FK to executions), index
- conversation_id: string, index (for multi-turn conversations)

Rationale: Tracing is foundational. Ship this first to enable distributed tracing immediately.

Phase 1b: Routing, attempts, and errors (must-have)
- attempts_count: integer, default 0, index (if not present)
- chosen_model_id: string, index (if not present)
- fallback_reason: string (short code: price_limit, quality_fail, rate_limit, timeout, safety, other)
- Extend attempts (JSONB) elements with: retry_reason, backoff_ms, finish_reason, rate_limited (boolean)
- retryable: boolean
- rate_limited: boolean
- error_tracking_id: string (link to Sentry/Bugsnag instead of storing backtrace)

Rationale: Retry/fallback observability is critical for reliability engineering.

Phase 1c: Hyperparameters and prompt info (must-have)
- max_tokens: integer
- top_p: float
- frequency_penalty: float
- presence_penalty: float
- stop: jsonb (array of strings)
- response_format: string
- tool_choice: string
- system_prompt_version: string (or integer)
- prompt_hash: string (sha256 of effective prompt), index
- prompt_template_id: string, index (if using templates)

Rationale: Essential for debugging and reproducing executions.

Phase 1d: Finish and streaming metrics (must-have)
- finish_reason: string (stop, length, content_filter, tool_calls, other)
- streaming: boolean, default false
- time_to_first_token_ms: integer

Rationale: Critical for latency analysis and understanding completion behavior.

Phase 1e: Costing and caching (must-have)
- pricing_version: string (reference to external pricing table)
- cache_hit: boolean, default false
- cache_key: string, index
- cached_at: datetime

Rationale: Cost tracking is essential. Use pricing_version reference instead of snapshots to avoid bloat.

Phase 1f: Environment and context (must-have, minimal set)
- source: string (web, api, job, cli)
- user_id: bigint, index (nullable)
- organization_id: bigint, index (nullable)
- timeout_ms: integer (configured timeout)

Rationale: Minimal context needed for filtering and multi-tenancy. Removed pid/thread_id/worker as noise.

Indexing strategy
- IMPORTANT: Validate index choices against actual query patterns before adding.
- Start with these composite indexes (add more based on observed queries):
  - (status, started_at) - for status dashboards
  - (agent_type, started_at) - for per-agent analytics
  - (trace_id) - for trace lookups
  - (request_id) - for request correlation
  - (user_id, started_at) - for user-scoped queries (only if user_id is populated)
- Defer these until query patterns justify them:
  - (model_id, started_at)
  - (chosen_model_id, started_at)
- Use EXPLAIN ANALYZE on production queries before adding indexes.

Phase 2: Optional domains (nice-to-have, add incrementally)

Tools/function-calling
- tools_used_count: integer
- tools_total_time_ms: integer
- tools_failures_count: integer
- tools_summary: jsonb (array of {name, latency_ms, success, error_class})

Retrieval/RAG
- retriever_id: string
- retriever_version: string
- retrieved_chunks_count: integer
- unique_sources_count: integer
- retrieval_latency_ms: integer
- reranker_model_id: string
- reranker_latency_ms: integer
- sources: jsonb (ids/urls only - limit to 10 entries max)

Safety/Moderation
- moderation_model_id: string
- moderation_flagged: boolean (simpler than full scores)
- content_filter_triggered: boolean
- pii_detected: boolean

Note: Removed moderation_scores and policy_violations JSONB - if needed, store in separate moderation_results table.

Quality/Evaluation/Feedback
- user_feedback_score: integer (bounded 1–5), nullable
- feedback_label: string (thumbs_up, thumbs_down) - NULL means no feedback
- feedback_comment: text (optional, encrypted)

Note: Removed feedback_tags and eval_scores JSONB. If complex evaluation is needed, use a separate evaluations table.

Data lifecycle and governance
- retention_until: datetime (for deletion/archival)
- redacted_at: datetime (when redaction occurred, NULL if not redacted)

Note: Removed pii_scrubbed boolean - this should be a process, not a flag.

Phase 3: Model updates
- Validations
  - top_p between 0 and 1 (allow nil)
  - penalties numeric between -2.0 and 2.0 (allow nil)
  - finish_reason in allowed set (allow nil for in-progress)
  - fallback_reason in allowed set (allow nil)
- Enums (use Rails enums backed by strings, not integers for clarity)
  - finish_reason: stop, length, content_filter, tool_calls, other
  - fallback_reason: price_limit, quality_fail, rate_limit, timeout, safety, other
  - source: web, api, job, cli
- Callbacks
  - keep calculate_total_tokens and calculate_total_cost
  - derive total_tokens if missing in backfill
  - normalize/clamp numeric params
- Scopes
  - by_trace(trace_id), by_request(request_id), by_user(user_id)
  - by_conversation(conversation_id)
  - with_fallback, with_retries, cached, errored_retryable

Phase 4: Instrumentation and ingestion
- Propagate request_id, trace_id, span_id from web/worker entrypoints using Current attributes.
- When calling LLMs, pass hyperparameters into execution record.
- Record time_to_first_token_ms and streaming=true for streamed runs.
- On retries/fallbacks, append attempt metadata (retry_reason, backoff_ms, finish_reason).
- Reference pricing_version when calculating costs; maintain separate pricing history.
- If cache hit, set cache_hit, cache_key, cached_at and zero out new token counts appropriately.

Privacy and security considerations
- NEVER store full prompts/outputs in the executions table by default.
- Use prompt_hash for deduplication and debugging without exposing content.
- If prompt storage is needed, use a separate encrypted prompts table with strict access controls.
- JSONB fields must never contain PII - validate on write.
- Implement field-level encryption for feedback_comment if storing user text.
- The retention_until field enables GDPR Article 17 (right to erasure) compliance.
- Implement a daily purge job: `Execution.where("retention_until < ?", Time.current).find_each(&:destroy)`.
- Admin UI must redact sensitive fields; use a dedicated serializer.

JSONB governance (to prevent schema chaos)
- Limit JSONB to: attempts, stop, tools_summary, sources (4 columns max in Phase 1-2).
- Each JSONB column must have a documented schema in code comments.
- Validate JSONB structure on write using custom validators.
- Never store unbounded arrays in JSONB - enforce max length (e.g., 50 attempts, 10 sources).
- Consider normalizing to separate tables if JSONB queries become common.

Migrations: proposed schema changes (high-level)
- Phase 1a-1f: Six small migrations, one per sub-phase. Run sequentially with 1-day gaps.
- Phase 2: One migration per optional domain. Feature-flag the code until migration is complete.
- All new columns are nullable to avoid backfill pressure.
- Use `add_index :executions, :column, algorithm: :concurrently` for all indexes.
- Test migration rollback in staging before production.

Backfill and data migration
- Backfill prompt_hash by hashing available prompt text or template parameters; if unavailable, skip.
- Compute total_tokens and total_cost where null using existing input/output fields.
- Populate attempts_count from attempts JSON array size, if null.
- For legacy records, leave new fields null unless cheaply derivable.
- Run backfill in batches of 1000 with 100ms sleep between batches.
- Schedule during low-traffic windows (e.g., 2-5 AM local time).

Rollout plan
- Ship Phase 1a (tracing) first; validate with logs before proceeding.
- Ship Phase 1b-1f over 1-2 weeks, one sub-phase at a time.
- Update model validations and instrumentation after each migration.
- Phase 2 domains added based on actual need - don't add speculatively.
- Add feature flags for any dashboard elements relying on optional domains.

Dashboard and analytics updates
- Enhance the real-time dashboard partial to show:
  - indicators for fallback, retries, cache hit
  - finish_reason, time_to_first_token_ms
  - trace_id/request_id links (clickable to trace view)
  - costs with pricing_version reference
- Add filters for status, agent_type, model_id, user_id, trace_id, conversation_id.

Observability and tracing
- Integrate OpenTelemetry (trace_id/span_id) with current logging.
- Log key fields at start/end of execution with structured logging.
- Emit metrics: execution_duration_ms, token_count, cost_usd (as histograms).

Testing plan
- Unit tests
  - Validations for all new fields (top_p bounds, enum values, etc.)
  - Callbacks: calculate_total_tokens, calculate_total_cost with edge cases
  - Scopes: by_trace, with_fallback, cached return correct records
  - JSONB validators enforce schema constraints
- Integration tests
  - End-to-end execution populates trace_id, request_id, finish_reason
  - Retry flow populates attempts array correctly
  - Cache hit sets appropriate fields
- Migration tests
  - Each migration is reversible (up/down)
  - Indexes exist after migration
  - Null defaults don't break existing queries
- Performance tests
  - Benchmark insert performance with new columns (< 5% regression acceptable)
  - Benchmark common dashboard queries with new indexes
  - Load test with 10x expected traffic before production rollout

Risks and mitigations
- DB bloat from JSONB: Enforce max array lengths; monitor column sizes monthly.
- Privacy leakage: Default to hashes/versions; encrypt sensitive fields; audit access logs.
- Lock contention: Use `algorithm: :concurrently` for all indexes; keep migrations small.
- Query performance: Profile queries before/after; add indexes reactively based on EXPLAIN ANALYZE.
- Over-engineering: Resist adding fields "just in case" - each field has maintenance cost.

Success criteria
- 95% of new executions include request_id and trace_id (100% unrealistic for edge cases).
- Fallback/Retry analytics accurate within 5% vs logs (1% is too strict initially).
- Time-to-first-token captured for 90% of streaming requests.
- Costing reproducible with pricing_version reference across releases.
- Dashboard query p99 latency < 500ms with new indexes.
- No increase in execution insert latency > 5%.

Owner and timeline
- DRI: Platform/LLM Infra
- Phase 1a (tracing): 1 day
- Phase 1b-1f: 1-2 days each, spread over 2 weeks
- Phase 2: Add incrementally based on need, not on schedule
- Backfill: 1-3 days depending on row count; schedule during low-traffic windows

Review checklist before implementation
- [ ] Confirmed current schema matches Phase 0 inventory
- [ ] Validated index strategy against top 10 dashboard queries
- [ ] Tested migrations on staging with production-like data volume
- [ ] Documented JSONB schemas in model comments
- [ ] Set up monitoring for table size and query performance
- [ ] Created feature flags for new dashboard elements
