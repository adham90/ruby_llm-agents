# Tenant Budget Tracking Refactor: Cache-Based → DB-Based Counters

## Problem Statement

The current budget tracking system uses **cache-based counters** (via `SpendRecorder`) for real-time budget enforcement. This has several critical issues:

1. **Cache eviction/restart loses all counters** — Budget enforcement becomes blind after a Redis/Memcached restart or key eviction. Tenants can silently exceed limits.
2. **Cache-DB drift** — Cache counters and `SUM(executions.total_cost)` can diverge with no reconciliation.
3. **Race condition in increment** — `SpendRecorder.increment_spend` does read-modify-write (`read → add → write`) instead of atomic increment. Concurrent executions can underreport spend.
4. **No persistence across deploys** — Cache flush during deployment resets all budget counters.
5. **Expensive reporting queries** — `Trackable` concern aggregates from `executions` table every time (`SUM`, `COUNT`), which degrades as the table grows.

## Proposed Solution

Add rolling counter columns to the `tenants` table and use **atomic SQL increments** (`UPDATE SET col = col + value`) after each execution. Remove cache-based spend tracking entirely.

---

## New Columns on `ruby_llm_agents_tenants`

12 columns total — focused on budget enforcement and the dashboard's most-hit queries.

### Cost Counters

```ruby
t.decimal :daily_cost_spent,       precision: 12, scale: 6, default: 0, null: false
t.decimal :monthly_cost_spent,     precision: 12, scale: 6, default: 0, null: false
```

### Token Counters

```ruby
t.bigint :daily_tokens_used,       default: 0, null: false
t.bigint :monthly_tokens_used,     default: 0, null: false
```

### Execution Counters

```ruby
t.bigint :daily_executions_count,  default: 0, null: false
t.bigint :monthly_executions_count, default: 0, null: false
```

### Error Counters

```ruby
t.bigint :daily_error_count,       default: 0, null: false
t.bigint :monthly_error_count,     default: 0, null: false
```

### Last Execution Metadata

```ruby
t.datetime :last_execution_at
t.string   :last_execution_status               # "success", "error", "timeout"
```

### Period Tracking (for Lazy Reset)

```ruby
t.date :daily_reset_date                         # defaults to today
t.date :monthly_reset_date                       # defaults to first of current month
```

### What We Intentionally Left Out

| Dropped Column(s) | Reason |
|---|---|
| `daily_input_cost`, `daily_output_cost`, `monthly_input_cost`, `monthly_output_cost` | Rarely needed for budgets or dashboards. Query from `executions` when needed. |
| `daily_input_tokens`, `daily_output_tokens`, `daily_cached_tokens` + monthly variants | Nice-to-have metrics, not budget-critical. Adds 6 columns and write overhead for infrequent use. |
| `daily_cost_by_agent`, `monthly_cost_by_agent` + token variants (JSON) | Non-atomic read-modify-write under concurrency. Drifts and needs `refresh_counters!` anyway. Per-agent breakdown is a reporting query, not a budget enforcement need. |
| `last_model_used`, `last_agent_used` | Low value. The `last_execution_at` + `last_execution_status` cover tenant health. Detail is on the execution record. |

These can be added in a follow-up migration if user demand materializes.

---

## Dashboard Query Elimination

| Dashboard Section | Current Approach | With New Columns |
|---|---|---|
| **Budget widget** (daily/monthly spend) | 2× `SUM(total_cost)` on executions | Read `daily_cost_spent`, `monthly_cost_spent` |
| **Top metrics strip** (cost, tokens, count, errors) | 4-6 aggregation queries | Read counter columns directly |
| **Action center alerts** (budget breach) | `SUM` queries to check limits | `daily_cost_spent >= daily_limit` |
| **Multi-tenant admin listing** | N queries (1 per tenant) | 1 query: `Tenant.select(counter_columns).order(...)` |
| **Success rate** | `COUNT` success + error separately | `daily_executions_count - daily_error_count` |
| **Tenant health** | Query last execution | Read `last_execution_at`, `last_execution_status` |

