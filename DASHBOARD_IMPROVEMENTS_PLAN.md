# RubyLLM::Agents – Dashboard Improvements Plan

Status: Draft
Owner: Core Maintainers
Target Version: 0.3.x
Last Updated: 2025-11-26

## 1) Objectives & Success Criteria

Objectives
- At-a-glance observability: Provide clear daily health, cost, and error signals.
- Faster debugging: Reduce time-to-root-cause for failed/slow/expensive executions.
- Governance visibility: Make budgets, alerts, and circuit breakers obvious and actionable.
- Usability & performance: Keep interactions under 200ms where possible; intuitive flows.

Success Criteria (quantitative)
- 50% reduction in median time spent investigating a failed execution (measured by click depth and dwell).
- < 2 seconds to render overview and agents pages under P95 load (with cached aggregates).
- CSV export for filtered executions consistently under 5 seconds for 10k rows (server-side paginated generation).
- > 80% task success rate in hallway tests for: “find why an agent is failing,” “confirm if budget exceeded,” and “compare versions.”

Non-goals
- Full BI-grade reporting (exports allow external analysis).
- Non-Rails host support (Rails is a requirement).
- Fine-grained per-tenant dashboards (may be added later).

## 2) Personas & Jobs-To-Be-Done

- SRE/Platform:
  - “Is anything on fire? Are breakers open? Are timeouts spiking?”
- Product owner/Manager:
  - “What’s our spend today and this month? Which agents cost most?”
- Application engineer:
  - “Why did this execution fail? Which attempt succeeded? How do I rerun?”
- Data/Analytics:
  - “Export execution slices for deeper analysis.”

## 3) Information Architecture

- Overview (Home)
  - KPIs: total executions, success rate, failures, cost, tokens, P95 duration.
  - Open circuit breakers strip.
  - Budget usage bars (daily/monthly).
  - Activity charts (Executions and Cost toggle).
  - Alerts feed (budget/breaker/anomalies).

- Agents
  - Hero metrics (success, failures, P95/P50 duration, tokens/sec).
  - Configuration panel (model, temperature, timeout, caching, retries/circuit breaker).
  - Circuit breaker status by model/fallback.
  - Version comparison (select v1 vs v2).
  - Trends (7/30-day executions and cost).
  - Actions: Rerun latest with params; open playground.

- Executions
  - Filters: agent, status chips, time range presets, version, model, temperature.
  - Search: free-text across error_class/message/params keys.
  - Saved filters (localStorage or DB).
  - Table: timestamp, agent, status, cost, tokens, duration, model, version, attempts.
  - Inline row expansion (attempts summary).
  - Export CSV for filtered scope.

- Execution Detail
  - Attempts timeline (per-attempt model, status, duration, tokens, error badge).
  - Chosen (successful) attempt marked clearly.
  - Prompts & Response panels (masking/unmasking with copy buttons).
  - Cost breakdown (per-attempt and totals).
  - Diagnostics panel (breaker/timeout/budget notes).
  - Actions: Rerun (dry-run and real), Open in Playground with prefilled params.

- Governance
  - Budgets dashboard (daily/monthly global + top agents).
  - Forecast (simple linear projection based on last 7 days).
  - Alerts feed with filters (by type, agent).
  - Circuit breaker monitor (open breakers, cooldown timers, historical opens last 24h).

## 4) UX/Interaction Principles

- Consistency:
  - Status colors: success (green), error (red), timeout (yellow), running (blue).
- Progressive disclosure:
  - Summaries first; drill-downs reveal details (attempts, prompts).
- Fast feedback:
  - Turbo Stream updates for KPIs, alerts, and execution changes.
- Empowerment:
  - Shortcuts (rerun, playground) available where context is clear.
- Accessibility:
  - Keyboard navigable filters and tables; proper headings/labels/roles.

## 5) UI Components (Planned)

Overview
- StatCard (KPI) with delta vs previous day.
- BudgetsBar (daily, monthly) with cap markers (soft/hard colors).
- BreakerStrip: pill list with agent/model and cooldown countdown.
- ActivityChart: toggle between executions and cost; show P95 badge.
- AlertsList: streaming, filterable by type/agent.

