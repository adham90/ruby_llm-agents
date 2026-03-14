# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.11.0] - 2026-03-14

### Added

- **`agents` DSL** — Separate DSL for declaring sub-agent delegates, distinct from `tools`. Supports simple form (`agents [AgentA, AgentB], forward: [:workspace_path]`) and block form with per-agent `timeout:` and `description:` overrides, `forward` parameter auto-injection, and `instructions` text
- **`forward` parameter injection** — Auto-injects parent agent params into sub-agent calls and removes them from the LLM-facing tool schema, eliminating token waste and reducing failure points
- **System prompt auto-generation** — Agents with the `agents` DSL automatically get "## Direct Tools" and "## Agents" sections appended to their system prompt, helping the LLM distinguish between cheap local tools and expensive autonomous agents
- **`StreamEvent` value object** — Typed streaming events (`:chunk`, `:tool_start`, `:tool_end`, `:agent_start`, `:agent_end`, `:error`) for full execution lifecycle visibility. Opt-in via `stream_events: true` on `.call()` — default raw chunk behavior unchanged
- **Router auto-delegation** — Routes with `agent:` mapping now automatically invoke the mapped agent after classification. `RoutingResult` exposes `delegated?`, `delegated_to`, `routing_cost`, and `total_cost` for full visibility into the classification + delegation pipeline
- **`OrchestratorAgent` example** — New example agent demonstrating the `agents` DSL with block form, `forward`, and `instructions`

## [3.10.0] - 2026-03-13

### Added

- **`RubyLLM::Agents::Tool` base class** — Extends `RubyLLM::Tool` with agent context access, per-tool timeouts, and automatic error handling. Users implement `execute()` (standard RubyLLM convention) while `call()` wraps with context, timeout, and error recovery
- **`ToolContext` accessor** — Read-only context wrapper providing method-style (`context.container_id`) and hash-style (`context[:container_id]`) access to agent params, tenant ID, and execution ID from within tools
- **Per-tool timeout DSL** — `timeout 30` class-level DSL on tools, with `config.default_tool_timeout` global fallback
- **`ToolExecution` model** — Real-time per-tool tracking with individual database records (INSERT on start, UPDATE on complete), enabling live dashboard views and queryable tool-level analytics
- **Cancellation support** — `on_cancelled:` proc checked before each tool execution. Raises `CancelledError` which `BaseAgent` catches to return `Result` with `cancelled? = true`
- **`Result#cancelled?`** — Query whether an agent execution was cancelled mid-run
- **Example coding agent** — `CodingAgent` with `FileReaderTool` demonstrating tool context and timeout features

### Fixed

- **Undefined method `error?` on Context** — Fixed budget middleware breaking tenant budget tracking when `Pipeline::Context` lacked the `error?` method

## [3.9.0] - 2026-03-09

### Added

- **`RubyLLM::Agents.track` block API** — Group multiple agent executions into a single tracked request with `request_id` and tags. Includes `Tracker` and `TrackReport` classes for aggregated cost/token analytics
- **Requests dashboard** — New dashboard page for viewing and filtering tracked request groups with per-request detail views
- **Convenience query API** — `RubyLLM::Agents.executions`, `.recent`, `.for_agent`, `.for_model` class-level query methods for accessing execution data from host apps
- **`doctor` generator** — `rails generate ruby_llm_agents:doctor` validates installation, configuration, database tables, and RubyLLM connectivity
- **`demo` generator** — `rails generate ruby_llm_agents:demo` scaffolds a working example agent with demo rake task
- **Structured logging & pipeline tracing** — Middleware base class now provides structured `log_info`/`log_warn`/`log_error` helpers with trace context for debugging pipeline execution
- **Trackable results** — All `Result` subclasses register with the active tracker for automatic request-level aggregation
- **Wiki guide** — "Using Data In Your App" wiki page documenting the convenience query API

### Changed

- **Modernized generators** — Agent and install generators produce cleaner, DSL-focused templates with better inline documentation
- **Improved error messages** — Actionable error messages for common configuration mistakes (missing API key, missing model, etc.)
- **README quickstart** — Streamlined golden-path getting started section
- **Bumped ruby_llm dependency** to v1.13.2

### Fixed

- **Tenant API keys** — Use `RubyLLM::Context#chat` instead of passing context as keyword arg, fixing tenant-scoped API key isolation
- **Test isolation** — Fixed `verify_partial_doubles` issues in specs

## [3.8.0] - 2026-03-06

### Added

- **Inception Labs Mercury provider** — New provider for diffusion-based LLMs via Inception Labs API. Includes model registry, capabilities detection, and chat integration. Configure with `config.inception_api_key`
- **AgentRegistry service** — Centralized agent discovery combining filesystem scanning with execution history for dashboard agent listings
- **Dashboard performance indexes** — New composite indexes (`[status, created_at]`, `[model_id, status]`, `[cache_hit, created_at]`) for dashboard query optimization. Available via upgrade generator

### Changed

- **Dashboard query optimization** — Rewrote analytics queries to use SQL `GROUP BY` with conditional aggregation instead of loading records into Ruby. Reduces dashboard page load from ~75 SQL queries to ~10
- **Thin controllers** — Extracted query logic from dashboard and agents controllers into models and AgentRegistry service
- **Consolidated instrumentation** — Deprecated legacy `Instrumentation` module in favor of pipeline middleware, DRY'd up shared logic
- **Thread-safe tenant API keys** — Store tenant API keys on pipeline context instead of mutating global configuration

### Fixed

- **Code quality** — Fixed error logging, race conditions in budget tracking, tenant scoping, XSS in views, and test mock violations
- **Flaky test** — Fixed `tenant_auto_create_spec` test pollution from leaked `track_executions` config
- **Test coverage** — Added specs for TenantsController, SystemConfigController, ExecutionDetail, and Mercury provider

## [3.7.2] - 2026-03-05

### Fixed

- **Fix missing trace_id and request_id extraction in pipeline instrumentation middleware** — The instrumentation middleware was not properly extracting `trace_id` and `request_id` from the pipeline context, causing these fields to be missing in execution logs.

