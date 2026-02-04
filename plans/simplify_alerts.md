# Plan: Simplify Alerts and Notifier Integrations

## Goal
Reduce core gem surface area by removing built-in notifier integrations (Slack/Webhook/Email), while preserving alert functionality via a small, stable event hook API.

## Scope Decisions
- Keep: alert event emission, alert configuration hook, and event payload schema.
- Remove: built-in notifier classes, notifier configs, templates, and specs for Slack/Webhook/Email.
- Add: lightweight event subscription path (config proc and/or ActiveSupport::Notifications).

## Detailed Plan

### 1. Inventory and dependency audit
- Search for alert-related files under `lib/`, `app/`, `config/`, `spec/`, `README.md`, and wiki docs.
- Identify all references to:
  - AlertManager and notifier classes
  - Configuration keys (e.g., `config.alerts`, notifier settings)
  - Any UI elements that display alert settings
  - Tests that assert notifier behavior

### 2. Define the new alert surface
- Decide on a minimal public API:
  - `config.alerts` hook signature `->(event, payload)` (keep or introduce)
  - Event names (e.g., `:budget_soft_cap`, `:budget_hard_cap`, `:execution_error`, `:circuit_open`, `:anomaly`)
  - Standard payload keys (e.g., `:timestamp`, `:tenant_id`, `:agent`, `:model`, `:execution_id`, `:total_cost`, `:duration_ms`, `:error`)
- Decide whether to emit via `ActiveSupport::Notifications` and document event name (e.g., `"ruby_llm_agents.alert"`).

### 3. Refactor alert emission
- Update the alert dispatch path to call the new hook only:
  - If `config.alerts` is set, call it with `(event, payload)`.
  - If `ActiveSupport::Notifications` is used, emit a single standardized notification.
- Ensure all alert-producing code paths funnel through one method to keep behavior consistent.

### 4. Remove notifier integrations
- Delete notifier classes and templates under `lib/ruby_llm/agents/workflow/notifiers/` or any other notifier locations.
- Remove any notifier-specific configuration keys and defaults from configuration.
- Remove any related migrations, generators, or sample code.

### 5. Update docs and README
- Replace “Alerts” docs to explain the hook-based approach with an example.
- Remove Slack/Webhook/Email examples or mention them as external integrations.
- Add a short “Adapters” note to encourage community plugins.

### 6. Update tests
- Remove notifier-specific specs.
- Add tests for:
  - Event hook is called with expected `event` and `payload`.
  - Notifications are emitted (if ActiveSupport::Notifications is used).
  - Alert behavior does not raise when hook is unset.

### 7. Backwards compatibility and upgrade notes
- Add a breaking-change note in `CHANGELOG.md`.
- Provide migration guidance: “Replace `config.alerts` notifier hash with a proc or notification subscription.”

## Acceptance Criteria
- No built-in notifier classes or configs remain in the gem.
- Alerts still fire via a single hook API.
- Tests cover the new event pathway.
- Documentation shows how users can send alerts to Slack/Webhooks/Sentry by subscribing to events.