Agents
- AgentHero: summary metrics, RAG of success/error.
- AgentConfigPanel: model/temperature/timeout/caching/retry/circuit breaker info.
- BreakerStatusList: per model/fallback state.
- VersionCompare: selector for two versions + metrics table (avg cost, tokens, P95).
- TrendsChart: executions and cost for 7/30 days.
- ActionsBar: rerun last, open playground.

Executions
- FiltersBar: status chips, time presets, multi-select agent/version/model/temp.
- SearchBox with debounce and highlight in results.
- SavedFilters dropdown (persisted).
- ExecutionsTable: columns incl. attempts; row expansion for quick attempt view.
- ExportButton: CSV of filtered scope.

Execution Detail
- AttemptsTimeline with badges and durations.
- PromptsPanel: system and user prompts (masked by default).
- ResponsePanel: highlighted JSON, masked by default.
- CostBreakdown: per-attempt chips + totals.
- DiagnosticsPanel: breaker/budget/timeout annotations.
- Actions: Rerun buttons.

Governance
- BudgetsCards: global and per top-N agents (usage vs cap).
- ForecastWidget: month projection.
- GovernanceAlerts: filterable stream.
- BreakerMonitor: open breakers with cooldown timers and history.

## 6) Backend & Data Requirements

Queries & Endpoints
- Aggregates (cached):
  - Today KPIs: count, successful, failed, avg & P95 duration, cost, tokens.
  - Hourly activity series (executions and cost).
  - Per-agent summaries (for agents page).
- Executions listing:
  - Filter by agent/status/time/version/model/temp.
  - Free-text search: error_class, error_message, parameters (JSONB), metadata fields.
  - Return attempts_count and chosen_model_id for table display.
- Execution detail:
  - Return attempts array (new JSONB), plus normalized token/cost totals.
- Governance:
  - Budget usage values (daily/monthly) from counters.
  - Breaker states from cache keys.
  - Alerts fetch from persisted alerts table (optional) or event stream (cache backed).

Database & Indexing
- Existing: add `attempts`, `attempts_count`, `chosen_model_id`, `fallback_chain` (JSONB).
- Index `attempts_count`, `chosen_model_id`.
- Optional (Postgres): GIN indexes for `parameters` and `metadata` to speed search.
- Consider partial indexes for `status = 'error'` and `created_at` time windows.

Caching
- Short TTL (30–60s) for dashboard-level aggregates.
- Namespaced keys:
  - stats: ruby_llm_agents:stats:today
  - activity: ruby_llm_agents:activity:YYYY-MM-DD
  - budgets: ruby_llm_agents:budget:{scope}:{window}
  - breaker: ruby_llm_agents:cb:open:{agent}:{model}
- Invalidation:
  - Use time-scoped keys; allow natural expiry to avoid complex invalidation.

CSV Export
- Use streaming CSV or server-side pagination to avoid memory spikes.
- Respect filters and masking based on user role.
- Rate-limit or require admin role (configurable).

## 7) Real-Time Updates

Events to stream
- Execution created/updated (existing broadcast).
- KPIs & activity: re-render minimal areas every N seconds or on thresholds.
- Alerts: new budget or breaker events pushed to AlertsList.
- Governance: breaker open/close events update BreakerStrip/Monitor.

Approach
- Turbo Stream targets per panel (frame or container).
- Lean payloads (HTML partials ideally pre-rendered server-side).
- Throttle updates to avoid reflow storms (e.g., 1–5s debounce on frequent changes).

## 8) Security, Privacy, Authorization

PII Redaction & Masking
- Default mask prompts/responses; toggle to unmask only if authorized.
- Truncate long strings before storing/displaying.
- Field and regex-based redaction configured globally.

Authorization
- Reuse parent controller auth (already supported).
- Add role concept for “can_unmask” and “can_export”.
- Guard CSV export and playground reruns behind roles.

Auditability
- Log rerun actions and exports with user id, timestamp, filter scope.