**Still uses `executions` table for:** per-agent comparison, per-model breakdown, input/output cost split, cache hit ratio, historical ranges (last week, custom), time series charts, execution detail pages.

---

## Implementation Plan

### Phase 1: Migration

**File:** New migration `AddUsageCountersToTenants`

```ruby
class AddUsageCountersToTenants < ActiveRecord::Migration[7.1]
  def change
    change_table :ruby_llm_agents_tenants, bulk: true do |t|
      # Cost counters
      t.decimal :daily_cost_spent,        precision: 12, scale: 6, default: 0, null: false
      t.decimal :monthly_cost_spent,      precision: 12, scale: 6, default: 0, null: false

      # Token counters
      t.bigint :daily_tokens_used,        default: 0, null: false
      t.bigint :monthly_tokens_used,      default: 0, null: false

      # Execution counters
      t.bigint :daily_executions_count,   default: 0, null: false
      t.bigint :monthly_executions_count, default: 0, null: false

      # Error counters
      t.bigint :daily_error_count,        default: 0, null: false
      t.bigint :monthly_error_count,      default: 0, null: false

      # Last execution metadata
      t.datetime :last_execution_at
      t.string   :last_execution_status

      # Period tracking
      t.date :daily_reset_date
      t.date :monthly_reset_date
    end
  end
end
```

### Phase 2: Lazy Reset Logic

**File:** New concern `Tenant::Resettable`

The counters reset lazily — before any read or write, check if the period has rolled over:

```ruby
module Resettable
  extend ActiveSupport::Concern

  def ensure_daily_reset!
    return if daily_reset_date == Date.current

    # Atomic reset with WHERE guard to prevent race conditions
    rows = self.class.where(id: id)
      .where("daily_reset_date IS NULL OR daily_reset_date < ?", Date.current)
      .update_all(
        daily_cost_spent: 0, daily_tokens_used: 0,
        daily_executions_count: 0, daily_error_count: 0,
        daily_reset_date: Date.current
      )

    reload if rows > 0
  end

  def ensure_monthly_reset!
    bom = Date.current.beginning_of_month
    return if monthly_reset_date == bom

    rows = self.class.where(id: id)
      .where("monthly_reset_date IS NULL OR monthly_reset_date < ?", bom)
      .update_all(
        monthly_cost_spent: 0, monthly_tokens_used: 0,
        monthly_executions_count: 0, monthly_error_count: 0,
        monthly_reset_date: bom
      )

    reload if rows > 0
  end

  # Recalculate all counters from the source-of-truth executions table.
  # Use when counters have drifted due to manual DB edits, failed writes,
  # or after deleting/updating execution records.
  def refresh_counters!
    today = Date.current
    bom = today.beginning_of_month

    daily_stats = aggregate_stats(
      executions.where("created_at >= ?", today.beginning_of_day)
    )
    monthly_stats = aggregate_stats(
      executions.where("created_at >= ?", bom.beginning_of_day)
    )

    last_exec = executions.order(created_at: :desc).pick(:created_at, :status)

    update_columns(
      daily_cost_spent:        daily_stats[:cost],
      daily_tokens_used:       daily_stats[:tokens],
      daily_executions_count:  daily_stats[:count],
      daily_error_count:       daily_stats[:errors],
      daily_reset_date:        today,

      monthly_cost_spent:       monthly_stats[:cost],
      monthly_tokens_used:      monthly_stats[:tokens],
      monthly_executions_count: monthly_stats[:count],
      monthly_error_count:      monthly_stats[:errors],
      monthly_reset_date:       bom,

      last_execution_at:     last_exec&.first,
      last_execution_status: last_exec&.last
    )

    reload
  end

  def self.refresh_all_counters!
    find_each(&:refresh_counters!)
  end

  def self.refresh_active_counters!
    active.find_each(&:refresh_counters!)
  end

  private

  def aggregate_stats(scope)
    agg = scope.pick(
      Arel.sql("COALESCE(SUM(total_cost), 0)"),
      Arel.sql("COALESCE(SUM(total_tokens), 0)"),
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)")
    )

    { cost: agg[0], tokens: agg[1], count: agg[2], errors: agg[3] }
  end
end
```

