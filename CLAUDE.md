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

---

## Core Design Principles

### Deep Modules Philosophy

> From John Ousterhout's *A Philosophy of Software Design*: **The best modules are deep — they hide significant complexity behind a simple interface.**

```
Module Depth = (Complexity Hidden) / (Interface Exposed)
```

A **deep module** has a small public API that hides substantial logic. A **shallow module** exposes an interface almost as complex as its implementation. **Do not create shallow modules.**

### Decision Framework: When to Create a New Abstraction

Before creating a new class, module, concern, or middleware, answer:

1. **What complexity does it hide?** If "not much" or "it just delegates," don't create it.
2. **Is the interface simpler than the implementation?** If the public API has as many concepts as the internals, it's shallow.
3. **Does it have a reason to change independently?** If it always changes in lockstep with another module, merge them.
4. **Can I name it with a specific noun/verb?** Vague names (`Manager`, `Handler`, `Processor`, `Utils`) usually signal shallow design.

### Deep vs. Shallow in This Gem

| Layer | Deep | Shallow |
|-------|------|---------|
| **Middleware** | `Reliability` — hides retries, exponential backoff, fallback model switching, circuit breaker state machine | A middleware that just logs and delegates |
| **DSL Module** | `Dsl::Reliability` — simple `on_failure { retries 3 }` hides complex config normalization and validation | A DSL module that wraps a single `attr_accessor` |
| **Concern** | `Execution::Analytics` — hides aggregate queries, trend calculations, grouping logic | `Execution::Timestamps` — just reformats `created_at` |
| **Infrastructure** | `BudgetTracker` — facade hiding query/record/forecast/alert subsystems | A class that just calls `update_column` |
| **Pipeline::Context** | Explicit data carrier — all middleware reads/writes named attributes | Would be shallow if it were just a hash wrapper |
| **Controller** | Intentionally thin — delegates to models. Controllers *should* be shallow in this gem |
| **Job** | `ExecutionLoggerJob` — thin wrapper calling deep model logic (correct; jobs are infrastructure glue) |

### Anti-Patterns to Reject

**Pass-through methods:**
```ruby
# BAD: Wraps a call without hiding anything
class AgentExecutor
  def run(agent, params)
    agent.call(**params)
  end
end
# Just call agent.call(**params) directly.
```

**Premature extraction:**
```ruby
# BAD: Concern used by only one class, hides nothing meaningful
module Pipeline::Middleware::Logging
  def log_start = Rails.logger.info("Starting")
end
# Inline it. Extract when a second middleware needs it.
```

**Needless indirection:**
```ruby
# BAD: Repository pattern over ActiveRecord
class ExecutionRepository
  def find(id) = Execution.find(id)
  def all = Execution.all
end
# ActiveRecord IS the repository. This adds a layer that hides nothing.
```

**Config objects for simple cases:**
```ruby
# BAD: Over-engineered wrapper
class RetryConfig
  attr_reader :max, :backoff
  def initialize(max: 3, backoff: :linear) = ...
end
# Use keyword arguments or constants until complexity warrants it.
```

---

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

---

## Code Architecture Rules

### Where Depth Belongs

**Depth in lib/ (gem internals):** Middleware, infrastructure services, DSL modules, and the pipeline are where complexity lives. Each should hide meaningful logic behind a simple interface.

**Shallow in app/ (Rails engine):** Controllers, jobs, and views are intentionally thin. They delegate to deep model methods and gem internals.

**Concerns earn their existence:** Every concern must hide real complexity. Don't extract a concern for a single method or trivial logic — keep it on the model until a second consumer needs it or the logic is substantial.

```ruby
# GOOD: Deep concern — hides aggregate queries, trend math, grouping
module Execution::Analytics
  def self.cost_trends(period:, group_by:)
    # Complex SQL aggregation, date bucketing, trend calculation
  end
end

# BAD: Shallow concern — trivial delegation
module Execution::Status
  def success? = status == "success"
end
# Just put this on the model.
```