## 9) Performance & Accessibility

Performance
- Cache aggregates; minimize N+1 queries (use preloads where needed).
- Avoid rendering massive tables; paginate; lazy-load row expansions (attempts).
- Server-render charts with minimal JS config (Chartkick already in use).

Accessibility
- Headings hierarchy consistent per page.
- Buttons and interactive chips have aria-labels.
- Keyboard focus management on filter changes and reruns.
- Sufficient color contrast for badges and charts.

## 10) Testing Strategy

Unit
- Helpers (formatting, number_to_human_short, highlight_json).
- Query builders for filters and searches.
- Budget & breaker presenters (state derivation for UI).

Integration/System (Capybara)
- Overview renders KPIs and reacts to streams.
- Agents page shows version compare; breaker indicator reflects cache state.
- Executions filters combine correctly; search works on errors/params.
- Execution detail shows attempts timeline; rerun buttons function (dry-run in test).
- Governance page displays budgets and alerts; CSV export produces masked output.

Performance
- Request specs that validate page render times under fixture loads (seeded 10k executions).

A11y
- Axe-core automated checks for key pages.

## 11) Rollout Phases

Phase 1 (Quick Wins)
- Executions detail: attempts timeline, masked prompts/response with copy, rerun buttons.
- Executions list: search box, CSV export, inline attempts summary.
- Agents: hero KPIs, breaker indicator, basic version comparison.
- Overview: budgets bars, breaker strip, alerts feed.
- Caching for overview aggregates.

Phase 2
- Trends & toggle between executions and cost on Overview.
- Saved filters; localStorage persistence (or user prefs).
- Forecast widget for budgets.
- Better diagnostics in execution detail (timeout/budget notes).

Phase 3
- Per-tenant scoping (optional).
- Historical breaker analytics (last 7–30 days).
- Playground enhancements (saved sessions, shareable links).
- A/B charting for version traffic splits.

## 12) Acceptance Criteria (Per Phase)

Phase 1
- Attempts timeline is visible and accurate; chosen attempt is clearly indicated.
- Masking defaults ON; authorized users can toggle and export masked/unmasked according to role.
- CSV export respects filters and role-based masking.
- Budgets bars and breaker strip visible on overview with live updates.
- Agents page shows breaker indicator and version comparison (avg cost, P95 duration).

Phase 2
- Overview chart toggles between Executions and Cost; caches are effective.
- Saved filters persist across sessions.
- Budget forecast visible and correct within a small tolerance.

Phase 3
- Playground supports saved sessions; can prefill from an execution.
- Breaker analytics page displays historical opens and resolved states.

## 13) Risks & Mitigations

- Heavy queries on large datasets:
  - Mitigate with caching, pagination, indexes (GIN on JSONB), and preloads.
- Over-streaming causing UI churn:
  - Debounce updates; partial reloads of small components.
- Privacy leakage via exports:
  - Role-based masking enforcement; audit logs; rate-limits.
- Feature creep:
  - Strict scoping per phase with measurable acceptance tests.

## 14) Open Questions

- Should alerts be persisted (DB) or ephemeral (cache)? (Phase 1: ephemeral + optional DB later)
- Do we need user-specific saved filters or global? (Phase 1: localStorage; Phase 2: per-user if demand)
- Should CSV be limited to N rows or streamed fully? (Phase 1: cap at 50k rows; warning banner)

## 15) Implementation Checklist (Phase 1)

- [ ] Add attempts UI to execution detail page
- [ ] Add masked prompts/response with toggle + copy buttons
- [ ] Add rerun buttons (dry-run + real) with confirmation
- [ ] Add search box to executions; extend filtering; inline row expansion
- [ ] Add CSV export (filtered scope; masked by role)
- [ ] Add budgets bars and breaker strip to overview
- [ ] Add alerts feed panel to overview
- [ ] Add hero KPIs and breaker indicator to agent page
- [ ] Add simple version comparison on agent page
- [ ] Cache overview aggregates; validate TTLs
- [ ] Add tests (unit/system/performance/a11y) for new components

End of document.
