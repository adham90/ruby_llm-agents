# Cost-tracking and request-capture fixes (RubyLLM 1.16 follow-up)

## Context

A recall-focused code review of the RubyLLM 1.16 upgrade (PR #34) surfaced five
defects in the new cost-tracking and HTTP-request-timing code. This documents
the fixes and the two behavioral changes worth calling out.

## Decision

1. **Scope `llm_request_count` / `llm_request_ms` to the originating execution.**
   `Instrumentation#capture_llm_requests` subscribed to `request.ruby_llm` on the
   process-global `ActiveSupport::Notifications` bus, so the metric counted HTTP
   requests from executions running concurrently on other threads and from nested
   agent-as-tool sub-agents. It now keeps a fiber-local stack of accumulators and
   credits only the innermost active capture on the thread that emitted the event.

2. **`total_cost` is derived from its components plus recorded extras.**
   `Execution#calculate_total_cost` now computes
   `input_cost + output_cost + sum(metadata["cost_breakdown"])`. The pipeline
   persists `input_cost`/`output_cost` (previously dropped on the async-logging
   path) alongside the cache/reasoning breakdown, and the model derives a
   cache-aware total without a separate guard. With no breakdown this is the
   plain `input + output` sum, so text-only executions are unchanged.

3. **Reasoning tokens are no longer double-charged.** Providers fold reasoning
   tokens into the reported `output_tokens`. When a model prices reasoning
   separately (`reasoning_output != output`, e.g. `perplexity/sonar-deep-research`),
   `calculate_costs` now subtracts the reasoning tokens from the output it prices
   at the output rate, since `extra_token_costs` already charges them at the
   reasoning rate.

4. **`cost_breakdown` reconciles with `total_cost`.** The extra added to the
   total is now the sum of the rounded breakdown components, not the unrounded
   sum, so the stored breakdown adds up to the amount folded into the total.

5. **Swallowed cost errors leave a breadcrumb.** The bare `rescue` clauses in
   `extra_token_costs`/`response_cost` now capture the error and debug-log it
   (when a Rails logger is available) instead of failing silently.

## Consequences

- **Divergence from `RubyLLM::Cost#total`:** RubyLLM's own cost prices the full
  `output_tokens` at the output rate and adds the reasoning component on top
  (double-counting reasoning for separately-priced models). Our `total_cost` is
  now more accurate than `response.cost.total` for those models by the reasoning
  tokens × output-rate amount. This affects only models with
  `reasoning_output != output` (currently just `perplexity/sonar-deep-research`).
- `input_cost`/`output_cost` are now persisted on the async-logging path; the
  Input/Output cost trend charts no longer collapse to zero for those rows.
- No schema changes. `metadata["cost_breakdown"]` is read at save time to derive
  the total.
