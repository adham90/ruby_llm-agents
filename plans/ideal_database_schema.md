# Ideal Database Schema for ruby_llm-agents

This is the target schema — what the database should look like if we designed it from scratch with everything we've learned. It addresses the issues identified in the schema review while preserving all active business logic.

---

## Table 1: `ruby_llm_agents_executions`

The core analytics table. Kept lean — only columns that are queried, aggregated, or filtered. Large payloads moved to `execution_details`.

```ruby
create_table :ruby_llm_agents_executions do |t|
  # ── Agent identification ──
  t.string  :agent_type,       null: false              # "SearchAgent", "ContentAgent"
  t.string  :agent_version,    null: false, default: "1.0"
  t.string  :execution_type,   null: false, default: "chat"  # chat, embedding, moderation, image, audio

  # ── Model ──
  t.string  :model_id,         null: false              # "gpt-4o", "claude-sonnet-4-20250514"
  t.string  :model_provider                              # "openai", "anthropic"
  t.decimal :temperature,      precision: 3, scale: 2   # 0.00 - 2.00
  t.string  :chosen_model_id                             # If fallback used, which model succeeded

  # ── Status ──
  t.string  :status,           null: false, default: "running"  # running, success, error, timeout
  t.string  :finish_reason                               # stop, length, content_filter, tool_calls, other
  t.string  :error_class                                 # "RateLimitError", "TimeoutError"

  # ── Timing ──
  t.datetime :started_at,      null: false
  t.datetime :completed_at
  t.integer  :duration_ms

  # ── Token usage ──
  t.integer :input_tokens,     default: 0
  t.integer :output_tokens,    default: 0
  t.integer :total_tokens,     default: 0
  t.integer :cached_tokens,    default: 0

  # ── Cost (USD) ──
  t.decimal :input_cost,       precision: 12, scale: 6
  t.decimal :output_cost,      precision: 12, scale: 6
  t.decimal :total_cost,       precision: 12, scale: 6

  # ── Caching ──
  t.boolean :cache_hit,        default: false
  t.string  :response_cache_key                          # Cache lookup key

  # ── Streaming ──
  t.boolean :streaming,        default: false
  t.integer :time_to_first_token_ms                      # Only for streaming

  # ── Retry / Fallback ──
  t.integer :attempts_count,   default: 1, null: false
  t.boolean :retryable
  t.boolean :rate_limited
  t.string  :fallback_reason                             # price_limit, quality_fail, rate_limit, etc.

  # ── Tool calls ──
  t.integer :tool_calls_count, default: 0, null: false

  # ── Distributed tracing ──
  t.string  :request_id
  t.string  :trace_id
  t.string  :span_id

  # ── Execution hierarchy (self-join) ──
  t.bigint  :parent_execution_id
  t.bigint  :root_execution_id

  # ── Workflow ──
  t.string  :workflow_id
  t.string  :workflow_type                               # pipeline, parallel, router
  t.string  :workflow_step

  # ── Multi-tenancy ──
  t.string  :tenant_id

  # ── Conversation context ──
  t.integer :messages_count,   default: 0, null: false

  # ── Flexible storage (small, user-provided key-value data only) ──
  # For: trace context, custom tags, feature flags, request IDs
  # NOT for: prompts, responses, tool call payloads — those go in execution_details
  t.json    :metadata,         default: {}, null: false

  t.timestamps
end

# ── Indexes: only what's actually queried ──

# Primary query patterns (dashboard, listing, filtering)
add_index :ruby_llm_agents_executions, [:agent_type, :created_at]
add_index :ruby_llm_agents_executions, [:agent_type, :status]
add_index :ruby_llm_agents_executions, :status
add_index :ruby_llm_agents_executions, :created_at

# Tenant-scoped queries
add_index :ruby_llm_agents_executions, [:tenant_id, :created_at]
add_index :ruby_llm_agents_executions, [:tenant_id, :status]

# Tracing
add_index :ruby_llm_agents_executions, :trace_id
add_index :ruby_llm_agents_executions, :request_id

# Execution hierarchy
add_index :ruby_llm_agents_executions, :parent_execution_id
add_index :ruby_llm_agents_executions, :root_execution_id

# Workflow queries
add_index :ruby_llm_agents_executions, [:workflow_id, :workflow_step]
add_index :ruby_llm_agents_executions, :workflow_type

# Caching
add_index :ruby_llm_agents_executions, :response_cache_key

# Foreign keys
add_foreign_key :ruby_llm_agents_executions, :ruby_llm_agents_executions,
                column: :parent_execution_id, on_delete: :nullify
add_foreign_key :ruby_llm_agents_executions, :ruby_llm_agents_executions,
                column: :root_execution_id, on_delete: :nullify
```

**Column count: 39** (down from 68)

---

## Table 2: `ruby_llm_agents_execution_details`

Large/optional payloads that are stored for audit and display but never aggregated or filtered. One-to-one with executions, loaded on demand (execution detail page).

