# Dashboard query performance (executions list and related pages)

## Context

`GET /agents/executions` was slow and returned 500s on large tables. Tracing
the request showed 12 SQL statements, four of them full scans of the executions
table, plus one query that loaded every large payload column for the visible
page:

- `SELECT DISTINCT agent_type` and `SELECT DISTINCT model_id` — unbounded scans,
  no usable index, run on every page view (a third, `DISTINCT tenant_id`, ran
  from the filters partial).
- The same `COUNT(*)` twice: once in `Paginatable#paginate`, once in
  `load_filter_stats`.
- `SUM(total_cost)` and `SUM(total_tokens)` over the filtered scope. Because
  that scope carried `includes(:child_executions, :detail)`, ActiveRecord's
  `has_include?` branch turned each sum into a `LEFT OUTER JOIN` across both
  associations **without** `DISTINCT` — so the totals were also wrong, inflated
  once per child execution.
- `includes(:child_executions)`, which nothing in the index views reads.
- `includes(:detail)`, which selects `system_prompt`, `user_prompt`, `response`,
  `messages_summary`, `tool_calls` and `attempts` for every row on the page, so
  the list could pull megabytes just to render `error_message` on error rows.
  Image and audio agents store large payloads here; this is the memory blowup
  behind the 500s.
- `executions.empty?` in the list partial issued an extra `SELECT 1` because the
  paginated relation was returned unloaded.

The main list query — `WHERE parent_execution_id IS NULL ORDER BY created_at
DESC` — also had no composite index, only the single-column ones.

A sweep of the other dashboard pages found the same classes of problem:

- **Agents index**: `Execution.stats_for` ran eight separate count/sum/avg
  scans, and the index calls it once per agent (9 queries × N agents).
- **Agent show**: the model/temperature filter options were plucked **without
  DISTINCT** (one row per execution the agent ever ran, into Ruby);
  `avg_time_to_first_token` plucked every streaming execution's metadata JSON
  to average one key; `cache_hit_rate` and `streaming_rate` each ran two
  full-history counts; the executions table repeated the count + two sums and
  had no preload, so error rows N+1'd on the full detail row.
- **Dashboard home**: the recent-executions strip preloaded full detail rows;
  `load_open_breakers` and `AgentRegistry.execution_agents` each ran the
  `DISTINCT agent_type` scan.
- **Analytics**: the same two DISTINCT scans for its dropdowns.
- **Requests index**: `COUNT(DISTINCT request_id)` ran twice (pagination and
  stats strip) plus a separate `SUM`. It also used `GROUP_CONCAT`, which does
  not exist on PostgreSQL, so the page 500'd there.
- **CSV export**: preloaded the full detail row for every execution in each
  1000-row batch.

## Decision

- Added `Execution#error_detail`: the same `has_one` row as `:detail` but
  selecting only `id, execution_id, error_message`. `#error_message` uses it
  unless `:detail` is already loaded. Every list-style view (executions index,
  agent show table, dashboard recent strip, CSV export) preloads this instead
  of the full detail row. `executions#show` keeps `includes(:detail)` and drops
  the unused `:child_executions` preload.
- `Execution.totals` — count, cost and token sums for a scope in one `pick`,
  matching the existing `aggregate_period_stats` pattern. Used by the
  executions and agent show pages, with the count passed to
  `paginate(total_count:)` so the page runs one aggregate query instead of
  four.
- `Execution.stats_for` is one `pick` (was eight queries). `cache_hit_rate` and
  `streaming_rate` are one query each via a shared `boolean_rate`.
  `avg_time_to_first_token` averages a JSON extract in SQL (SQLite
  `json_extract`, PostgreSQL `->>`) instead of loading metadata rows.
- The filter dropdown scans are cached for 5 minutes behind three helpers on
  the engine's `ApplicationController` — `available_agent_types`,
  `available_model_ids`, `available_tenants` — and shared by the executions,
  dashboard and analytics controllers. `AgentRegistry.execution_agents` is
  cached the same way with its own key.
- Agent show filter options use `DISTINCT`.
- Requests index computes its distinct count and cost sum in one `pick` shared
  with pagination, and uses `STRING_AGG(DISTINCT …)` on PostgreSQL.
- `Paginatable#paginate` accepts `total_count:` and loads the page relation.
- New index `[:parent_execution_id, :created_at]`.

Result on the executions list: 12 queries to 7 (3 of which are cached in
production), no large payload columns on the list path, and correct cost/token
totals. Agent show drops from ~30 queries to ~16 with no unbounded row loads;
agents index goes from 9 to 2 queries per agent.

## Consequences

- Host apps should run `rails generate ruby_llm_agents:upgrade` for the
  `add_root_execution_list_index` migration. Existing installs work without it,
  just without the index.
- A newly-seen agent type, model, or tenant takes up to 5 minutes to appear in
  the filter dropdowns and, for history-only (deleted) agents, in the agents
  list. Filtering by it via URL params works immediately. Apps whose
  `Rails.cache` is a `NullStore` see no caching and no change.
- `@filter_stats[:total_cost]` and `[:total_tokens]` now exclude child
  executions, matching the rows the list actually shows. Dashboards comparing
  against the old (inflated) numbers will see them drop.
- `error_detail` selects three columns; reading any other attribute off it
  raises `ActiveModel::MissingAttributeError`. Use `:detail` for anything else.
- The PostgreSQL branches (`STRING_AGG`, `->>` in the TTFT average) follow the
  existing adapter idiom in this codebase but the test suite runs on SQLite
  only, so they are not exercised by CI.
- `spec/support/sql_capture.rb` adds `capture_sql { }` for query-shape
  regressions; the new specs pin query counts and assert that list paths never
  load detail payload columns.
