# Database Schema Refactor Plan

This plan migrates from the current 3-table schema (68-column executions, tenants, api_configurations) to a cleaner 4-table design with leaner executions, separated detail payloads, tenant rolling counters, and global cache fallback.

---

## Target Schema

### Table 1: `ruby_llm_agents_executions` (39 columns)

Lean analytics table — only columns that are queried, aggregated, or filtered.

```ruby
create_table :ruby_llm_agents_executions do |t|
  # ── Agent identification ──
  t.string  :agent_type,       null: false
  t.string  :agent_version,    null: false, default: "1.0"
  t.string  :execution_type,   null: false, default: "chat"

  # ── Model ──
  t.string  :model_id,         null: false
  t.string  :model_provider
  t.decimal :temperature,      precision: 3, scale: 2
  t.string  :chosen_model_id

  # ── Status ──
  t.string  :status,           null: false, default: "running"
  t.string  :finish_reason
  t.string  :error_class

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
  t.string  :response_cache_key

  # ── Streaming ──
  t.boolean :streaming,        default: false
  t.integer :time_to_first_token_ms

  # ── Retry / Fallback ──
  t.integer :attempts_count,   default: 1, null: false
  t.boolean :retryable
  t.boolean :rate_limited
  t.string  :fallback_reason

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
  t.string  :workflow_type
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
add_index :ruby_llm_agents_executions, [:agent_type, :created_at]
add_index :ruby_llm_agents_executions, [:agent_type, :status]
add_index :ruby_llm_agents_executions, :status
add_index :ruby_llm_agents_executions, :created_at
add_index :ruby_llm_agents_executions, [:tenant_id, :created_at]
add_index :ruby_llm_agents_executions, [:tenant_id, :status]
add_index :ruby_llm_agents_executions, :trace_id
add_index :ruby_llm_agents_executions, :request_id
add_index :ruby_llm_agents_executions, :parent_execution_id
add_index :ruby_llm_agents_executions, :root_execution_id
add_index :ruby_llm_agents_executions, [:workflow_id, :workflow_step]
add_index :ruby_llm_agents_executions, :workflow_type
add_index :ruby_llm_agents_executions, :response_cache_key

add_foreign_key :ruby_llm_agents_executions, :ruby_llm_agents_executions,
                column: :parent_execution_id, on_delete: :nullify
add_foreign_key :ruby_llm_agents_executions, :ruby_llm_agents_executions,
                column: :root_execution_id, on_delete: :nullify
```

### Table 2: `ruby_llm_agents_execution_details` (16 columns)

Optional 1:1 with executions. Large payloads for audit and display. Only created when there's data to store.

```ruby
create_table :ruby_llm_agents_execution_details do |t|
  t.references :execution, null: false,
               foreign_key: { to_table: :ruby_llm_agents_executions, on_delete: :cascade },
               index: { unique: true }

  t.text     :error_message
  t.text     :system_prompt
  t.text     :user_prompt
  t.json     :response,             default: {}
  t.json     :messages_summary,     default: {}, null: false
  t.json     :tool_calls,           default: [], null: false
  t.json     :attempts,             default: [], null: false
  t.json     :fallback_chain
  t.json     :parameters,           default: {}, null: false
  t.string   :routed_to
  t.json     :classification_result
  t.datetime :cached_at
  t.integer  :cache_creation_tokens, default: 0

  t.timestamps
end
```

### Table 3: `ruby_llm_agents_tenants` (31 columns)

Tenant identity, budget config, and rolling counters.

```ruby
create_table :ruby_llm_agents_tenants do |t|
  t.string  :tenant_id,          null: false
  t.string  :name
  t.boolean :active,             default: true, null: false
  t.json    :metadata,           default: {}, null: false

  t.string  :tenant_record_type
  t.bigint  :tenant_record_id

  t.decimal :daily_limit,        precision: 12, scale: 6
  t.decimal :monthly_limit,      precision: 12, scale: 6
  t.bigint  :daily_token_limit
  t.bigint  :monthly_token_limit
  t.bigint  :daily_execution_limit
  t.bigint  :monthly_execution_limit
  t.json    :per_agent_daily,    default: {}, null: false
  t.json    :per_agent_monthly,  default: {}, null: false
  t.string  :enforcement,        default: "soft", null: false
  t.boolean :inherit_global_defaults, default: true, null: false

  t.decimal :daily_cost_spent,        precision: 12, scale: 6, default: 0, null: false
  t.decimal :monthly_cost_spent,      precision: 12, scale: 6, default: 0, null: false
  t.bigint  :daily_tokens_used,       default: 0, null: false
  t.bigint  :monthly_tokens_used,     default: 0, null: false
  t.bigint  :daily_executions_count,  default: 0, null: false
  t.bigint  :monthly_executions_count, default: 0, null: false
  t.bigint  :daily_error_count,       default: 0, null: false
  t.bigint  :monthly_error_count,     default: 0, null: false

  t.datetime :last_execution_at
  t.string   :last_execution_status

  t.date :daily_reset_date
  t.date :monthly_reset_date

  t.timestamps
end

add_index :ruby_llm_agents_tenants, :tenant_id, unique: true
add_index :ruby_llm_agents_tenants, :active
add_index :ruby_llm_agents_tenants, [:tenant_record_type, :tenant_record_id]
```