**This record is optional** — only created when there's data to store. Simple executions (e.g. embeddings with no prompts, response, or tool calls) don't need a detail row.

```ruby
create_table :ruby_llm_agents_execution_details do |t|
  t.references :execution, null: false,
               foreign_key: { to_table: :ruby_llm_agents_executions, on_delete: :cascade },
               index: { unique: true }

  # ── Error details ──
  t.text :error_message                                      # Full error message / stack trace

  # ── Prompts (audit trail) ──
  t.text :system_prompt
  t.text :user_prompt

  # ── Full response ──
  t.json :response,             default: {}

  # ── Conversation summary ──
  t.json :messages_summary,     default: {}, null: false    # First/last messages

  # ── Tool call details ──
  t.json :tool_calls,           default: [], null: false    # Full tool call payloads

  # ── Retry attempt details ──
  t.json :attempts,             default: [], null: false    # Per-attempt data
  t.json :fallback_chain                                     # Models tried in order

  # ── Agent parameters (redacted) ──
  t.json :parameters,           default: {}, null: false

  # ── Workflow routing ──
  t.string :routed_to                                        # Which agent was routed to
  t.json   :classification_result                            # Router classification data

  # ── Cache metadata ──
  t.datetime :cached_at
  t.integer  :cache_creation_tokens, default: 0

  t.timestamps
end
```

**Why separate:**
- `system_prompt` + `user_prompt` + `response` + `error_message` can be kilobytes each — keeping them out of the main table makes aggregation queries (`SUM`, `GROUP BY`, `COUNT`) scan much less data
- These are only loaded on the execution detail page, never in listings or dashboards
- Cascade delete means no orphans
- Optional creation avoids empty rows for simple executions

---

## Table 3: `ruby_llm_agents_tenants`

Tenant identity, budget config, and rolling counters for real-time budget enforcement.

```ruby
create_table :ruby_llm_agents_tenants do |t|
  # ── Identity ──
  t.string  :tenant_id,          null: false                # "acme_corp", "org_123"
  t.string  :name                                            # Human-readable display name
  t.boolean :active,             default: true, null: false
  t.json    :metadata,           default: {}, null: false   # Custom tenant data

  # ── Polymorphic link to user's model ──
  t.string  :tenant_record_type                              # "Organization", "Account"
  t.bigint  :tenant_record_id

  # ── Budget limits ──
  t.decimal :daily_limit,        precision: 12, scale: 6    # USD per day
  t.decimal :monthly_limit,      precision: 12, scale: 6    # USD per month
  t.bigint  :daily_token_limit                               # Tokens per day
  t.bigint  :monthly_token_limit                             # Tokens per month
  t.bigint  :daily_execution_limit                           # Executions per day
  t.bigint  :monthly_execution_limit                         # Executions per month
  t.json    :per_agent_daily,    default: {}, null: false      # { "SearchAgent" => 5.0 }
  t.json    :per_agent_monthly,  default: {}, null: false      # { "SearchAgent" => 120.0 }
  t.string  :enforcement,        default: "soft", null: false  # none, soft, hard
  t.boolean :inherit_global_defaults, default: true, null: false

  # ── Rolling counters (atomic increment, lazy reset) ──
  t.decimal :daily_cost_spent,        precision: 12, scale: 6, default: 0, null: false
  t.decimal :monthly_cost_spent,      precision: 12, scale: 6, default: 0, null: false
  t.bigint  :daily_tokens_used,       default: 0, null: false
  t.bigint  :monthly_tokens_used,     default: 0, null: false
  t.bigint  :daily_executions_count,  default: 0, null: false
  t.bigint  :monthly_executions_count, default: 0, null: false
  t.bigint  :daily_error_count,       default: 0, null: false
  t.bigint  :monthly_error_count,     default: 0, null: false

  # ── Last execution snapshot ──
  t.datetime :last_execution_at
  t.string   :last_execution_status                          # success, error, timeout

  # ── Period tracking (for lazy reset) ──
  t.date :daily_reset_date
  t.date :monthly_reset_date

  t.timestamps
end

add_index :ruby_llm_agents_tenants, :tenant_id, unique: true
add_index :ruby_llm_agents_tenants, :active
add_index :ruby_llm_agents_tenants, [:tenant_record_type, :tenant_record_id]
```

**Column count: 31**

---

## Global Budget Tracking (No Table — Cache with Executions Fallback)

Global budgets stay cache-based but with an executions-table fallback on cache miss. No new table needed.

**Why no table:**
- Global budgets are a loose safety net (soft enforcement), not precision accounting
- Low contention — single app, not per-tenant isolation
- The read-modify-write race condition causes minor underreporting ($2 on a $300 limit) which is acceptable for soft enforcement
- Adding a singleton table creates complexity (singleton management, shared concern with tenants, two code paths everywhere) that isn't justified

**Cache with fallback approach:**

