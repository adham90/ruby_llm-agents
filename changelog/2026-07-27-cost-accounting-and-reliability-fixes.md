# Cost accounting and reliability correctness fixes

## Context

A deep review of cost math, prompt caching, and the middleware pipeline turned
up six defects, all invisible to the 4905-example suite because the specs that
covered them encoded the same wrong assumptions the code did.

1. **`retries` never ran.** `Pipeline::Builder.reliability_enabled?` gated the
   Reliability middleware on `agent_class.retries.is_a?(Integer)`, but that DSL
   reader returns the retry config *Hash*. Only a configured `fallback` pulled
   the middleware into the stack — so `on_failure { retries times: 3 }`,
   circuit-breaker-only, and `total_timeout`-only agents ran with no reliability
   layer at all. The builder specs passed because they used hand-rolled doubles
   whose `.retries` returned an Integer, a shape no real agent has.

2. **Prompt-cache reads were under-billed on every non-Anthropic provider.**
   `#input_cost_for` assumed OpenAI/Gemini fold cache reads *into* `input_tokens`
   and split them back out. RubyLLM 1.16 already reports `input_tokens` net of
   the cache reads for every provider (`Providers::OpenAI::Chat#input_tokens`,
   `Gemini`, `Bedrock`, `OpenRouter` all subtract the cache counters). The gem
   subtracted a second time, clamped the remainder to zero, and billed the real
   uncached input at $0. Measured against `RubyLLM::Cost`: **-23.8%** on
   `gpt-4.1`, **-26.1%** on Bedrock-hosted Claude. Native Anthropic was correct.

3. **A recovered retry was recorded as a failure.** The Reliability middleware
   set `context.error` on a failed attempt and nothing ever cleared it, while
   `Context#success?` requires it to be nil. An execution that failed once and
   then succeeded therefore skipped budget recording (limits were bypassable by
   any agent that blipped), skipped the cache write (`cache_for` silently stopped
   working), was saved green but stamped with an `error_class`, and had its
   `context.model` reverted to the primary even when a fallback won.

4. **`cached_tokens` never reached its column.** Prompt-cache counts landed only
   in the metadata JSON, so `executions/show` — which renders the column —
   displayed "0 cached" for a call that read 6016 tokens from cache.

5. **Cache savings were structurally always $0.** A cache hit makes no API call,
   so its `total_cost` is 0; `cache_savings` summed exactly those rows.

6. **The cache key ignored everything except the user prompt.** Same text prompt
   with a different attachment returned the wrong cached result; an edited system
   prompt served stale answers for the whole TTL; entries were shared across
   tenants.

## Decision

1. `reliability_enabled?` now delegates to `agent_class.reliability_config`, the
   same predicate `Middleware::Reliability` uses on itself, so the builder gate
   and the middleware gate cannot drift apart again. A spec asserts they agree.

2. Deleted `#input_cost_for`, `#cached_input_price` and
   `#cached_tokens_included_in_input?`. Input is charged at the full rate on all
   reported `input_tokens`; cache reads are added on top via the new
   `#cache_read_cost`, which prefers RubyLLM's registry cache-read rate and falls
   back to the full input rate when the registry publishes none — so an unpriced
   model is never billed at zero. `cost_breakdown` metadata no longer carries the
   `cache_read_priced` flag. The pricing spec now asserts agreement with
   `RubyLLM::Cost#total` on real registry models rather than on doubles.

3. `Middleware::Reliability` clears `context.error` at the start of each attempt.

4. `cached_tokens` is persisted on the execution and `cache_creation_tokens` on
   its detail record.

5. `cache_savings[:estimated_savings]` is now the cost *avoided*: hits × the mean
   cost of the misses in the same scope.

6. The cache key includes `tenant_id` and a digest of the response-affecting
   execution options (system prompt, assistant prefill, temperature, schema,
   messages, thinking, attachments, tool names).

7. **Behavior change:** `retries` and `fallback` compose instead of cancelling.
   Each model now exhausts its own retries before the next is tried, matching
   what `wiki/Automatic-Retries.md` has always documented. Previously the mere
   presence of a fallback discarded the retry setting silently.

Also: `model_stats` attributes spend to `COALESCE(chosen_model_id, model_id)` so
a fallback's cost is no longer billed to the primary it fell back from.

## Consequences

- **Reported costs go up** for anyone using prompt caching on OpenAI, Gemini,
  Bedrock or OpenRouter. The old numbers were too low; historical rows are not
  backfilled.
- **API call volume goes up on failure** for agents configuring both `retries`
  and `fallback` — they now get the retries they asked for. `total_timeout` is
  the bound; agents wanting the old fail-fast behavior should set `retries
  times: 0`.
- **Agents with `retries`/`circuit_breaker` but no `fallback` gain a middleware
  layer they never had.** Their executions now record `attempts_count: 1`
  instead of `0`, and transient failures are retried rather than raised.
- **Cache keys change shape, so every existing entry misses once** after upgrade
  and is rewritten. No action needed.
- Budget counters will start incrementing for recovered executions that
  previously slipped through unrecorded.