### Table 4: `ruby_llm_agents_api_configurations` (30 columns)

Unchanged from current design.

```ruby
create_table :ruby_llm_agents_api_configurations do |t|
  t.string :scope_type,         null: false, default: "global"
  t.string :scope_id

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

  t.string :bedrock_region
  t.string :vertexai_project_id
  t.string :vertexai_location

  t.string :openai_api_base
  t.string :gemini_api_base
  t.string :ollama_api_base
  t.string :gpustack_api_base
  t.string :xai_api_base

  t.string :openai_organization_id
  t.string :openai_project_id

  t.string :default_model
  t.string :default_embedding_model
  t.string :default_image_model
  t.string :default_moderation_model

  t.integer :request_timeout
  t.integer :max_retries
  t.decimal :retry_interval,            precision: 5, scale: 2
  t.decimal :retry_backoff_factor,      precision: 5, scale: 2
  t.decimal :retry_interval_randomness, precision: 5, scale: 2
  t.string  :http_proxy

  t.boolean :inherit_global_defaults, default: true

  t.timestamps
end

add_index :ruby_llm_agents_api_configurations, [:scope_type, :scope_id], unique: true
```

### Global Budget Tracking (No Table — Cache with Executions Fallback)

Global budgets stay cache-based with an executions-table fallback on cache miss.

```ruby
def current_global_spend(period)
  cached = cache_read(global_key(period))
  return cached if cached.present?

  total = Execution.where("created_at >= ?", period_start(period))
                   .where(tenant_id: nil)
                   .sum(:total_cost)
  cache_write(global_key(period), total, expires_in: period_ttl(period))
  total
end
```

---

## Schema Summary

| Table | Purpose | Columns | Rows |
|---|---|---|---|
| `executions` | Lean analytics — queryable metrics | 39 | Many (millions) |
| `execution_details` | Large payloads — prompts, response, error details, tool calls | 16 | Optional 1:1 with executions |
| `tenants` | Identity + budget config + rolling counters | 31 | Few (per customer) |
| `api_configurations` | API keys + endpoints + connection settings | 30 | Few (1 global + per tenant) |

**Total tables: 4.** Global budget tracking uses cache with executions-table fallback.

---

## What Changed from Current Schema

| Change | Why |
|---|---|
| Split `execution_details` out of `executions` | Keep aggregation table lean. Prompts/response/tool_calls only loaded on detail page. |
| Dropped 20 indexes → 13 on executions | Removed single-column indexes that don't match real query patterns. |
| Kept `per_agent_daily`/`per_agent_monthly` JSON on tenants | Small hashes, rarely queried, JSON is simpler than a separate table. |
| Dropped `tenant_record` polymorphic from executions | Redundant — access via `execution → tenant → tenant_record`. |
| Global budgets: cache + executions fallback | No new table. Cache for speed, executions `SUM` on cache miss. Acceptable for soft enforcement. |
| Moved `error_message`, `system_prompt`, `user_prompt`, `response`, `tool_calls`, `attempts`, `parameters`, `routed_to`, `classification_result`, `messages_summary`, `fallback_chain`, `cached_at`, `cache_creation_tokens` to `execution_details` | Display/audit data, not analytics. `error_class` stays on executions for filtering. |
| Removed `organizations` table from gem | Example model belongs in dummy app/specs, not gem migrations. |

---

## Implementation Plan

### Phase 1: Tenant Counter Columns (ships with budget tracking refactor)

Already covered in `plans/tenant_budget_tracking_refactor.md`. Adds 12 counter/metadata columns to `tenants` table. No changes to `executions`.

### Phase 2: Split `execution_details` from Executions