### Phase 3: Atomic Increment Method

**File:** New concern `Tenant::Incrementable`

```ruby
module Incrementable
  extend ActiveSupport::Concern

  def record_execution!(cost:, tokens:, error: false)
    ensure_daily_reset!
    ensure_monthly_reset!

    error_inc = error ? 1 : 0

    # Single atomic SQL UPDATE — no read-modify-write race
    self.class.where(id: id).update_all(
      self.class.sanitize_sql_array([
        <<~SQL,
          daily_cost_spent = daily_cost_spent + ?,
          monthly_cost_spent = monthly_cost_spent + ?,
          daily_tokens_used = daily_tokens_used + ?,
          monthly_tokens_used = monthly_tokens_used + ?,
          daily_executions_count = daily_executions_count + 1,
          monthly_executions_count = monthly_executions_count + 1,
          daily_error_count = daily_error_count + ?,
          monthly_error_count = monthly_error_count + ?,
          last_execution_at = ?,
          last_execution_status = ?
        SQL
        cost.to_f, cost.to_f,
        tokens.to_i, tokens.to_i,
        error_inc, error_inc,
        Time.current, error ? "error" : "success"
      ])
    )

    reload
    check_soft_cap_alerts!
  end
end
```

### Phase 4: Update Budget Middleware

**File:** `lib/ruby_llm/agents/pipeline/middleware/budget.rb`

Change `record_spend!` to call the tenant's `record_execution!` method instead of `BudgetTracker.record_spend!`:

```ruby
def record_spend!(context)
  return unless context.tenant_id.present?

  tenant = Tenant.find_by(tenant_id: context.tenant_id)
  return unless tenant

  tenant.record_execution!(
    cost: context.total_cost || 0,
    tokens: context.total_tokens || 0,
    error: context.error?
  )
end
```

### Phase 5: Update Budget Checks (Pre-Execution)

**File:** `Tenant::Budgetable`

Replace `BudgetTracker.check_budget!` with direct column reads:

```ruby
def within_daily_cost_budget?
  ensure_daily_reset!
  daily_limit.nil? || daily_cost_spent < daily_limit
end

def within_monthly_cost_budget?
  ensure_monthly_reset!
  monthly_limit.nil? || monthly_cost_spent < monthly_limit
end

def within_daily_token_budget?
  ensure_daily_reset!
  daily_token_limit.nil? || daily_tokens_used < daily_token_limit
end

def within_daily_execution_budget?
  ensure_daily_reset!
  daily_execution_limit.nil? || daily_executions_count < daily_execution_limit
end

# ... same pattern for all monthly variants
```

### Phase 6: Update Trackable Concern

**File:** `app/models/ruby_llm/agents/tenant/trackable.rb`

For current-period queries, read directly from counters instead of aggregating:

```ruby
# Current period — read from counters (free)
def cost_today          = (ensure_daily_reset!;  daily_cost_spent)
def cost_this_month     = (ensure_monthly_reset!; monthly_cost_spent)
def tokens_today        = (ensure_daily_reset!;  daily_tokens_used)
def tokens_this_month   = (ensure_monthly_reset!; monthly_tokens_used)
def executions_today    = (ensure_daily_reset!;  daily_executions_count)
def executions_this_month = (ensure_monthly_reset!; monthly_executions_count)
def errors_today        = (ensure_daily_reset!;  daily_error_count)
def errors_this_month   = (ensure_monthly_reset!; monthly_error_count)
def success_rate_today  = daily_executions_count.zero? ? 100.0 :
                          ((daily_executions_count - daily_error_count).to_f / daily_executions_count * 100)

# Historical periods — still aggregate from executions table
def cost_last_week      = executions.last_n_days(7).sum(:total_cost)
# ... etc
```

