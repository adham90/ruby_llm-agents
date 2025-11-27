# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.3.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.1...v0.2.3
[0.2.1]: https://github.com/adham90/ruby_llm-agents/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/adham90/ruby_llm-agents/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/adham90/ruby_llm-agents/releases/tag/v0.1.0