Single migration that creates the new table, backfills data, and drops old columns. Users run the generator to get the migration file, then `rails db:migrate` handles everything during deploy.

**Migration:**

```ruby
class SplitExecutionDetailsFromExecutions < ActiveRecord::Migration[7.1]
  def up
    # 1. Create the new table
    create_table :ruby_llm_agents_execution_details do |t|
      t.references :execution, null: false,
                   foreign_key: { to_table: :ruby_llm_agents_executions, on_delete: :cascade },
                   index: { unique: true }

      t.text     :error_message
      t.text     :system_prompt
      t.text     :user_prompt
      t.json     :response,             default: {}
      t.json     :messages_summary,     default: {}, null: false
      t.json     :tool_calls,           default: [], null: false
      t.json     :attempts,             default: [], null: false
      t.json     :fallback_chain
      t.json     :parameters,           default: {}, null: false
      t.string   :routed_to
      t.json     :classification_result
      t.datetime :cached_at
      t.integer  :cache_creation_tokens, default: 0

      t.timestamps
    end

    # 2. Backfill existing data
    execute <<~SQL
      INSERT INTO ruby_llm_agents_execution_details
        (execution_id, error_message, system_prompt, user_prompt, response,
         messages_summary, tool_calls, attempts, fallback_chain, parameters,
         routed_to, classification_result, cached_at, cache_creation_tokens,
         created_at, updated_at)
      SELECT id, error_message, system_prompt, user_prompt, response,
             messages_summary, tool_calls, attempts, fallback_chain, parameters,
             routed_to, classification_result, cached_at, cache_creation_tokens,
             created_at, updated_at
      FROM ruby_llm_agents_executions
      WHERE error_message IS NOT NULL
         OR system_prompt IS NOT NULL
         OR user_prompt IS NOT NULL
         OR response IS NOT NULL
         OR tool_calls IS NOT NULL
         OR attempts IS NOT NULL
         OR routed_to IS NOT NULL
    SQL

    # 3. Drop old columns
    remove_column :ruby_llm_agents_executions, :error_message, :text
    remove_column :ruby_llm_agents_executions, :system_prompt, :text
    remove_column :ruby_llm_agents_executions, :user_prompt, :text
    remove_column :ruby_llm_agents_executions, :response, :json
    remove_column :ruby_llm_agents_executions, :messages_summary, :json
    remove_column :ruby_llm_agents_executions, :tool_calls, :json
    remove_column :ruby_llm_agents_executions, :attempts, :json
    remove_column :ruby_llm_agents_executions, :fallback_chain, :json
    remove_column :ruby_llm_agents_executions, :parameters, :json
    remove_column :ruby_llm_agents_executions, :routed_to, :string
    remove_column :ruby_llm_agents_executions, :classification_result, :json
    remove_column :ruby_llm_agents_executions, :cached_at, :datetime
    remove_column :ruby_llm_agents_executions, :cache_creation_tokens, :integer
  end

  def down
    # Re-add old columns
    add_column :ruby_llm_agents_executions, :error_message, :text
    add_column :ruby_llm_agents_executions, :system_prompt, :text
    add_column :ruby_llm_agents_executions, :user_prompt, :text
    add_column :ruby_llm_agents_executions, :response, :json
    add_column :ruby_llm_agents_executions, :messages_summary, :json
    add_column :ruby_llm_agents_executions, :tool_calls, :json
    add_column :ruby_llm_agents_executions, :attempts, :json
    add_column :ruby_llm_agents_executions, :fallback_chain, :json
    add_column :ruby_llm_agents_executions, :parameters, :json
    add_column :ruby_llm_agents_executions, :routed_to, :string
    add_column :ruby_llm_agents_executions, :classification_result, :json
    add_column :ruby_llm_agents_executions, :cached_at, :datetime
    add_column :ruby_llm_agents_executions, :cache_creation_tokens, :integer

    # Copy data back
    execute <<~SQL
      UPDATE ruby_llm_agents_executions e
      SET error_message = d.error_message,
          system_prompt = d.system_prompt,
          user_prompt = d.user_prompt,
          response = d.response,
          messages_summary = d.messages_summary,
          tool_calls = d.tool_calls,
          attempts = d.attempts,
          fallback_chain = d.fallback_chain,
          parameters = d.parameters,
          routed_to = d.routed_to,
          classification_result = d.classification_result,
          cached_at = d.cached_at,
          cache_creation_tokens = d.cache_creation_tokens
      FROM ruby_llm_agents_execution_details d
      WHERE d.execution_id = e.id
    SQL

    drop_table :ruby_llm_agents_execution_details
  end
end
```

