# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[2.1.0]: https://github.com/adham90/ruby_llm-agents/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.4...v2.0.0
[1.3.4]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/adham90/ruby_llm-agents/compare/v1.3.2...v1.3.3
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
