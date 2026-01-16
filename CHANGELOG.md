# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