**Model:**

```ruby
# app/models/ruby_llm/agents/execution_detail.rb
module RubyLLM
  module Agents
    class ExecutionDetail < ActiveRecord::Base
      self.table_name = "ruby_llm_agents_execution_details"

      belongs_to :execution, class_name: "RubyLLM::Agents::Execution"
    end
  end
end
```

**Association on Execution:**

```ruby
# In execution.rb
has_one :detail, class_name: "RubyLLM::Agents::ExecutionDetail",
        dependent: :destroy

# Delegations so existing code keeps working
delegate :system_prompt, :user_prompt, :response, :error_message,
         :messages_summary, :tool_calls, :attempts, :fallback_chain,
         :parameters, :routed_to, :classification_result,
         :cached_at, :cache_creation_tokens,
         to: :detail, prefix: false, allow_nil: true
```

**Instrumentation writes to detail table:**

```ruby
# In instrumentation middleware, after creating the execution:
def save_execution_details(execution, context)
  detail_data = {
    error_message: context.error_message,
    system_prompt: context.system_prompt,
    user_prompt: context.user_prompt,
    response: context.response,
    messages_summary: context.messages_summary,
    tool_calls: context.tool_calls,
    attempts: context.attempts,
    fallback_chain: context.fallback_chain,
    parameters: context.redacted_parameters,
    routed_to: context.routed_to,
    classification_result: context.classification_result,
    cached_at: context.cached_at,
    cache_creation_tokens: context.cache_creation_tokens
  }

  has_data = detail_data.values.any? { |v| v.present? && v != {} && v != [] }
  execution.create_detail!(detail_data) if has_data
end
```

### Phase 3: Drop `tenant_record` Polymorphic from Executions

The `tenant_record_type`/`tenant_record_id` on executions is redundant — the tenant row already holds this association. Access via `execution.tenant.tenant_record`.

**Migration:**

```ruby
class RemoveTenantRecordFromExecutions < ActiveRecord::Migration[7.1]
  def change
    remove_index :ruby_llm_agents_executions,
                 column: [:tenant_record_type, :tenant_record_id],
                 if_exists: true
    remove_column :ruby_llm_agents_executions, :tenant_record_type, :string
    remove_column :ruby_llm_agents_executions, :tenant_record_id, :bigint
  end
end
```

**Model changes:**

```ruby
# Remove from execution.rb:
belongs_to :tenant_record, polymorphic: true, optional: true

# Add convenience method instead:
def tenant_record
  return nil unless tenant_id.present?
  Tenant.find_by(tenant_id: tenant_id)&.tenant_record
end
```

**Update any views** that reference `execution.tenant_record` to go through `execution.tenant_record` (which now delegates through the tenant).

### Phase 4: Audit and Drop Unused Indexes

**Remove these indexes** (single-column on rarely-filtered columns):

```ruby
class CleanupExecutionIndexes < ActiveRecord::Migration[7.1]
  def change
    # These exist in current schema but aren't used in real query patterns
    remove_index :ruby_llm_agents_executions, :duration_ms, if_exists: true
    remove_index :ruby_llm_agents_executions, :total_cost, if_exists: true
    remove_index :ruby_llm_agents_executions, :messages_count, if_exists: true
    remove_index :ruby_llm_agents_executions, :attempts_count, if_exists: true
    remove_index :ruby_llm_agents_executions, :tool_calls_count, if_exists: true
    remove_index :ruby_llm_agents_executions, :chosen_model_id, if_exists: true
    remove_index :ruby_llm_agents_executions, :execution_type, if_exists: true

    # These overlap with composite indexes
    remove_index :ruby_llm_agents_executions, :agent_type, if_exists: true
    remove_index :ruby_llm_agents_executions, :tenant_id, if_exists: true
  end
end
```

**Keep:** All composite indexes, `trace_id`, `request_id`, `parent_execution_id`, `root_execution_id`, `response_cache_key`, `workflow_type`, `status`, `created_at`.

### Phase 5: Global Cache Fallback

No migration needed. Code change only.

**File:** `lib/ruby_llm/agents/infrastructure/budget/spend_recorder.rb` (or `budget_query.rb`)