## [3.7.1] - 2026-02-25

### Fixed

- **Upgrade generator missing usage counter columns migration** — The upgrade generator had a template for adding usage counter columns (`monthly_cost_spent`, `daily_cost_spent`, etc.) to the tenants table but never wired it into the generator steps. Users upgrading from older versions would hit `PG::UndefinedColumn` errors on the dashboard. Running `rails generate ruby_llm_agents:upgrade` now correctly detects and generates the missing migration.

## [3.7.0] - 2026-02-21

### Added

- **Evaluation framework** — New `RubyLLM::Agents::Eval` module for testing and benchmarking agents:
  - `EvalSuite` — Define test cases with expected outputs, run evaluations with built-in scorers (exact match, includes, semantic similarity, custom), and generate summary reports
  - `EvalResult` — Structured result objects with pass/fail status, scores, and metadata
  - `EvalRun` — Batch evaluation runner with parallel execution support and aggregate statistics
- Evaluation examples in example app (`SchemaAgentEval`, `SupportRouterEval`)
- Evaluation framework documentation in README, wiki, and LLMS.txt
- Comprehensive unit and integration specs for eval framework components

### Fixed

- Dashboard overview stats overflow on mobile viewports

### Removed

- Dead redaction references left over from v3.0.0 removal

## [3.6.0] - 2026-02-21

### Added

- **Agent-as-tool composition** — Wrap any agent as a RubyLLM tool with `AgentTool` adapter. Use `tools AgentTool.from(OtherAgent)` to let agents call other agents. Execution hierarchy tracked via `parent_execution_id` in metadata
- **Queryable agents** — Query execution history directly from agent classes: `.executions`, `.last_run`, `.failures(since:)`, `.total_spent(since:)`, `.stats(since:)`, `.cost_by_model(since:)`, `.with_params(**params)`. Includes replay support for A/B testing models on real inputs
- **ActiveSupport Notifications** — Instrument the full pipeline with `ruby_llm_agents.*` events:
  - Execution lifecycle: `execution.start`, `execution.complete`, `execution.error`
  - Cache: `cache.hit`, `cache.miss`, `cache.write`
  - Budget: `budget.check`, `budget.record`, `budget.exceeded`
  - Reliability: `reliability.fallback`, `reliability.exhausted`
- **Custom middleware** — Inject custom middleware into the pipeline globally via `config.middleware` or per-agent via `middleware` DSL. Supports `before`/`after`/`around` positioning relative to built-in middleware
- **Agent rename support** — Three complementary approaches for handling agent class renames:
  - **Aliases DSL** — `aliases "OldName", "AnotherOldName"` on agent classes makes `by_agent` scopes, analytics, and budget checks automatically include records from all previous names
  - **Programmatic helper** — `RubyLLM::Agents.rename_agent("Old", to: "New")` updates execution records and tenant budget keys in-place, with `dry_run: true` support
  - **Migration generator** — `rails generate ruby_llm_agents:rename_agent OldName NewName` creates a reversible migration
  - **Rake task** — `rake ruby_llm_agents:rename_agent FROM=Old TO=New [DRY_RUN=1]` as a CLI alternative
- **Debugging helpers** — `Configuration#to_h`, `BaseAgent.config_summary`, `Result#execution` for console inspection
- **Parameter descriptions** — `desc:` / `description:` keyword on `param` DSL for documenting agent parameters
- **Dashboard enhancements** — Custom date range picker for stats/charts, cache savings display, top tenants overview, favicons

### Changed

- Tenant middleware now supports objects responding to `llm_tenant_id` in addition to string/symbol tenant IDs
- Deep symbolize hash keys in agent response processing for consistent access patterns
- Replaced test doubles with real objects across spec suite for more reliable tests

### Removed

- Dead code cleanup: removed unused `Reliability::Executor` sub-classes, duplicate error classes, orphaned `async_max_concurrency` config, unimplemented redaction stub, hardcoded pricing constants, dead `Pipeline` convenience methods and `Instrumentation` diagnostic methods

## [3.5.5] - 2026-02-19

### Changed

