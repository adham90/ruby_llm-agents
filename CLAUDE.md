# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubyLLM::Agents is a Rails engine gem for building, managing, and monitoring LLM-powered AI agents. It provides a DSL for agent configuration, a middleware pipeline for execution, automatic tracking with cost analytics, and a mountable dashboard UI.

**Requirements:** Ruby >= 3.1, Rails >= 7.0, RubyLLM >= 1.12.0

## Common Commands

```bash
bundle exec rspec                          # Run full test suite (~3700+ specs)
bundle exec rspec spec/agents/routing_spec.rb  # Run a single spec file
bundle exec rspec spec/agents/ -e "parses"     # Run specs matching description
bundle exec standardrb                     # Lint (StandardRB, targets Ruby 3.1)
bundle exec standardrb --fix              # Auto-fix lint issues
bundle exec rake                           # Run both specs and linter (default task)
RUN_INTEGRATION=1 bundle exec rspec        # Include integration tests (skipped by default)
```

**Pre-commit hook:** A git pre-commit hook runs `standardrb --no-fix` and blocks commits on lint failures. Fix with `bundle exec standardrb --fix` before committing.

**CI:** Runs lint on Ruby 3.4, tests on Ruby 3.2/3.3/3.4.

## Architecture

### Class Hierarchy

```
RubyLLM::Agents::BaseAgent        # Core: middleware pipeline, DSL, execute
  └── RubyLLM::Agents::Base       # Adds before_call/after_call callbacks
        └── ApplicationAgent      # User's base class in host app
              └── ConcreteAgent   # User's agent
```

Specialized types (`Embedder`, `Speaker`, `Transcriber`, image agents) also inherit from `BaseAgent` but have their own execution logic.

### Middleware Pipeline

Agent execution flows through a middleware stack assembled by `Pipeline::Builder`:

1. **Tenant** → resolves tenant context
2. **Budget** → checks spending limits, records costs after
3. **Cache** → returns cached result or stores new one
4. **Instrumentation** → logs execution to DB via `ExecutionLoggerJob`
5. **Reliability** → retries, fallback models, circuit breakers
6. **Core executor** → calls the agent's `execute` method (builds messages, calls LLM)

`Pipeline::Context` is the data carrier that flows through each middleware layer.

### Agent DSL

Two layers — both can be mixed:

**Declarative (recommended):** `model`, `temperature`, `system`, `user`/`prompt` (with `{placeholder}` auto-registering params), `assistant` (prefill), `returns` (structured output), `cache for:`, `on_failure { retries/fallback/circuit_breaker }`, `tools`, `streaming`, `before`/`after` callbacks, `aliases` (previous class names for rename tracking).

**Method overrides:** `system_prompt`, `user_prompt`, `process_response(response)`, `messages`, `schema`, `metadata`.

### Database Schema (3 tables, all prefixed `ruby_llm_agents_`)

- **executions** — lean analytics columns (agent_type, model, tokens, costs, timing, status, tenant_id, metadata JSON)
- **execution_details** — large payloads via `has_one :detail` (prompts, response, tool_calls, attempts, fallback_chain)
- **tenants** — multi-tenancy budget tracking (limits, usage counters, enforcement mode)

### Key Directories

```
lib/ruby_llm/agents/
├── core/           # Configuration, version, errors, instrumentation, LLM tenant
├── dsl/            # Base, Reliability, Caching DSL modules
├── pipeline/       # Context, Builder, Executor, middleware/
├── infrastructure/ # Reliability (retry/fallback/circuit breaker), budget, cache, alerts
├── routing/        # Classification concern (ClassMethods, Result)
├── results/        # Result classes for each agent type
├── text/           # Embedder
├── audio/          # Speaker, Transcriber, pricing
├── image/          # Generator, Analyzer, Editor, Transformer, etc.
└── rails/          # Engine

app/
├── models/         # Execution, ExecutionDetail, Tenant, TenantBudget
├── controllers/    # Dashboard, Agents, Executions, Tenants, SystemConfig
├── views/          # ERB templates with Tailwind CSS + Alpine.js
├── services/       # AgentRegistry
└── helpers/

spec/
├── agents/         # Core agent/pipeline/DSL/reliability specs
├── models/         # ActiveRecord model specs
├── controllers/    # Request specs
├── views/          # View specs
├── generators/     # Generator specs
├── migrations/     # Migration upgrade path specs (type: :migration)
├── factories/      # FactoryBot definitions
├── support/        # Schema builder, mock objects, shared examples
└── dummy/          # Minimal Rails app with SQLite in-memory
```

### Example App

Located at `example/` — a full Rails app demonstrating all agent types. Uses `storage/development.sqlite3` (not `db/`). Agents organized in `app/agents/` with subdirectories: `embedders/`, `audio/`, `images/`, `routers/`, `concerns/`.

## Naming Conventions

- **Tables:** `ruby_llm_agents_` prefix
- **Models:** `RubyLLM::Agents::` namespace (e.g., `RubyLLM::Agents::Execution`)
- **Generators:** `RubyLlmAgents::` module (note different casing from runtime namespace)
- **Agent types in app:** `app/agents/` (top-level), `app/agents/embedders/`, `app/agents/audio/`, `app/agents/images/`, `app/agents/routers/`

## Testing Patterns

### Minimize mocks — test real code

**Always prefer exercising real code paths over mocking.** Mocks hide bugs and make tests brittle to refactoring. Only mock when absolutely necessary (external HTTP calls to LLM APIs). Specifically:

- **Do NOT mock** internal classes like `Pipeline::Executor`, middleware, `Result`, DSL methods, or ActiveRecord models. Instantiate real objects and call real methods.
- **Do NOT stub** methods on the class under test. If you need to control inputs, pass them as arguments or set up proper test state.
- **Do NOT replace `RubyLLM::Agents.configuration` with a test double.** Use `RubyLLM::Agents.reset_configuration!` + `RubyLLM::Agents.configure { |c| ... }` to set real config values. Config doubles become stale whenever a new config attribute is added, causing hard-to-diagnose CI failures.
- **DO mock** the external LLM API boundary (`RubyLLM::Chat`, `RubyLLM::Embedding`, etc.) to avoid real network calls. Use the existing helpers in `spec/support/ruby_llm_mock.rb` and `spec/support/chat_mock_helpers.rb`.
- When testing `process_response`, pass a real or simple struct response object directly — don't mock the entire call chain to get there.
- When testing DSL behavior (routes, params, schema), define a real test class with the DSL and assert against its class-level state. No mocks needed.
- For database-touching specs, use FactoryBot and let the real ActiveRecord models run against SQLite in-memory.

The goal: if the real code breaks, the test should break too.

### General setup

- Tests use SQLite in-memory database; schema loaded from `spec/dummy/db/schema.rb`
- `DatabaseCleaner` with transaction strategy (truncation for migration tests)
- `spec/support/ruby_llm_mock.rb` mocks RubyLLM API calls to avoid real LLM requests
- Migration specs (`spec/migrations/`, type `:migration`) use `SchemaBuilder` to rebuild schema at historical versions
- Integration tests require `RUN_INTEGRATION=1` environment variable
- FactoryBot factories in `spec/factories/`
- Shared examples in `spec/support/shared_examples/`
- Ruby 3.4+/4.0 compatibility: `require "ostruct"` explicitly when using OpenStruct in specs