### Middleware Design

Each middleware must follow the pre/post pattern and hide meaningful logic:

```ruby
# GOOD: Deep middleware — hides retry logic, backoff calculation,
# fallback switching, circuit breaker state
class Pipeline::Middleware::Reliability < Base
  def call(context)
    with_retries(context) do
      with_fallbacks(context) do
        with_circuit_breaker(context) do
          @app.call(context)
        end
      end
    end
  end
end

# BAD: Shallow middleware — just logs and passes through
class Pipeline::Middleware::Logger < Base
  def call(context)
    log("starting")
    @app.call(context)
  end
end
# Inline this into an existing middleware.
```

### DSL Module Design

DSL modules provide the declarative interface for agent authors. Each module should feel like configuration, not programming:

```ruby
# GOOD: Simple declaration hides complex configuration normalization
class MyAgent < Base
  on_failure {
    retries 3, backoff: :exponential
    fallback "gpt-4o-mini"
    circuit_breaker threshold: 5, reset_after: 60
  }
end

# BAD: DSL that mirrors the implementation (no depth gained)
class MyAgent < Base
  set_retry_count 3
  set_backoff_type :exponential
end
# This is just attr_writers with extra steps.
```

### Gem-Specific Patterns

**Configuration — use the existing singleton pattern:**
```ruby
RubyLLM::Agents.configure do |config|
  config.default_model = "gpt-4o"
end
# Do NOT introduce alternative config mechanisms. One way to configure.
```

**Results — typed result objects per agent type:**
Each agent type returns a specific `Result` subclass. Don't return raw hashes or untyped data. The result class hides response normalization.

**Pipeline::Context — explicit data carrier:**
All data flows through named attributes on Context. Don't store data in instance variables on middleware or use thread-local storage. Context is the single source of truth.

**Agent Registry — two-source discovery:**
Combines filesystem scanning with execution history. Don't simplify to one source — both are needed (filesystem for current agents, history for deleted/renamed ones).

### Do's and Don'ts

| DO | DON'T |
|----|-------|
| Follow existing patterns (middleware, DSL, Context) | Introduce new architectural patterns without justification |
| Keep diffs minimal and focused | Mix refactors with behavior changes |
| Add to existing middleware when appropriate | Create new middleware for trivial logic |
| Use concerns that hide real complexity | Extract concerns for one method or one consumer |
| Design simple public APIs on classes | Expose implementation details to callers |
| Keep controllers thin (delegate to models) | Put business logic in controllers |
| Keep jobs as thin infrastructure glue | Put business logic in jobs |
| Return typed Result objects | Return raw hashes or unstructured data |
| Use Pipeline::Context for data flow | Use instance variables or thread-local state |
| Validate at system boundaries (user input, LLM responses) | Add redundant validation for internal data |

---

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| **Tables** | `ruby_llm_agents_` prefix | `ruby_llm_agents_executions` |
| **Models** | `RubyLLM::Agents::` namespace | `RubyLLM::Agents::Execution` |
| **Generators** | `RubyLlmAgents::` module | Note different casing from runtime |
| **Middleware** | `Pipeline::Middleware::` namespace | `Pipeline::Middleware::Budget` |
| **DSL Modules** | `Dsl::` namespace | `Dsl::Reliability` |
| **Results** | `Results::` namespace + `Result` suffix | `Results::EmbeddingResult` |
| **Agent types** | `app/agents/` with subdirs | `embedders/`, `audio/`, `images/`, `routers/` |

**Naming red flags:** `Manager`, `Handler`, `Processor`, `Helper`, `Utils`, `Wrapper`. If you reach for these names, reconsider whether the abstraction earns its keep.

---

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

### Test all new code