- **Include agent metadata in instrumentation middleware** — The instrumentation middleware now merges agent-defined `metadata` (from the agent's `metadata` method) into execution records. Agent metadata serves as a base layer, with middleware metadata overlaid on top. This makes custom agent metadata visible on the dashboard immediately, without requiring a separate `process_response` override

## [3.5.4] - 2026-02-19

### Fixed

- **Fix CI failures in embedder/transcriber specs** — Replaced config test doubles with real `RubyLLM::Agents.configuration` objects. The doubles were missing `current_tenant_id` (added in v3.5.3), causing 38 test failures across all Ruby versions

## [3.5.3] - 2026-02-19

### Fixed

- **Fix tenant resolver fallback in Tenant middleware** — When `multi_tenancy_enabled = true` and a `tenant_resolver` is configured, calling an agent without an explicit `tenant:` option now correctly falls back to the configured resolver. Previously, the resolver was never consulted, resulting in `tenant_id = nil` on the Execution record ([#12](https://github.com/adham90/ruby_llm-agents/issues/12))

## [3.5.2] - 2026-02-18

### Fixed

- **Fix `NoMethodError` for `turbo_stream` in API-only apps** — `ExecutionsController` now guards `format.turbo_stream` behind a `turbo_stream_available?` check (`defined?(Turbo)`). Apps without `turbo-rails` installed no longer crash when accessing the dashboard ([#11](https://github.com/adham90/ruby_llm-agents/issues/11))

## [3.5.1] - 2026-02-18

### Fixed

- **Fix `default_model` not passed to RubyLLM.chat** — `build_client` now passes the model directly to `RubyLLM.chat(model:)` instead of chaining `.with_model()` afterward. This prevents `Chat#initialize` from falling back to `gpt-5-nano` and triggering `ConfigurationError: Missing configuration for OpenAI` when using non-OpenAI models ([#10](https://github.com/adham90/ruby_llm-agents/issues/10))

## [3.5.0] - 2026-02-18

### Added

- **Multi-source pricing cascade** — New `Pricing::DataStore` with two-layer cache (in-memory + Rails.cache) fetches pricing from 7 sources: user config, RubyLLM gem, LiteLLM, Portkey AI, OpenRouter, Helicone, and LLM Pricing AI. Lazy cascade stops at first match to minimize HTTP calls
- **6 pricing adapters** — `LiteLLMAdapter`, `PortkeyAdapter`, `OpenRouterAdapter`, `HeliconeAdapter`, `LLMPricingAdapter`, `RubyLLMAdapter` each normalize source-specific pricing into a common format covering text LLM, transcription, TTS, image, and embedding models
- **Transcription pricing refactored** — `TranscriptionPricing` now uses shared adapters with 7-tier cascade instead of standalone LiteLLM fetch. Supports `input_cost_per_audio_token` for GPT-4o-transcribe models (in addition to `input_cost_per_second`)
- **Per-source configuration** — New config options: `pricing_cache_ttl`, `portkey_pricing_enabled`, `openrouter_pricing_enabled`, `helicone_pricing_enabled`, `llmpricing_enabled`, and URL overrides for each source
- **Integration test framework** — Tests tagged `:integration` hit real pricing APIs (excluded by default, run with `RUN_INTEGRATION=1`). Covers API availability, schema stability, cross-source price consistency, and caching performance
- **Pricing wiki page** — New [Pricing](https://github.com/adham90/ruby_llm-agents/wiki/Pricing) documentation covering all sources, caching, configuration, and debugging
- **Routing concern** — Lightweight `include RubyLLM::Agents::Routing` concern for message classification. Define routes with `route` DSL, classify input with `classify(message)`, and get structured `Routing::Result` objects with destination, confidence, and metadata
- **Dashboard router support** — Router agent type shown in agent index with dedicated config panel displaying route definitions, default route, and confidence threshold
- **Dynamic release command** — `/release` command now auto-detects version bump type by analyzing commits, CHANGELOG sections, and file changes since the last tag

### Changed

- User config now has **highest priority** in transcription pricing cascade (was #2, now #1)
- `TranscriptionPricing.refresh!` now clears all pricing source caches via `DataStore.refresh!`
- `TranscriptionPricing.all_pricing` returns data from all 7 sources

## [3.4.0] - 2026-02-18

### Added

- **ElevenLabs ModelRegistry** — Fetches and caches model data from ElevenLabs `/v1/models` API using the user's API key. Provides model capability queries: TTS support, voice conversion, cost multiplier, max characters, languages, style/speaker_boost support
- **Dynamic ElevenLabs pricing** — New Tier 3 in the pricing cascade uses `character_cost_multiplier` from the API × configurable `elevenlabs_base_cost_per_1k` base rate (default: $0.30). Replaces hardcoded per-model prices with live API data
- **`elevenlabs_base_cost_per_1k` config** — Configurable base cost per 1K characters for ElevenLabs pricing (default: 0.30, Pro plan overage rate). Users on different plans override just this one number
- **`elevenlabs_models_cache_ttl` config** — Cache TTL in seconds for ElevenLabs model data (default: 21,600 = 6 hours)
- **28 native ElevenLabs output formats** — Full pass-through support for ElevenLabs-native format strings (e.g., `mp3_44100_192`, `pcm_16000`, `opus_48000_64`, `wav_22050`). Users can now request specific quality levels directly
- **Expanded format convenience map** — Simple symbols `:wav`, `:opus`, `:alaw` now map to appropriate ElevenLabs native formats. Unsupported formats (`:ogg`, `:flac`, `:aac`) gracefully fall back to MP3
- **ElevenLabs model validation** — Speaker validates ElevenLabs models before API calls: raises `ConfigurationError` for non-TTS models (speech-to-speech), warns on text exceeding `maximum_text_length_per_request`, warns on unsupported `style` voice settings
- **Native format MIME types** — `SpeechResult#content_type` now handles ElevenLabs native format strings (e.g., `mp3_44100_128` → `audio/mpeg`, `opus_48000_64` → `audio/opus`, `ulaw_8000` → `audio/basic`)

### Changed

- SpeechPricing cascade expanded from 3 tiers to 4: LiteLLM → user config → **ElevenLabs API** → hardcoded fallbacks
- `ELEVENLABS_FORMAT_MAP` expanded from 3 entries to 10 convenience mappings
- Default PCM format mapping changed from `pcm_44100` to `pcm_24000` (more standard for TTS)

## [3.3.0] - 2026-02-17

### Added

- **Dashboard audio player** — Speaker/Narrator execution detail pages now render an HTML5 `<audio>` player when audio data is available, with metadata display (duration, format, file size, voice, provider)
- **`persist_audio_data` config option** — Opt-in setting (`config.persist_audio_data = true`) to store TTS-generated audio as base64 data URIs in the `execution_details.response` JSON column. Default: `false`
- **Audio URL auto-persistence** — `audio_url` from SpeechResult is always stored in execution details (lightweight, no binary), enabling playback from ActiveStorage or external URLs without enabling `persist_audio_data`
- **ActiveStorage support for Speaker** — `Speaker::ActiveStorageSupport` module for attaching generated audio to ActiveStorage

### Changed

- SpeechResult `audio_url`, `audio_key`, `audio_path` changed from `attr_reader` to `attr_accessor` to support post-creation URL assignment (e.g., after ActiveStorage upload)
- SpeechResult `content_type` and `mime_type_for_format` are now public methods

## [3.2.0] - 2026-02-17

### Added

- **Direct TTS HTTP client** — Speaker now uses a direct Faraday-based `SpeechClient` instead of the non-existent `RubyLLM.speak()`, making text-to-speech work at runtime
- **OpenAI TTS support** — Full support for `tts-1` and `tts-1-hd` models via OpenAI's `/v1/audio/speech` endpoint
- **ElevenLabs TTS support** — Full support for all ElevenLabs model generations: v1 (`eleven_monolingual_v1`, `eleven_multilingual_v1`), v2 (`eleven_multilingual_v2`, `eleven_turbo_v2`, `eleven_flash_v2`), v2.5 (`eleven_turbo_v2_5`, `eleven_flash_v2_5`), and v3 (`eleven_v3`)
- **ElevenLabs configuration** — New `elevenlabs_api_key` and `elevenlabs_api_base` config options for ElevenLabs API access
- **TTS pricing cascade** — `SpeechPricing` module with 3-tier pricing resolution: LiteLLM JSON (future-proof), user-configurable `tts_model_pricing` overrides, and hardcoded per-model fallbacks
- **`tts_model_pricing` config** — Override TTS pricing per model via `config.tts_model_pricing = { "tts-1" => 0.015 }`
- **`default_tts_cost` config** — Fallback cost per 1K characters for unknown models
- **`UnsupportedProviderError`** — Raised when a TTS provider is not `:openai` or `:elevenlabs`
- **`SpeechApiError`** — Raised when a TTS API returns an HTTP error, includes `status` and `response_body` attributes

### Fixed

- **Speaker runtime crash** — `RubyLLM.speak()` does not exist in ruby_llm v1.12.0; replaced with direct HTTP client
- **ElevenLabs had no backing implementation** — ElevenLabs was referenced in the DSL but had no actual API integration

### Changed

- Speaker specs rewritten to use WebMock HTTP stubs instead of method-level mocks, testing real code paths
- Removed `MockSpeechResponse` and `RubyLLM.speak` mock from test support
- `calculate_cost` now delegates to `SpeechPricing` module with differentiated ElevenLabs pricing (flash/turbo at $0.15/1K, premium at $0.30/1K)

## [3.1.0] - 2026-02-16

### Added

- **Assistant prompt persistence** — The `assistant_prompt` value from the `assistant` DSL is now stored in `execution_details` alongside `system_prompt` and `user_prompt`, and displayed on the execution detail page in the dashboard
- **Pipeline prompt persistence** — Pipeline middleware instrumentation now persists all three prompts (system, user, assistant) when `persist_prompts` is enabled; previously only core instrumentation saved prompts
- **Gruvbox dark theme** — Dashboard dark mode now uses a warm Gruvbox-inspired color palette via CSS custom properties
- **Auto-create Tenant record** — When a pre-existing host model (e.g., `Organization`) is passed to an agent via multi-tenancy, the corresponding `Tenant` record is automatically created if it doesn't exist

### Fixed

- **Cache key collision** — `assistant_prompt` is now included in `cache_key_data`, preventing two calls that differ only by assistant prefill from incorrectly sharing a cached response
- **Upgrade generator for assistant_prompt** — New idempotent migration template (`add_assistant_prompt_migration.rb.tt`) ensures existing installs get the column on upgrade

## [3.0.0] - 2026-02-16

### Breaking Changes

- **Block form removed** — `system do ... end`, `user do ... end`, and `prompt do ... end` are no longer supported. Blocks are silently ignored. Use a string argument for static content or a `def system_prompt` / `def user_prompt` method override for dynamic content.
- **`resolve_prompt_from_config` no longer handles Procs** — only string templates are supported. Agents that relied on `Proc`-based prompt configs must migrate to method overrides.

### Changed

- `prompt "..."` now emits a deprecation warning — use `user "..."` instead (alias still works)
- `prompt` kept as permanent deprecated alias for `user`
- `resolve_prompt_from_config` simplified to delegate directly to `interpolate_template`
- Removed internal `@prompt_block`, `@system_block`, and `@prompt_template` storage

## [2.2.0] - 2026-02-16

### Added

- **Three-role prompt DSL** — `system`, `user`, `assistant` class-level methods mirror LLM API terminology (system/user/assistant)
- **`user` DSL** — preferred replacement for `prompt`, with `{placeholder}` auto-registration
- **`assistant` DSL** — define assistant prefill to steer model output format (e.g., `assistant '{"result":'` forces JSON)
- **`.ask(message)` class method** — new API for conversational agents that accept freeform input without needing a `user` template
- **Streaming with `.ask`** — `Agent.ask("question") { |chunk| print chunk.content }`
- **Attachments with `.ask`** — `Agent.ask("describe this", with: "image.jpg")`
- **System prompt placeholders** — `system "Helping {user_name}"` now auto-registers `{placeholder}` params (same as `user`)
- **`#assistant_prompt` instance method** — override for dynamic prefill logic
- **Assistant prefill in LLM calls** — prefill sent as assistant message before completion for response steering

### Changed

- `prompt` is now a backward-compatible alias for `user` (no breaking change)
- `#user_prompt` resolution order: method override > `.ask` message > class template > inherited > error
- `.ask` skips required param validation (template params not needed for freeform input)
- Dry run output now includes `assistant_prompt`

### Deprecated

- `prompt` class-level DSL — use `user` instead (alias still works, will emit warning in v2.3.0)

## [2.1.0] - 2026-02-15

### Added

- Unified API key configuration — configure all LLM provider API keys directly in `RubyLLM::Agents.configure` block (no separate `ruby_llm.rb` initializer needed)
- Upgrade generator suggests consolidating separate `ruby_llm.rb` initializer into unified config

### Fixed

- Missing API key error on fresh install (#5)
- Cost calculation returning zero by using `Models.find` instead of `Models.resolve`
- Tenants nav link hidden when multi-tenancy is disabled
- `_detail_data` extraction in ExecutionLoggerJob

### Changed

- Minimum `ruby_llm` dependency bumped to `>= 1.12.0`
- Cost calculation refactored to use nested pricing objects

## [2.0.0] - 2026-02-14

### Added

- **`before_call` and `after_call` callbacks** - Agent-level hooks that run before and after LLM calls. Use method names or blocks. Callbacks can mutate context, raise to block execution, or inspect responses.
- **Simplified DSL with prompt-centric syntax** - New inline prompt syntax for more concise agent definitions.
- **Execution details table** - Large payloads (prompts, responses, tool calls, error messages) split into a separate `ruby_llm_agents_execution_details` table for better query performance. The executions table stays lean for analytics.
- **Tenants table** - New `ruby_llm_agents_tenants` table with DB counter columns for efficient budget tracking (daily/monthly cost, tokens, executions, errors).
- **Database-agnostic metadata JSON queries** - Helper methods (`metadata_present`, `metadata_true`, `metadata_value`) for querying JSON metadata fields across SQLite and PostgreSQL.
- **Class-level schema DSL** - Define response schemas directly in agent classes.
- **Upgrade generator** - Run `rails generate ruby_llm_agents:upgrade` to automatically migrate from v1.x to v2.0 schema.
- **Single `on_alert` handler** - Simplified alert system replacing the built-in notifiers.

### Changed

- **BREAKING: Schema split** - Execution detail columns (`system_prompt`, `user_prompt`, `response`, `error_message`, `tool_calls`, `attempts`, `fallback_chain`, `parameters`, `routed_to`, `classification_result`, `cached_at`, `cache_creation_tokens`, `messages_summary`) moved from `executions` to `execution_details`. Existing code using these fields on Execution instances still works via delegation.
- **BREAKING: Niche fields moved to metadata JSON** - `time_to_first_token_ms`, `rate_limited`, `retryable`, `fallback_reason`, `span_id`, `response_cache_key` are now stored in the `metadata` JSON column with getter/setter methods.
- **BREAKING: Renamed `execution_metadata` to `metadata`** throughout the codebase and database.
- **Tenant budget tracking** uses DB counter columns instead of querying executions, significantly improving performance.
- **LLMTenant concern** now uses `foreign_key: :tenant_id` instead of polymorphic `as: :tenant_record` for the executions association.
- **Dashboard redesigned** with compact layout, sortable columns on agents/tenants, and improved styling.
- Normalized code style with frozen string literals throughout the codebase.

### Removed

- **BREAKING: Removed workflow orchestration** - The workflow subsystem (`Workflow`, `WorkflowStep`, `WorkflowDiagram`, etc.) has been removed entirely. Use dedicated workflow gems (e.g., Temporal, Sidekiq) for orchestration.
- **BREAKING: Removed `version` DSL method** - Cache keys are now content-based and auto-invalidate when prompts change. Use `metadata` for traceability.
- **BREAKING: Removed `ApiConfiguration` table** - API keys should be configured via environment variables. Per-tenant keys available via `llm_tenant` DSL.
- **BREAKING: Removed built-in moderation system** - Use `before_call` hook for custom moderation.
- **BREAKING: Removed built-in PII redaction** - Use `before_call` hook for custom redaction.
- **BREAKING: Removed image content policy** - Implement content filtering in your application layer.
- Removed `agent_version` column from executions.
- Removed workflow columns from executions.

### Fixed

- Agent show pages crashing due to analytics querying removed columns as SQL columns.
- `with_parameter` scope now correctly queries the `execution_details` table.
- Migration and upgrade path for both fresh installs and version upgrades.
- LLMTenant executions association using correct `tenant_id` foreign key.

### Migration Guide

**Upgrading from v1.x:**

1. Run the upgrade generator:
   ```bash
   rails generate ruby_llm_agents:upgrade
   rails db:migrate
   ```

2. The generator will:
   - Create the `execution_details` table and migrate data from `executions`
   - Create the `tenants` table (if not already present)
   - Remove old columns from `executions`

3. **If you were using `version` DSL:** Remove all `version "X.Y"` calls. Use `metadata` for traceability.

4. **If you were using `ApiConfiguration`:** Move API keys to environment variables.

5. **If you were using moderation/redaction:** Replace with `before_call`/`after_call` hooks.

6. **If you were using workflows:** Migrate to a dedicated workflow library.

## [1.3.4] - 2026-01-29

### Improved

- **AllModelsExhaustedError Messages** - Error message now lists each model's error class and message on separate lines instead of only showing the last error. Includes an `errors` accessor returning structured error data (model, error_class, error_message, error_backtrace).
- **Error Backtrace Capture** - `AttemptTracker` now captures the first 20 lines of each error's backtrace, persisted in the execution's `attempts` JSON column.
- **Execution Dashboard Error Display** - Error column in the attempts table now shows the error class and message visibly (not hidden in a tooltip). Click "Stack trace" to expand the full backtrace inline. Copy buttons for individual traces and all errors.

## [1.3.3] - 2026-01-29

### Fixed

- **Embedder Fallback Model Resolution** - Fixed bug where `execute_batch` ignored `context.model` set by reliability middleware, always using the class-level model. All fallback embedding attempts now correctly use the fallback model instead of re-calling the primary provider.
- **Chat Agent Fallback Model Passthrough** - Fixed `execute` in `core/base.rb` not passing context to `build_client`, causing fallback models to be ignored during chat agent execution.

### Added

- **Three-Model Fallback Chain Specs** - Comprehensive test coverage for multi-model fallback scenarios verifying `last_error` tracking, model switching, and early termination on success.
- **Downstream Model Resolution Specs** - Tests ensuring both chat agents and embedders use `context.model` (not the class-level model) when reliability middleware activates fallback.

## [1.3.2] - 2026-01-28

### Added

- **Per-Model Error Tracking** - Reliability middleware now tracks individual attempts per model using `AttemptTracker`. Each execution record includes detailed per-model attempt data (model_id, timing, tokens, error details, short-circuit status) in the `attempts` JSON column, visible on the dashboard.
- **Non-Fallback Error Handling** - Programming errors (`ArgumentError`, `TypeError`, `NameError`, `NoMethodError`, `NotImplementedError`) now fail immediately without trying fallback models. Configurable via `non_fallback_errors` DSL.
- **Smart Retry Strategy** - When fallback models are configured, transient errors skip retries and move directly to the next model. Retries only occur when no fallbacks are available.
- **Response Persistence** - Instrumentation middleware can now persist LLM response content with automatic redaction of sensitive data.

### Fixed

- **Gemini Quota Errors Now Trigger Fallback** - Added "quota" to default retryable rate limiting patterns so Gemini quota exceeded errors are properly recognized as transient and trigger model fallback.

## [1.3.1] - 2026-01-28

### Fixed

- **Fallback Models Now Work Correctly** - Fixed critical bug where fallback models were never actually used. The `build_client` method was ignoring `context.model` set by the reliability middleware, always using the agent's primary model instead. Now properly uses fallback models when the primary model fails.

### Added

- New test coverage for `build_client` to ensure fallback model support doesn't regress

## [1.3.0] - 2026-01-27

### Added

- **Enhanced Tool Call Tracking** - Comprehensive tool call data capture and display:
  - Track tool call results, status (success/error), duration, and timestamps
  - New `tool_result_max_length` configuration option (default: 10,000 characters) for result truncation
  - Tool tracking callbacks (`on_tool_call`, `on_tool_result`) in BaseAgent
  - Enhanced execution view with status badges, duration badges, result display, and error sections
  - Backward compatible with existing tool call data (missing fields handled gracefully)
  - Example app seeds updated with detailed tool call execution data

### Changed

- Updated `BaseAgent` to capture tool call metadata during execution
- Updated instrumentation middleware to persist enhanced tool call data
- Improved execution show view with expandable tool call sections showing detailed timing and results

## [1.2.3] - 2026-01-27

### Added

- Comprehensive test coverage improvements:
  - Added specs for `ModerationResult` class with threshold and category filtering tests
  - Added specs for `AsyncExecutor` with fiber-based concurrent execution tests
  - Added specs for `IterationExecutor` with collection processing tests
  - Added specs for `ScheduleHelpers` DSL methods (next_weekday_at, next_hour, tomorrow_at, etc.)
  - Added specs for `Notifiers` module and registry wrapper
  - Added specs for `Workflow::Result` with step/branch aggregation tests
  - Added specs for `ThrottleManager` with rate limiting and token bucket tests
  - Enhanced `ImageGenerationResult` specs with data, save, blob, and mime type tests
  - Enhanced `ImageEditResult` specs with comprehensive coverage
  - Enhanced `ImagePipelineResult` specs with transform, background_removal, and caching tests
  - Enhanced `SpeechResult` specs with additional audio format tests

### Changed

- Added VCR and WebMock gems for improved test mocking
- Test coverage improved from 87.91% to 89.05%

## [1.2.2] - 2026-01-27

### Fixed

- Fixed `BudgetTracker` method calls in pipeline budget middleware - was calling non-existent `check!` method instead of `check_budget!`, and `record_spend!` had incorrect argument signature

## [1.2.1] - 2026-01-27

### Fixed

- Fixed autoloading for all subdirectories under `app/agents/` - Previously only `audio`, `image`, `text` subdirectories were namespaced. Now any subdirectory (e.g., `app/agents/embedders/`, `app/agents/tools/`, `app/agents/custom_foo/`) is properly namespaced

### Changed

- Updated `namespace_for_path` in engine to dynamically namespace ALL subdirectories under `app/agents/`
- Simplified `namespace_for` method in configuration to support arbitrary categories using camelize
- Updated documentation comments to reflect new default directory structure (`app/agents/` instead of `app/llm/`)

## [1.2.0] - 2026-01-27

### Added

- **Per-Tenant API Configuration** - New `Configurable` concern for tenant-specific API keys:
  - `configure_api` - Block syntax for configuring tenant API settings
  - `api_key_for(:provider)` - Get API key for a specific provider
  - `has_custom_api_keys?` - Check if tenant has custom API keys
  - `effective_api_configuration` - Get resolved config with fallbacks
  - `configured_providers` - List all configured providers

- **Polymorphic Tenant Support** - Flexible tenant associations for any model

### Changed

- **Tenant Model Refactor** - Unified tenant management with organized concerns:
  - Renamed `TenantBudget` model to `Tenant` as the central entity for all tenant functionality
  - Added `Budgetable` concern for budget limits and enforcement
  - Added `Trackable` concern for usage tracking (cost, tokens, executions)
  - Added `Configurable` concern for per-tenant API configuration
  - New tracking methods: `usage_by_agent`, `usage_by_model`, `usage_by_day`, `recent_executions`, `failed_executions`
  - New status methods: `active?`, `linked?`, `activate!`, `deactivate!`
  - `TenantBudget` is now an alias for backward compatibility (deprecated, will be removed in future major version)
  - Added tenant table rename to upgrade generator for seamless migration

### Deprecated

- `RubyLLM::Agents::TenantBudget` - Use `RubyLLM::Agents::Tenant` instead
- `llm_budget` association in LLMTenant concern - Use `llm_tenant_record` instead
- `llm_configure_budget` method - Use `llm_configure` instead

### Removed

- `Limitable` concern - Rate limiting, feature flags, and model restrictions removed (may return in a future release)

## [1.1.0] - 2026-01-26

### Added

- **Human Approval & Wait Steps** - New workflow DSL for human-in-the-loop workflows:
  - `wait` - Delay execution for a specified duration
  - `wait_until` - Wait until a condition is met with configurable timeout
  - `wait_for` - Wait for human approval with notifications (Slack, Email, Webhook)
- **Sub-Workflow Support** - Compose workflows by nesting other workflows as steps
- **Iteration Support** - Process collections with `each:` option on steps
- **Recursion Support** - Workflows can call themselves with depth limits
- **New Specialized Agents** - `SpecialistAgent` and `ValidatorAgent` for common patterns
- **Email Alerts** - `AlertMailer` for workflow notifications and alerts
- **Refined Workflow DSL** - Declarative workflow definitions with cleaner syntax
- **Workflows Index Page** - Dashboard page with filtering and navigation for workflows
- **Sortable Columns** - Sortable tables across agents, executions, and workflows views
- **Model Stats Dashboard** - Cost breakdown and model statistics in dashboard
- **Upgrade Guide** - Documentation for upgrading from v0.5.0 to v1.0.0

### Changed

- **Directory Structure** - Default root directory changed from `app/llm` to `app/agents`
- **Simplified Namespacing** - Removed `Llm` module nesting from agent and tool classes
- **Image Module Rename** - Renamed `llm/image` modules to `agents/images`
- **Unified Workflow Types** - All workflow types consolidated into single "workflow" category
- **Redesigned Workflow Diagram** - New vertical layout with improved details view
- **Simplified Agent Display** - Removed type badges and colors from agent views

### Fixed

- Added missing `Pipeline::ErrorResult` class for proper optional step failure handling

## [1.0.0-beta.1] - 2026-01-20

### Added

#### New Agent Types
- **Audio Agents** - Full audio processing support:
  - `Transcriber` agent for speech-to-text with DSL, execution tracking, and results
  - `Speaker` agent for text-to-speech synthesis
  - Generators for scaffolding audio agents

- **Image Agents** - Comprehensive image generation and manipulation:
  - `ImageGenerator` agent with config, UI support, and pricing calculations
  - `ImageAnalyzer` agent for image understanding
  - `BackgroundRemover` agent for image editing
  - `ImagePipeline` framework for multi-step image workflows
  - Async/fiber support for concurrent image operations

- **Embedder Agent** - Vector embedding support:
  - Embedder base class with DSL and execution tracking
  - Generators for creating embedding agents

- **Moderator Agent** - Content safety:
  - Input/output safety checks
  - Comprehensive content moderation support

#### Middleware Pipeline Architecture
- **BaseAgent Class** - New flexible agent configuration with DSL modules
- **Middleware Infrastructure** - Pluggable pipeline for agent execution
- All existing agents migrated to new middleware pipeline:
  - Base conversation agent
  - ImageGenerator, Transcriber, Speaker
  - Moderator, Embedder

#### Extended Thinking Support
- **Thinking DSL** - Configure extended reasoning capabilities
- Runtime support for streaming thinking tokens
- Example reasoning agent included

#### Multi-Tenant Enhancements
- **LLMTenant Concern** - Tenant DSL for per-tenant configuration
- **API Keys Support** - Per-tenant API key configuration
- **Execution Limits** - TenantBudget execution limits with DSL support
- Comprehensive budget tracking with multi-tenant support

#### Reliability Improvements
- **Retryable Error Patterns** - Configure custom retryable error patterns in reliability DSL
- **`fallback_provider` DSL** - New method for configuring provider-level fallbacks

#### Workflows & Analytics
- Workflows controller and views for detailed workflow analytics
- Agent sub-type categorization and filtering UI

#### Concurrent Execution
- Async/fiber support for concurrent agent execution
- Parallel agent execution capabilities

### Changed

#### Directory Structure (Breaking)
- **New Root Directory** - All generators now use configurable root (default: `app/llm`)
- Agents organized into `LLM` namespace (e.g., `LLM::Chat::SupportAgent`)
- Documentation and examples updated for new structure

#### Internal Refactoring
- Agent directory structure reorganized
- Cost calculation now rounds to 6 decimals for consistency
- Renamed `test_app` to `example` directory
- Removed `Chat::TestAgent` and related files

### Documentation
- New guides: Audio (`04_audio.md`), Image Generation (`05_image_generation.md`)
- LLM directory restructure guide (`06_llm_directory_restructure.md`)
- Gem internal restructure guide (`07_gem_internal_restructure.md`)
- Updated best practices, queries, config, and generators guides
- Replaced SVG logos with PNG versions

## [0.5.0] - 2026-01-18

### Added

- **Tenant Token Limits** - Explicit tenant configuration resolver with token limit support
- **Database-backed API Configuration** - Store and manage API configurations in the database
- **Tenant Budgets Management** - UI and backend for managing tenant token limits and budgets
- **Conversation Messages Summary** - Display conversation message summaries in agent executions
- **GitHub Wiki Sync** - GitHub Action to auto-sync wiki folder with GitHub Wiki
- **Comprehensive Test Coverage** - New specs for DSL, ReliabilityDSL, Engine, deprecations, migrations, and inflections

### Changed

- Renamed `SettingsController` to `SystemConfigController` for clarity
- Resolved config values now shown with API key visibility toggle in dashboard
- Tenant context resolved before building client in agent initialization

## [0.4.0] - 2026-01-16

### Added

- **Reliability Block DSL** - New grouped syntax for reliability configuration:
  ```ruby
  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    total_timeout 30
    circuit_breaker errors: 10, within: 60, cooldown: 300
  end
  ```
- **Enhanced Execution Model** - New tracked fields:
  - `chosen_model_id` - Final model used (may differ from primary if fallback triggered)
  - `attempts` - JSON array of all attempt details
  - `attempts_count` - Number of attempts made
  - `fallback_chain` - Models attempted in order
  - `fallback_reason` - Why fallback was triggered
  - `cache_hit` - Whether response came from cache
  - `retryable` - Whether error was retryable
  - `rate_limited` - Whether rate limit was hit
  - `tenant_id` - Tenant identifier for multi-tenant apps
- **Multi-Tenancy Support**:
  - `multi_tenancy_enabled` configuration option
  - `tenant_resolver` proc for identifying tenants
  - `TenantBudget` model for per-tenant budget tracking
  - Circuit breaker isolation per tenant
- **New Execution Scopes**:
  - `.by_tenant(id)` - Filter by tenant
  - `.for_current_tenant` - Filter by resolved tenant
  - `.with_tenant` / `.without_tenant` - Presence filters
  - `.cached` / `.cache_miss` - Cache hit filters
  - `.with_fallback` - Executions that used fallback models
  - `.retryable_errors` - Executions with retryable failures
  - `.rate_limited` - Executions that hit rate limits
- **`description` DSL Attribute** - Document agent purpose:
  ```ruby
  class MyAgent < ApplicationAgent
    description "Extracts search intent and filters from user queries"
  end
  ```
- **`cache_for` DSL** - Preferred syntax for cache TTL (replaces `cache`):
  ```ruby
  cache_for 1.hour  # Preferred
  # cache 1.hour    # Deprecated but still works
  ```
- **Parameter Type Validation** - Validate parameter types at call time:
  ```ruby
  param :count, type: :integer, required: true
  param :tags, type: :array
  ```

### Changed

- `cache` DSL method deprecated in favor of `cache_for`
- Result object hash-style access (`result[:key]`) deprecated in favor of `result.content[:key]`
- Execution model now stores more granular reliability metadata

### Fixed

- Circuit breaker state now properly isolated per tenant in multi-tenant mode
- Fallback chain properly records all attempted models

## [0.3.6] - 2026-01-11

### Added

- Nested directory support for agents (e.g., `agents/chat/support_agent.rb` → `Chat::SupportAgent`)
- Generator now supports namespaced agents: `rails g ruby_llm_agents:agent chat/support`
- URL encoding for namespaced agent links in dashboard
- Comprehensive Tools documentation (`wiki/Tools.md`)
- Tools section added to Agent DSL documentation

### Fixed

- Fixed `with_message` → `add_message` API compatibility with ruby_llm gem
- Dashboard now properly displays namespaced agent names with visual hierarchy

### Changed

- Agent generator uses compact class notation (`class Chat::TestAgent`) for namespaced agents

## [0.3.3] - 2025-11-27

### Added

- Tool calls tracking in Result object (`tool_calls`, `tool_calls_count`, `has_tool_calls?`)
- Dedicated `tool_calls` and `tool_calls_count` columns in executions table
- Tool calls display in execution show page
- Migration generator for upgrading existing installations with tool calls columns
- Scopes for filtering executions by tool calls (`with_tool_calls`, `without_tool_calls`)

### Fixed

- Tool calls now properly captured from all responses during multi-turn conversations
- Previously only the final response was captured, missing tool calls from intermediate responses

### Changed

- Instrumentation now uses accumulated tool calls from conversation history
- UI improvements to dashboard and agent views

## [0.3.2] - 2025-11-27

### Added

- `rails-controller-testing` gem for controller spec support
- Result class with rich execution metadata (tokens, cost, timing, model info)

### Fixed

- Controller specs now use anonymous controller pattern to avoid template errors
- Instrumentation specs properly mock the RubyLLM client interface
- ExecutionLoggerJob specs use correct expectation syntax for instance methods
- Analytics spec updated for non-cached hourly_activity_chart method
- Changed `response.is_a?(RubyLLM::Message)` to duck typing in instrumentation to avoid NameError
- Updated test expectations for days filter and invalid status handling

### Changed

- Dashboard controller tests updated to match current `@now_strip` implementation
- Redaction placeholder standardized to `[REDACTED]`

## [0.3.1] - 2025-11-27

### Added

- Attachment support for vision and multimodal agents via `with:` option
- Support for images, PDFs, audio, video, and document files
- Attachments displayed in dry_run response

## [0.3.0] - 2025-11-27

### Changed

- Switch charts from Chartkick to Highcharts with improved defaults
- Redesign dashboard with real-time polling updates
- Various UI improvements and refinements

## [0.2.3] - 2025-11-26

### Added

- Responsive header with mobile menu support
- Streaming and tools support for RubyLLM agents
- Tracing, routing, and caching to executions
- Finish reasons and prompts to analytics UI
- Phase 2 dashboard features (dry-run, enhanced analytics)
- Global configuration settings page to dashboard
- Full agent configuration display on dashboard show page
- Reliability, governance, and redaction features
- Comprehensive YARD documentation across entire codebase

### Changed

- Refactor agent executions filters into components
- Comprehensive codebase cleanup and test coverage improvements
- Set dynamic dashboard ApplicationController with auth

### Fixed

- Instrumentation issue
- Execution error handling and cost calculation bugs
- Reliability nil error
- Turbo error on dry-run button
- Missing helper methods in dynamic ApplicationController

## [0.2.1] - 2025-11-26

### Added

- HTTP Basic Auth support for dashboard

### Changed

- Improved instrumentation

## [0.2.0] - 2025-11-26

### Added

- Dark mode support
- Nil-safe token handling

## [0.1.0] - 2025-11-25

### Added

- Initial release
- Agent DSL for defining and configuring LLM-powered agents
- Execution tracking with cost analytics
- Mountable Rails dashboard UI
- Agents dashboard with registry and charts
- Paginated executions list for agents
- ActionCable real-time updates for executions
- Stimulus live updates for agents dashboard
- Chartkick charts with live dashboard refresh
- Model/temperature filters and prompt details
- Shared stat_card partial for consistent UI
- Hourly activity charts

[3.9.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.8.0...v3.9.0
[3.8.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.7.2...v3.8.0
[3.7.2]: https://github.com/adham90/ruby_llm-agents/compare/v3.7.1...v3.7.2
[3.7.1]: https://github.com/adham90/ruby_llm-agents/compare/v3.7.0...v3.7.1
[3.7.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.6.0...v3.7.0
[3.6.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.5...v3.6.0
[3.5.5]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.4...v3.5.5
[3.5.4]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.3...v3.5.4
[3.5.3]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.2...v3.5.3
[3.5.2]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.1...v3.5.2
[3.5.1]: https://github.com/adham90/ruby_llm-agents/compare/v3.5.0...v3.5.1
[3.5.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/adham90/ruby_llm-agents/compare/v2.2.0...v3.0.0
[2.2.0]: https://github.com/adham90/ruby_llm-agents/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/adham90/ruby_llm-agents/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.4...v2.0.0
[1.3.4]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.2...v1.3.3
[3.11.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.10.0...v3.11.0
[3.10.0]: https://github.com/adham90/ruby_llm-agents/compare/v3.9.0...v3.10.0
[1.3.2]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/adham90/ruby_llm-agents/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/adham90/ruby_llm-agents/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/adham90/ruby_llm-agents/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/adham90/ruby_llm-agents/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/adham90/ruby_llm-agents/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/adham90/ruby_llm-agents/compare/v1.0.0...v1.1.0
[1.0.0-beta.1]: https://github.com/adham90/ruby_llm-agents/compare/v0.5.0...v1.0.0-beta.1
[0.5.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.3.6...v0.4.0
[0.3.6]: https://github.com/adham90/ruby_llm-agents/compare/v0.3.3...v0.3.6
[0.3.3]: https://github.com/adham90/ruby_llm-agents/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/adham90/ruby_llm-agents/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/adham90/ruby_llm-agents/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.1...v0.2.3
[0.2.1]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/adham90/ruby_llm-agents/releases/tag/v0.1.0
