# Transcriber uses the shared reliability DSL

## Context

`Transcriber` shadowed the shared `DSL::Reliability` with its own
`ReliabilityConfig` object and duplicated retry/fallback logic inside
`execute`. The `Reliability` middleware expects the Hash config produced by
the shared DSL, so any Transcriber subclass declaring `reliability do ... end`
crashed at runtime with `NoMethodError: undefined method '[]' for
ReliabilityConfig` in `Reliability#build_models_list` (v3.15.0).

## Decision

- Removed `Transcriber::ReliabilityConfig` and the class-level
  `reliability` / `reliability_config` / `fallback_models` overrides — the
  shared `DSL::Reliability` on `BaseAgent` provides the same DSL surface
  (`retries max:/backoff:`, `fallback_models`, `total_timeout`, plus
  `circuit_breaker` and `on_failure`, which the old object never supported).
- Removed the Transcriber's internal retry/fallback loop
  (`execute_with_reliability`, `reliability_max_retries`, `retryable_error?`,
  `calculate_backoff`); the `Reliability` middleware is the single owner of
  retries, fallbacks, and circuit breakers.
- `Transcriber#execute` now transcribes with `context.model`, so per-attempt
  model switching by the middleware actually takes effect.

## Consequences

- `Transcriber.reliability_config` now returns the shared Hash shape
  (`{retries: {max:, ...}, fallback_models: [...], ...}`) instead of a
  `ReliabilityConfig` object, and returns `nil` when nothing is configured.
- Transcribers no longer silently retry 3 times by default when no
  reliability is configured — consistent with every other agent type; opt in
  with `reliability { retries max: 3 }`.
- Attempts/fallbacks are now tracked in execution records like all other
  agents (the internal loop bypassed `AttemptTracker`).