| Change Type | Required Tests |
|-------------|----------------|
| New middleware | Middleware spec exercising pre/post logic and edge cases |
| New DSL method | DSL spec with real test agent class asserting class-level state |
| New model/concern | Model spec with validations, associations, scopes |
| New controller action | Request spec |
| Bug fix | Regression test proving the fix |
| New agent type | Agent spec with mocked LLM boundary |
| New infrastructure | Unit spec for the service, integration spec for the pipeline |

### General setup

- Tests use SQLite in-memory database; schema loaded from `spec/dummy/db/schema.rb`
- `DatabaseCleaner` with transaction strategy (truncation for migration tests)
- `spec/support/ruby_llm_mock.rb` mocks RubyLLM API calls to avoid real LLM requests
- Migration specs (`spec/migrations/`, type `:migration`) use `SchemaBuilder` to rebuild schema at historical versions
- Integration tests require `RUN_INTEGRATION=1` environment variable
- FactoryBot factories in `spec/factories/`
- Shared examples in `spec/support/shared_examples/`
- Ruby 3.4+/4.0 compatibility: `require "ostruct"` explicitly when using OpenStruct in specs

---

## Security

- **Never log or store** API keys, tokens, or credentials in execution records or metadata
- **Filter sensitive parameters** — ensure `filter_parameters` covers all secret fields
- **Validate at boundaries** — validate user input in controllers, validate LLM responses in result classes
- **Strong parameters** — always use `permit` in controllers, never raw `params`
- **Dashboard auth** — respect `config.dashboard_auth` lambda for access control
- **Avoid command injection** — never interpolate user input into shell commands or raw SQL

---

## Dashboard UI (Views)

The engine includes a mountable dashboard using ERB + Tailwind CSS + Alpine.js.

### CSS Guidelines

- **Use existing Tailwind utilities** — don't introduce custom CSS unless absolutely necessary
- **Use Alpine.js for interactivity** — don't add other JS frameworks
- **Keep views thin** — complex logic belongs in helpers or model methods, not ERB
- **Use partials for reuse** — extract repeated markup into partials
- **Accessibility** — include focus states, ARIA labels on interactive elements

### View Do's and Don'ts

| DO | DON'T |
|----|-------|
| Use Tailwind utility classes | Write custom CSS for things Tailwind handles |
| Use Alpine.js for dynamic behavior | Add jQuery, React, or other JS frameworks |
| Extract repeated markup into partials | Copy-paste view code between templates |
| Put display logic in helpers | Put complex conditionals in ERB |
| Use `turbo_stream` for dynamic updates | Full page reloads for partial updates |

---

## Change Log

When making significant changes to architecture, database schema, or public API, document the decision in [`changelog/`](changelog/).

### What to Log

- Database schema changes (new tables, columns, migrations)
- Public API changes (new DSL methods, changed signatures, deprecations)
- Middleware pipeline changes (new middleware, reordering)
- Major refactors affecting multiple files
- New architectural patterns introduced

### ADR Format

Create a new file: `changelog/YYYY-MM-DD-short-title.md`

```markdown
# Title

## Context

What is the background? What problem are we solving?

## Decision

What change was made?

## Consequences

- What are the implications?
- What migrations or follow-up work is needed?
```

---

## Key Takeaways

1. **Design deep modules** — every abstraction must hide meaningful complexity behind a simple interface
2. **Reject shallow wrappers** — no pass-through methods, trivial concerns, or needless indirection
3. **Depth in lib/, thin in app/** — middleware, DSL, and infrastructure are deep; controllers, jobs, and views are thin
4. **One way to do things** — follow existing patterns (middleware pipeline, DSL, Context, Result objects)
5. **Keep diffs minimal** — only change what's necessary, don't mix refactors with features
6. **Test real code** — mock only the LLM API boundary, exercise everything else
7. **Explicit data flow** — use Pipeline::Context, not instance variables or thread-locals
8. **Typed results** — return Result subclasses, not raw hashes
9. **Concerns earn their keep** — extract only when complexity warrants it
10. **Security by default** — validate at boundaries, filter secrets, respect auth config