**Keep** the `executions` table aggregation for historical queries (last week, last month, custom ranges, per-agent breakdowns, per-model breakdowns, time series charts, etc.).

### Phase 7: Remove Tenant Cache-Based Tracking, Add Global Fallback

**Files to modify:**
- `lib/ruby_llm/agents/infrastructure/budget/spend_recorder.rb` — Remove **tenant** cache increment logic. Keep global cache writes.
- `lib/ruby_llm/agents/infrastructure/budget_tracker.rb` — Remove tenant `current_spend`/`current_tokens` cache reads; delegate to tenant model. Keep global reads.
- `lib/ruby_llm/agents/pipeline/middleware/budget.rb` — Already updated in Phase 4

**Add executions fallback for global cache misses:**

```ruby
# In SpendRecorder or BudgetQuery
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

def current_global_tokens(period)
  cached = cache_read(global_token_key(period))
  return cached if cached.present?

  total = Execution.where("created_at >= ?", period_start(period))
                   .where(tenant_id: nil)
                   .sum(:total_tokens)
  cache_write(global_token_key(period), total, expires_in: period_ttl(period))
  total
end
```

**Why cache stays for global but not tenant:**
- Global budgets are soft enforcement safety nets — minor drift from the read-modify-write race is acceptable
- A dedicated table for one singleton row adds complexity (shared concerns, two code paths) that isn't justified
- The executions fallback ensures cache loss (restart/eviction) no longer causes counters to reset to zero

**Keep:** Alert logic (soft cap notifications) for tenants moves to `Tenant::Incrementable`.

### Phase 8: Alerts (Soft Cap)

Move alert checking into the tenant model, called after increment in `record_execution!`:

```ruby
def check_soft_cap_alerts!
  return unless soft_enforcement?

  if daily_limit && daily_cost_spent >= daily_limit
    AlertManager.notify(:budget_soft_cap, tenant_id: tenant_id, type: :daily_cost)
  end
  if monthly_limit && monthly_cost_spent >= monthly_limit
    AlertManager.notify(:budget_soft_cap, tenant_id: tenant_id, type: :monthly_cost)
  end
  if daily_token_limit && daily_tokens_used >= daily_token_limit
    AlertManager.notify(:token_soft_cap, tenant_id: tenant_id, type: :daily_tokens)
  end
  if monthly_token_limit && monthly_tokens_used >= monthly_token_limit
    AlertManager.notify(:token_soft_cap, tenant_id: tenant_id, type: :monthly_tokens)
  end
  if daily_execution_limit && daily_executions_count >= daily_execution_limit
    AlertManager.notify(:budget_soft_cap, tenant_id: tenant_id, type: :daily_executions)
  end
  if monthly_execution_limit && monthly_executions_count >= monthly_execution_limit
    AlertManager.notify(:budget_soft_cap, tenant_id: tenant_id, type: :monthly_executions)
  end
end
```

---

## Phase 9: Refresh / Reconciliation

The counters are **append-only approximations**. They can drift when:
- Execution records are manually deleted or updated after the fact
- A `record_execution!` write fails silently
- Manual DB edits to executions or tenants

The `refresh_counters!` method (defined in Phase 2) recalculates everything from the source-of-truth `executions` table.

### 9a: Rake Tasks

**File:** `lib/tasks/ruby_llm_agents.rake`

```ruby
namespace :ruby_llm_agents do
  namespace :tenants do
    desc "Refresh all tenant counters from executions table"
    task refresh: :environment do
      count = 0
      RubyLLM::Agents::Tenant.find_each do |tenant|
        tenant.refresh_counters!
        count += 1
      end
      puts "Refreshed #{count} tenants"
    end

    desc "Refresh a single tenant's counters"
    task :refresh_one, [:tenant_id] => :environment do |_, args|
      tenant = RubyLLM::Agents::Tenant.find_by!(tenant_id: args[:tenant_id])
      tenant.refresh_counters!
      puts "Refreshed tenant: #{tenant.tenant_id}"
    end
  end
end
```

