# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Per-Tenant API Configuration** - New `Configurable` concern for tenant-specific API keys:
  - `configure_api` - Block syntax for configuring tenant API settings
  - `api_key_for(:provider)` - Get API key for a specific provider
  - `has_custom_api_keys?` - Check if tenant has custom API keys
  - `effective_api_configuration` - Get resolved config with fallbacks
  - `configured_providers` - List all configured providers

- **Rate Limiting** - New `Limitable` concern for per-tenant request limits:
  - `rate_limit_per_minute` / `rate_limit_per_hour` columns
  - `can_make_request?` - Check if request is within rate limits
  - `requests_this_minute` / `requests_this_hour` - Current request counts
  - `remaining_requests_this_minute` / `remaining_requests_this_hour` - Remaining quota

- **Feature Flags** - Per-tenant feature toggles via `Limitable` concern:
  - `enable_feature!(:name)` / `disable_feature!(:name)` - Toggle features
  - `feature_enabled?(:name)` - Check if feature is enabled
  - `enabled_features` / `disabled_features` - List all features

- **Model Restrictions** - Per-tenant model access control via `Limitable` concern:
  - `allow_model!("model-id")` / `block_model!("model-id")` - Manage restrictions
  - `model_allowed?("model-id")` - Check if model is allowed
  - `has_model_restrictions?` - Check if any restrictions are set

### Changed

- **Tenant Model Refactor** - Unified tenant management with organized concerns:
  - Renamed `TenantBudget` model to `Tenant` as the central entity for all tenant functionality
  - Added `Budgetable` concern for budget limits and enforcement
  - Added `Trackable` concern for usage tracking (cost, tokens, executions)
  - Added `Configurable` concern for per-tenant API configuration
  - Added `Limitable` concern for rate limits, feature flags, and model restrictions
  - New tracking methods: `usage_by_agent`, `usage_by_model`, `usage_by_day`, `recent_executions`, `failed_executions`
  - New status methods: `active?`, `linked?`, `activate!`, `deactivate!`
  - `TenantBudget` is now an alias for backward compatibility (deprecated, will be removed in future major version)

### Deprecated

- `RubyLLM::Agents::TenantBudget` - Use `RubyLLM::Agents::Tenant` instead
- `llm_budget` association in LLMTenant concern - Use `llm_tenant_record` instead
- `llm_configure_budget` method - Use `llm_configure` instead

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