```ruby
def current_global_spend(period)
  cached = cache_read(global_key(period))
  return cached if cached.present?

  # Cache miss — rebuild from executions table
  total = Execution.where("created_at >= ?", period_start(period))
                   .where(tenant_id: nil)
                   .sum(:total_cost)
  cache_write(global_key(period), total, expires_in: period_ttl(period))
  total
end

def current_global_tokens(period)
  cached = cache_read(global_token_key(period))
  return cached if cached.present?

  total = Execution.where("created_at >= ?", period_start(period))
                   .where(tenant_id: nil)
                   .sum(:total_tokens)
  cache_write(global_token_key(period), total, expires_in: period_ttl(period))
  total
end

private

def period_start(period)
  case period
  when :daily  then Date.current.beginning_of_day
  when :monthly then Date.current.beginning_of_month.beginning_of_day
  end
end

def period_ttl(period)
  case period
  when :daily  then 1.day
  when :monthly then 31.days
  end
end
```

### Phase 6: Remove `organizations` from Gem Migrations

Move the `create_organizations` migration from `lib/generators/ruby_llm_agents/templates/` to `example/db/migrate/` (or the dummy app). Users installing the gem should not get an `organizations` table.

### Phase 7: Remove `TenantBudget` Alias

```ruby
# Remove from app/models/ruby_llm/agents/tenant_budget.rb:
TenantBudget = Tenant
```

If the gem has shipped stable releases, add a deprecation warning first:

```ruby
TenantBudget = Tenant
ActiveSupport::Deprecation.warn(
  "RubyLLM::Agents::TenantBudget is deprecated. Use RubyLLM::Agents::Tenant instead."
)
```

Remove entirely in the next major version.

---

## Shipping Order

Each phase is independent and ships as its own gem version.

| Phase | What | Breaking? | Notes |
|---|---|---|---|
| **1** | Tenant counter columns | No | Additive — new columns with defaults |
| **2** | Split `execution_details` + backfill + drop old columns | **Yes** | Single migration: create table, backfill via SQL, drop old columns |
| **3** | Drop `tenant_record` from executions | **Yes** | Bundle with Phase 2 in same major version |
| **4** | Drop unused indexes | No | Performance improvement, no API change |
| **5** | Global cache fallback | No | Bug fix — cache miss no longer loses global counters |
| **6** | Remove `organizations` from gem | No | Only affects new installs |
| **7** | Remove `TenantBudget` alias | **Yes** | Bundle with Phase 2/3 in same major version |

**Recommended grouping:**
- **v0.next (non-breaking):** Phases 1, 4, 5, 6
- **v1.0 (breaking):** Phases 2, 3, 7

---

## Files Changed per Phase

### Phase 1 (tenant counters)
See `plans/tenant_budget_tracking_refactor.md` — fully detailed there.

### Phase 2 (split execution_details)
| File | Change |
|---|---|
| New migration | Create `execution_details`, backfill via SQL, drop 13 old columns from executions |
| New: `app/models/ruby_llm/agents/execution_detail.rb` | Model with `belongs_to :execution` |
| `app/models/ruby_llm/agents/execution.rb` | Add `has_one :detail`, add delegations |
| `lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb` | Write details to `execution_details` table |
| `lib/ruby_llm/agents/core/instrumentation.rb` | Same — write to detail table |
| All views referencing moved columns | Read via delegation (transparent) or `execution.detail.X` |
| `execution/workflow.rb` | Read `routed_to`, `classification_result` from detail |
| Specs | Test detail creation, optional creation, cascade delete |

### Phase 3 (drop tenant_record from executions)
| File | Change |
|---|---|
| New migration | Remove `tenant_record_type`, `tenant_record_id`, index |
| `execution.rb` | Remove `belongs_to :tenant_record`, add delegation through tenant |
| Views/controllers referencing `execution.tenant_record` | No change if using the convenience method |
| Specs | Update |

### Phase 4 (drop indexes)
| File | Change |
|---|---|
| New migration | Remove 9 unused indexes |

### Phase 5 (global cache fallback)
| File | Change |
|---|---|
| `infrastructure/budget/spend_recorder.rb` or `budget_query.rb` | Add `current_global_spend` / `current_global_tokens` with fallback |
| Specs | Test cache hit, cache miss with fallback, re-seeding |

### Phase 6 (remove organizations)
| File | Change |
|---|---|
| `lib/generators/ruby_llm_agents/templates/` | Remove `create_organizations_migration.rb.tt` |
| Generator code | Remove reference to organizations migration |

### Phase 7 (remove alias)
| File | Change |
|---|---|
| `app/models/ruby_llm/agents/tenant_budget.rb` | Delete file (or add deprecation first) |