Usage:
```bash
rake ruby_llm_agents:tenants:refresh
rake ruby_llm_agents:tenants:refresh_one[acme_corp]
```

### 9b: Programmatic Access

```ruby
# Single tenant
tenant.refresh_counters!

# All active tenants
RubyLLM::Agents::Tenant.refresh_active_counters!

# All tenants
RubyLLM::Agents::Tenant.refresh_all_counters!
```

Users who want scheduled reconciliation can call these in their own jobs/cron — the gem doesn't need to ship a job class for this.

### 9c: Dashboard Refresh Button (Optional)

Add a "Refresh" action to the tenant budget widget that calls `tenant.refresh_counters!` — useful when an admin notices drift and wants to fix it without SSH.

---

## Non-Tenant Users Impact

**None.** The migration adds columns with defaults to a table that sits empty when multi-tenancy is disabled. The `record_execution!` path is only called when `context.tenant_id` is present. No runtime cost, no behavior change for single-tenant users.

---

## Files Changed Summary

| File | Change |
|------|--------|
| New migration | Add 12 counter/metadata columns |
| New: `tenant/resettable.rb` | Lazy reset, `refresh_counters!`, `aggregate_stats`, class-level refresh methods |
| New: `tenant/incrementable.rb` | `record_execution!` with sanitized atomic SQL increment |
| `tenant.rb` | Include `Resettable`, `Incrementable` |
| `tenant/trackable.rb` | Use counter columns for current-period reads, keep executions for historical |
| `tenant/budgetable.rb` | Check budget against counter columns directly |
| `pipeline/middleware/budget.rb` | Call `tenant.record_execution!` instead of cache |
| `infrastructure/budget/spend_recorder.rb` | Remove tenant cache logic. Keep global cache writes. Add executions fallback on global cache miss. |
| `infrastructure/budget_tracker.rb` | Delegate tenant reads to model. Keep global cache reads with fallback. |
| New: `lib/tasks/ruby_llm_agents.rake` | Rake tasks for refresh |
| Dashboard controller | Read counters instead of running aggregation queries |
| Dashboard views | Use new counter-based helpers |
| Specs for all above | Update to test DB-based counters, refresh, lazy reset |

## Migration Path

1. Deploy migration (adds columns, no behavior change)
2. Deploy code changes (tenant: switches from cache to DB counters; global: adds executions fallback on cache miss)
3. Run `rake ruby_llm_agents:tenants:refresh` to backfill current-period counters from executions
4. Remove dead tenant cache code (global cache stays with fallback)

## Trade-offs

**Gains:**
- Tenant counters: single source of truth (DB), survives restarts/deploys
- Atomic increments prevent race conditions for tenant tracking
- Cheap tenant budget checks (single column read vs cache round-trip)
- Cheap current-period reporting (no `SUM` aggregation)
- Dashboard queries reduced from 6+ aggregations to column reads
- Easy reconciliation via `refresh_counters!` when drift occurs
- Global budgets: no longer lose all tracking on cache restart (executions fallback)

**Costs:**
- One extra DB write per tenant execution (the `UPDATE` for counter increment)
- Row-level contention under very high concurrency per tenant (mitigated by atomic SQL)
- Lazy reset adds a conditional check before reads/writes
- Global budget tracking still has the read-modify-write race in cache (acceptable for soft enforcement)

**Acceptable because:**
- The execution already does a DB write (creating the `Execution` record), so one more `UPDATE` is negligible
- Atomic SQL increments handle typical concurrency well
- Lazy reset is a single date comparison — effectively free
- Global budgets are soft enforcement safety nets — minor drift is acceptable
- Non-tenant users pay zero runtime cost (global cache fallback only triggers on cache miss)
