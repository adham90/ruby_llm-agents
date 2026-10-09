# Dashboard on large executions tables

## Context

A production install (PostgreSQL, a few million executions) was getting 500s
from `/agents/executions` and `/agents/agents`. AppSignal showed both as
`Rack::Timeout` at 15 seconds inside a single aggregate query, and the
dashboard home taking 3 to 12 seconds on `SELECT DISTINCT agent_type` and the
period aggregates.

The 2026-09-01 change removed duplicated and N+1 queries, but left the shape
of the remaining ones alone: most pages still aggregated **all time**, so
their cost grew with the table rather than with what the page shows. Measured
on a 10M-row, 6.4 GB executions table (PostgreSQL 16, no caching) after that
change:

| Page | Time |
|------|------|
| Executions list (default) | 43 s |
| Agents list | 366 s |
| Agent page | 125 s |
| Dashboard, 30 / 90 days | 18 s / 42 s |
| Analytics, 30 / 90 days | 13 s / 51 s |
| Requests list | 54 s |
| Tenants list / tenant page | 38 s / 72 s |

Three causes account for all of it:

1. **All-time aggregates.** The executions totals strip, per-agent stats on
   the agents list (one query per agent), every figure on the agent and tenant
   pages, and the requests list all scanned the whole table.
2. **One scan per section.** The dashboard and analytics pages ran a separate
   pass over the selected range for each section (agents, models, errors,
   cache savings, error cost, ...).
3. **Wide rows.** Any aggregate over a time range fetched the full row to read
   five narrow columns; the `metadata` JSON makes up most of each row.

Running the suite against PostgreSQL (CI is SQLite-only) also turned up two
pages and two scopes that raised there: `requests#show` (`DISTINCT` with
`ORDER BY`), and `metadata_true` / `with_parameter` (`jsonb` operators applied
to `json` columns).

## Decision

**Bound what is aggregated.**

- Agents list: stats cover the last 30 days (`AgentRegistry::STATS_WINDOW`)
  and come from one grouped query for all agents, cached for 5 minutes.
  "Last run" stays all-time (an index probe).
- Agent page: headline stats cover the last 30 days, one query
  (`Execution.usage_summary`). Removed four loads the view never rendered
  (filter options, status and finish-reason distributions, average TTFT).
- Tenant page: usage figures cover the current month. Tenants list reads cost
  and last run from the counter columns on the tenant row instead of grouping
  executions by tenant.
- Requests list: the newest-first page is found by ranking requests seen in
  the last day, widening to 7 days, 30 days, then everything only if the page
  is not full; only the requests on the page are aggregated.

**Scan a range once.** `Execution.breakdown` reads a scope once, grouped by
agent, model, billed model, status and error class, and returns an
`Execution::Breakdown` that derives totals, per-agent and per-model stats, top
errors, error cost and cache savings in Ruby. The dashboard and analytics
pages build every section from one breakdown. `model_stats`, `top_errors`,
`cache_savings` and `batch_agent_stats` are now thin wrappers over it.

**Make the range cheap to scan.** New covering index `idx_executions_analytics`
on `created_at` including the aggregated columns, so range aggregates are
answered from the index without touching table rows. On the test table it is
1.2 GB next to 6.4 GB of table.

**Do not let any one figure hold the page hostage.**

- `Execution.with_statement_timeout` / `Execution.best_effort` (PostgreSQL
  `SET LOCAL statement_timeout` inside a savepoint).
- Every dashboard GET runs under `config.dashboard_query_timeout` (default 5 s,
  nil disables). A cancelled query renders a "narrow the time range" page with
  a 503 instead of a web-server timeout, and the database stops working on it.
- The totals strip on the executions list, agent page and requests list is
  best-effort with a 1 s budget. Without it the list still renders, and
  `Paginatable` pages by fetching one extra row (prev/next) instead of
  counting.
- Aggregates are cached per tenant, range and filters via `cached_stats`
  (30 s for "today", 1 to 5 minutes otherwise).

**Smaller fixes.** Filter dropdowns use `Execution.distinct_values`, a
recursive index walk costing one probe per distinct value in place of
`SELECT DISTINCT` over the table. The three copies of the pagination markup
became `shared/_pagination`. The chart endpoints declare `format: :json`.

Same table and hardware with the new index. "First view" is with nothing
cached; "repeat view" is the same page again within the cache TTL.

| Page | Before | First view | Repeat view |
|------|--------|------------|-------------|
| Executions list (default) | 43 s | 1.4 s (1 s of it the totals budget) | 0.03 s |
| Executions list, last 7 days | 1.7 s | 0.16 s | 0.04 s |
| Agents list | 366 s | 0.6 s | 0.05 s |
| Agent page | 125 s | 1.6 s | 0.01 s |
| Dashboard, today / 30 / 90 days | 2.5 / 18 / 42 s | 0.24 / 1.4 / 2.6 s | 0.05 s |
| Analytics, 30 / 90 days | 13 / 51 s | 0.7 / 3.0 s | 0.04 s |
| Requests list | 54 s | 1.1 s | 0.06 s |
| Tenants list / tenant page | 38 / 72 s | 0.1 / 0.4 s | 0.1 / 0.04 s |

Without the index the bounded pages are still fast (agents list 1.9 s, tenants
list 0.1 s, requests list 1.1 s), but 30-day ranges take 4 to 7 s and 90-day
ranges hit the query timeout.

## Consequences

- Host apps should run `rails generate ruby_llm_agents:upgrade` and migrate to
  get `idx_executions_analytics`. It is built `CONCURRENTLY` on PostgreSQL
  (the migration disables its DDL transaction); expect it to take about as
  long as any other index on that table. Everything works without it, slower.
- **Figures that used to be all-time are now windowed**, and labelled as such
  in the views: agents list (30 days), agent page headline stats (30 days),
  tenant page totals and usage tables (this month), tenants list cost (month
  to date). `Execution.stats_for(..., period: :all_time)` and the `Tenant`
  usage methods are unchanged for callers who want all-time numbers.
- On a table too large to total within a second, the executions list shows
  "totals: pick a time range" and prev/next pagination until a time filter is
  chosen. Sorting the whole table by cost or duration with no time filter can
  hit the query timeout; with a time filter it is fast.
- Filter dropdowns list agent types and models across all tenants, not only
  the selected tenant's. Narrowing them meant reading every execution that
  tenant has.
- Dashboard figures can be up to 30 seconds ("today") or 5 minutes (wider
  ranges, agents list) stale. Apps whose `Rails.cache` is a `NullStore` see no
  caching and pay for each view.
- Dashboard GET requests run inside a transaction on PostgreSQL (that is what
  scopes the timeout). A handler that rescues a cancelled query and keeps
  querying would find the transaction aborted, so controller-level rescues
  re-raise `ActiveRecord::QueryCanceled`.
- `Paginatable#paginate` no longer counts when `total_count:` is omitted; the
  pagination hash gains `:next_page` and may carry nil totals.
- Agent page no longer assigns `@models`, `@temperatures`, `@avg_ttft`,
  `@status_distribution` or `@finish_reason_distribution`. A host app that
  overrides that view and reads them needs to compute them itself.
- Ranges wider than the data that fits a few seconds of index scan (roughly
  90 days at 50k executions a day) are the next limit. Past that the answer is
  a rollup table maintained at write time; `Execution.breakdown` is the seam
  it would sit behind.
- The PostgreSQL-only paths (statement timeout, `INCLUDE` index, concurrent
  build) have specs that skip on SQLite. They were run against PostgreSQL 16
  for this change; CI still does not.