```ruby
def current_global_spend(period)
  cached = cache_read(global_key(period))
  return cached if cached.present?

  # Cache miss (restart, eviction) — rebuild from executions
  total = Execution.where("created_at >= ?", period_start(period))
                   .where(tenant_id: nil)
                   .sum(:total_cost)
  cache_write(global_key(period), total, expires_in: period_ttl(period))
  total
end
```

**How it works:**
1. Normal path: read/write cache (fast, same as today)
2. Cache miss (restart/eviction): recalculate from `executions` table, re-seed cache
3. Race condition: still exists on concurrent writes, but global budgets are soft enforcement — a few dollars of drift on a $300/day limit is acceptable
4. Dashboard reads: same cache read with the same fallback

**What changes from current code:**
- Add the executions fallback in `SpendRecorder` / `BudgetQuery` when cache returns nil
- Same pattern for tokens: `Execution.where(...).sum(:total_tokens)`
- No new tables, models, or migrations

---

## Table 4: `ruby_llm_agents_api_configurations`

Unchanged from current design — it's well-structured.

```ruby
create_table :ruby_llm_agents_api_configurations do |t|
  # ── Scope ──
  t.string :scope_type,         null: false, default: "global"  # global, tenant
  t.string :scope_id                                              # tenant_id when scope_type=tenant

  # ── Encrypted API keys ──
  t.text :openai_api_key
  t.text :anthropic_api_key
  t.text :gemini_api_key
  t.text :deepseek_api_key
  t.text :mistral_api_key
  t.text :perplexity_api_key
  t.text :openrouter_api_key
  t.text :gpustack_api_key
  t.text :xai_api_key
  t.text :ollama_api_key
  t.text :bedrock_api_key
  t.text :bedrock_secret_key
  t.text :bedrock_session_token
  t.text :vertexai_credentials

  # ── Provider-specific config ──
  t.string :bedrock_region
  t.string :vertexai_project_id
  t.string :vertexai_location

  # ── Custom endpoints ──
  t.string :openai_api_base
  t.string :gemini_api_base
  t.string :ollama_api_base
  t.string :gpustack_api_base
  t.string :xai_api_base

  # ── OpenAI-specific ──
  t.string :openai_organization_id
  t.string :openai_project_id

  # ── Default models ──
  t.string :default_model
  t.string :default_embedding_model
  t.string :default_image_model
  t.string :default_moderation_model

  # ── Connection settings ──
  t.integer :request_timeout
  t.integer :max_retries
  t.decimal :retry_interval,            precision: 5, scale: 2
  t.decimal :retry_backoff_factor,      precision: 5, scale: 2
  t.decimal :retry_interval_randomness, precision: 5, scale: 2
  t.string  :http_proxy

  # ── Inheritance ──
  t.boolean :inherit_global_defaults, default: true

  t.timestamps
end

add_index :ruby_llm_agents_api_configurations, [:scope_type, :scope_id], unique: true
```

---

## Schema Summary

| Table | Purpose | Columns | Rows |
|---|---|---|---|
| `executions` | Lean analytics — queryable metrics | 39 | Many (millions) |
| `execution_details` | Large payloads — prompts, response, error details, tool calls | 16 | Optional 1:1 with executions |
| `tenants` | Identity + budget config + rolling counters | 31 | Few (per customer) |
| `api_configurations` | API keys + endpoints + connection settings | 30 | Few (1 global + per tenant) |

Global budget tracking uses **cache with executions-table fallback** — no dedicated table.

**Total tables: 4** — up from 3. Each has a clear single responsibility.

---

## What Changed from Current Schema

| Change | Why |
|---|---|
| Split `execution_details` out of `executions` | Keep aggregation table lean. Prompts/response/tool_calls only loaded on detail page. |
| Dropped 20 indexes → 13 on executions | Removed single-column indexes that don't match real query patterns. |
| Kept `per_agent_daily`/`per_agent_monthly` JSON on tenants | Small hashes, rarely queried, JSON is simpler than a separate table. |
| Dropped `tenant_record` polymorphic from executions | Redundant — access via `execution → tenant → tenant_record`. |
| Global budgets: cache + executions fallback | No new table. Cache for speed, executions `SUM` on cache miss. Acceptable for soft enforcement. |
| Moved `error_message`, `system_prompt`, `user_prompt`, `response`, `tool_calls`, `attempts`, `parameters`, `routed_to`, `classification_result`, `messages_summary`, `fallback_chain`, `cached_at`, `cache_creation_tokens` to `execution_details` | These are display/audit data, not analytics data. `error_class` stays on executions for filtering; `error_message` (potentially large stack traces) moves to details. |
| Removed `organizations` table from gem | Example model belongs in dummy app/specs, not gem migrations. |

---

## Migration Strategy

This is the ideal schema, not a "rewrite everything now" plan. To get here incrementally:

1. **Now (v1):** Add tenant counter columns + global cache fallback (the budget tracking refactor plan)
2. **Next:** Create `execution_details` table, start writing to both tables, backfill
3. **Next:** Drop redundant `tenant_record` from executions
4. **Next:** Audit and drop unused indexes

Each step is a standalone migration that can ship independently.
