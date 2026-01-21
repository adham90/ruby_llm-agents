# Unified Agent Architecture Plan

## Overview

Consolidate all agent types (conversation, embedding, image, moderation, audio) under a unified architecture using a **middleware pipeline pattern**. This eliminates code duplication, ensures feature parity across all agent types, and provides a clear, testable, and debuggable architecture.

---

## Design Principles

1. **Composition over Inheritance** - Behavior through middleware, not deep class hierarchies
2. **Explicit over Implicit** - Data flows through a Context object, no hidden instance variables
3. **Testable in Isolation** - Each middleware is a simple class with one job
4. **Debuggable** - Linear call stack, no module chain to trace
5. **DRY** - Middleware reused across all agent types
6. **Single Responsibility** - Each middleware does one thing well

---

## Goals

1. **Single middleware stack** - All agents use the same pipeline infrastructure
2. **Feature parity** - All agents get reliability, budgeting, caching, and instrumentation
3. **Type discrimination** - Agent-specific behavior in the core `execute` method only
4. **Backward compatible** - Existing agent DSL continues to work unchanged
5. **Extensible** - Adding new middleware or agent types is trivial
6. **Reduced duplication** - Eliminate ~300+ lines of repeated code across standalone agents
7. **Testable** - Each component testable in complete isolation
8. **Debuggable** - Linear stack traces, explicit data flow

---

## Current State Analysis

### Problem: Three Divergent Patterns

**Pattern A: Conversation Agents (Base)**
```ruby
class Base
  include Instrumentation
  include Caching
  include CostCalculation
  include ToolTracking
  include ResponseBuilding
  include ModerationExecution
  include Execution
  include ReliabilityExecution  # ✅ Has reliability

  extend DSL
  extend ModerationDSL
end

class MyChat < RubyLLM::Agents::Base
  model "gpt-4"
  retries 3                    # ✅ Works
  fallback_models "gpt-3.5"    # ✅ Works
end
```

**Pattern B: Standalone Agents (Embedder, Moderator)**
```ruby
class Embedder
  extend DSL
  include Execution
  # ❌ No reliability features
  # ❌ Duplicates tenant resolution
  # ❌ Duplicates budget checking
  # ❌ Duplicates execution recording
end

class MyEmbedder < RubyLLM::Agents::Embedder
  model "text-embedding-3-small"
  retries 3                    # ❌ Doesn't exist
  fallback_models "..."        # ❌ Doesn't exist
end
```

**Pattern C: Image Agents (Generator, Analyzer, etc.)**
```ruby
class ImageGenerator
  extend DSL
  include Execution
  # ❌ Same problems as Pattern B
end
```

### Why Concerns Are Problematic

| Issue | Impact |
|-------|--------|
| Implicit dependencies between concerns | Hard to test in isolation |
| Deep module chain in stack traces | Hard to debug |
| Hidden instance variable mutations | "Where did `@tenant_id` come from?" |
| Include order matters | Subtle bugs when order changes |
| Thread safety unclear | Shared state across concerns |

### Duplicated Code Across Standalone Agents

| Method | Embedder | ImageGenerator | Moderator | Speaker | Transcriber |
|--------|----------|----------------|-----------|---------|-------------|
| `resolve_tenant_context!` | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines |
| `check_budget!` | ✅ ~10 lines | ✅ ~10 lines | ✅ ~10 lines | ✅ ~10 lines | ✅ ~10 lines |
| `record_execution` | ✅ ~40 lines | ✅ ~40 lines | ✅ ~40 lines | ✅ ~40 lines | ✅ ~40 lines |
| `record_failed_execution` | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines | ✅ ~30 lines |
| `cache_store` | ✅ ~5 lines | ✅ ~5 lines | ✅ ~5 lines | ✅ ~5 lines | ✅ ~5 lines |

**Estimated duplication: 300-400 lines across 8+ agent types**

### Missing Features in Standalone Agents

| Feature | Base Agents | Standalone Agents |
|---------|-------------|-------------------|
| Automatic retries | ✅ | ❌ |
| Model fallbacks | ✅ | ❌ |
| Circuit breaker | ✅ | ❌ |
| Total timeout | ✅ | ❌ |
| Streaming support | ✅ | ❌ (where applicable) |

---

## Target State: Middleware Pipeline Architecture

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User's Agent                             │
│  class MyEmbedder < RubyLLM::Agents::Embedder                   │
│    model "text-embedding-3-small"                               │
│    retries 3                                                    │
│    fallback_models "text-embedding-ada-002"                     │
│  end                                                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Pipeline Builder                            │
│  Reads DSL configuration → Builds middleware stack               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Execution Pipeline                           │
│                                                                  │
│  Context ─┬─────────────────────────────────────────────┬─► Result
│           │                                             │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │    Tenant     │ ← Resolves tenant, sets context     │        │
│   └───────┬───────┘                                     │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │    Budget     │ ← Checks limits, records spend      │        │
│   └───────┬───────┘                                     │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │    Cache      │ ← Returns cached or continues       │        │
│   └───────┬───────┘                                     │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │ Instrumentation│ ← Times, logs, records execution   │        │
│   └───────┬───────┘                                     │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │  Reliability  │ ← Retries, fallbacks, circuit break │        │
│   └───────┬───────┘                                     │        │
│           ▼                                             │        │
│   ┌───────────────┐                                     │        │
│   │  Core Logic   │ ← Agent-specific LLM API call       │        │
│   └───────────────┘                                     │        │
└─────────────────────────────────────────────────────────────────┘
```

### Why Middleware Pattern?

| Aspect | Concerns (Old) | Middleware (New) |
|--------|---------------|------------------|
| **Testing** | Must stub module methods, hidden deps | Inject mock `app`, test in isolation |
| **Debugging** | 15+ frame module chain | Linear 5-frame call stack |
| **Data flow** | Hidden `@instance_vars` | Explicit `context.field` |
| **Adding features** | New concern + update all includes | New middleware class + add to pipeline |
| **Removing features** | Tricky (hidden dependencies) | Remove from pipeline config |
| **Thread safety** | Must audit all shared state | Each middleware stateless |
| **Understanding** | Read 6+ files, trace includes | Read pipeline order top-to-bottom |

**Battle-tested pattern:** Used by Rack, Faraday, Sidekiq, Rails Action Dispatch.

---

## Core Components

### 1. Context Object

The Context carries all data through the pipeline. No hidden instance variables.

**File:** `lib/ruby_llm/agents/pipeline/context.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      # Carries request/response data through the middleware pipeline.
      #
      # All data flows explicitly through this object - no hidden
      # instance variables or implicit state.
      #
      # @example
      #   context = Context.new(input: "Hello", model: "gpt-4")
      #   context.tenant_id = "tenant_123"
      #   context.output = response
      #
      class Context
        # Request data
        attr_accessor :input, :model, :options

        # Tenant data (set by Tenant middleware)
        attr_accessor :tenant_id, :tenant_object, :tenant_config

        # Execution tracking (set by Instrumentation middleware)
        attr_accessor :started_at, :completed_at, :attempt, :attempts_made

        # Result data (set by core execute method)
        attr_accessor :output, :error, :cached

        # Cost tracking
        attr_accessor :input_tokens, :output_tokens, :total_cost

        # Agent metadata
        attr_reader :agent_class, :agent_type

        def initialize(input:, agent_class:, **options)
          @input = input
          @agent_class = agent_class
          @agent_type = agent_class.agent_type
          @model = options.delete(:model) || agent_class.model
          @options = options
          @attempt = 0
          @attempts_made = 0
          @cached = false
          @metadata = {}
        end

        # Duration in milliseconds
        # @return [Integer, nil]
        def duration_ms
          return nil unless @started_at && @completed_at
          ((@completed_at - @started_at) * 1000).to_i
        end

        # Was the result served from cache?
        # @return [Boolean]
        def cached?
          @cached == true
        end

        # Did execution succeed?
        # @return [Boolean]
        def success?
          @error.nil? && @output.present?
        end

        # Did execution fail?
        # @return [Boolean]
        def failed?
          @error.present?
        end

        # Custom metadata storage
        # @param key [Symbol]
        # @return [Object]
        def [](key)
          @metadata[key]
        end

        # Custom metadata storage
        # @param key [Symbol]
        # @param value [Object]
        def []=(key, value)
          @metadata[key] = value
        end

        # Convert to hash for logging/recording
        # @return [Hash]
        def to_h
          {
            agent_class: @agent_class.name,
            agent_type: @agent_type,
            model: @model,
            tenant_id: @tenant_id,
            duration_ms: duration_ms,
            cached: cached?,
            success: success?,
            input_tokens: @input_tokens,
            output_tokens: @output_tokens,
            total_cost: @total_cost,
            attempts_made: @attempts_made,
            error_class: @error&.class&.name,
            error_message: @error&.message
          }.compact
        end
      end
    end
  end
end
```

### 2. Base Middleware Class

All middleware inherit from this simple base.

**File:** `lib/ruby_llm/agents/pipeline/middleware/base.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Base class for all middleware.
        #
        # Middleware wraps the next handler in the chain and can:
        # - Modify the context before passing it down
        # - Short-circuit the chain (e.g., return cached result)
        # - Handle errors from downstream
        # - Modify the context after the response
        #
        # @example Simple middleware
        #   class Logger < Base
        #     def call(context)
        #       puts "Before: #{context.input}"
        #       @app.call(context)
        #       puts "After: #{context.output}"
        #       context
        #     end
        #   end
        #
        class Base
          # @param app [#call] The next handler in the chain
          # @param agent_class [Class] The agent class (for reading DSL config)
          def initialize(app, agent_class)
            @app = app
            @agent_class = agent_class
          end

          # Process the context through this middleware
          #
          # @param context [Context] The execution context
          # @return [Context] The (possibly modified) context
          def call(context)
            raise NotImplementedError, "#{self.class} must implement #call"
          end

          private

          # Read configuration from agent class DSL
          # @param method [Symbol] DSL method name
          # @param default [Object] Default value if not set
          # @return [Object]
          def config(method, default = nil)
            @agent_class.respond_to?(method) ? @agent_class.send(method) : default
          end

          # Check if a DSL option is enabled
          # @param method [Symbol] DSL method name (e.g., :cache_enabled?)
          # @return [Boolean]
          def enabled?(method)
            config(method, false)
          end
        end
      end
    end
  end
end
```

### 3. Tenant Middleware

Resolves tenant context from options.

**File:** `lib/ruby_llm/agents/pipeline/middleware/tenant.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Resolves tenant context from options.
        #
        # Supports three formats:
        # - Object with llm_tenant_id method (recommended)
        # - Hash with :id key (legacy)
        # - nil (no tenant)
        #
        class Tenant < Base
          def call(context)
            resolve_tenant!(context)
            @app.call(context)
          end

          private

          def resolve_tenant!(context)
            tenant_value = context.options[:tenant]

            case tenant_value
            when nil
              # No tenant - that's fine
            when Hash
              context.tenant_id = tenant_value[:id]&.to_s
              context.tenant_config = tenant_value.except(:id)
            else
              if tenant_value.respond_to?(:llm_tenant_id)
                context.tenant_id = tenant_value.llm_tenant_id
                context.tenant_object = tenant_value
              else
                raise ArgumentError,
                      "tenant must respond to :llm_tenant_id, got #{tenant_value.class}"
              end
            end
          end
        end
      end
    end
  end
end
```

### 4. Budget Middleware

Checks budget before execution, records spend after.

**File:** `lib/ruby_llm/agents/pipeline/middleware/budget.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Checks budget limits before execution and records spend after.
        #
        # Skipped if budgets are disabled in configuration.
        #
        class Budget < Base
          def call(context)
            return @app.call(context) unless budgets_enabled?

            check_budget!(context)
            @app.call(context)
            record_spend!(context) if context.success?
            context
          end

          private

          def budgets_enabled?
            RubyLLM::Agents.configuration.budgets_enabled?
          end

          def check_budget!(context)
            BudgetTracker.check!(
              agent_type: context.agent_class.name,
              tenant_id: context.tenant_id,
              execution_type: context.agent_type.to_s
            )
          end

          def record_spend!(context)
            return unless context.total_cost&.positive?

            BudgetTracker.record_spend!(
              tenant_id: context.tenant_id,
              cost: context.total_cost,
              tokens: (context.input_tokens || 0) + (context.output_tokens || 0)
            )
          end
        end
      end
    end
  end
end
```

### 5. Cache Middleware

Returns cached results or passes through.

**File:** `lib/ruby_llm/agents/pipeline/middleware/cache.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Caches results to avoid redundant API calls.
        #
        # Skipped if caching is disabled for the agent.
        #
        class Cache < Base
          def call(context)
            return @app.call(context) unless cache_enabled?

            cache_key = generate_cache_key(context)

            # Try to read from cache
            if (cached = cache_store.read(cache_key))
              context.output = cached
              context.cached = true
              return context
            end

            # Execute and cache result
            @app.call(context)

            if context.success?
              cache_store.write(cache_key, context.output, expires_in: cache_ttl)
            end

            context
          end

          private

          def cache_enabled?
            enabled?(:cache_enabled?)
          end

          def cache_store
            RubyLLM::Agents.configuration.cache_store
          end

          def cache_ttl
            config(:cache_ttl)
          end

          def generate_cache_key(context)
            components = [
              "ruby_llm_agents",
              context.agent_type,
              context.agent_class.name,
              config(:version, "1.0"),
              context.model,
              Digest::SHA256.hexdigest(context.input.to_json)
            ]
            components.join("/")
          end
        end
      end
    end
  end
end
```

### 6. Instrumentation Middleware

Times execution, records success/failure.

**File:** `lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Times execution and records results for observability.
        #
        # Records:
        # - Execution duration
        # - Success/failure status
        # - Token usage and costs
        # - Error details on failure
        #
        class Instrumentation < Base
          def call(context)
            context.started_at = Time.current

            begin
              @app.call(context)
              context.completed_at = Time.current
              record_success(context)
            rescue => e
              context.completed_at = Time.current
              context.error = e
              record_failure(context)
              raise
            end

            context
          end

          private

          def record_success(context)
            return unless tracking_enabled?(context)

            persist_execution(
              context: context,
              status: "success"
            )
          end

          def record_failure(context)
            return unless tracking_enabled?(context)

            persist_execution(
              context: context,
              status: "error"
            )
          end

          def persist_execution(context:, status:)
            data = {
              agent_type: context.agent_class.name,
              execution_type: context.agent_type.to_s,
              model_id: context.model,
              status: status,
              duration_ms: context.duration_ms,
              started_at: context.started_at,
              completed_at: context.completed_at,
              tenant_id: context.tenant_id,
              cached: context.cached?,
              input_tokens: context.input_tokens || 0,
              output_tokens: context.output_tokens || 0,
              total_cost: context.total_cost || 0,
              attempts_made: context.attempts_made
            }

            if context.error
              data[:error_class] = context.error.class.name
              data[:error_message] = context.error.message.to_s.truncate(1000)
            end

            if RubyLLM::Agents.configuration.async_logging && defined?(ExecutionLoggerJob)
              ExecutionLoggerJob.perform_later(data)
            elsif defined?(RubyLLM::Agents::Execution)
              RubyLLM::Agents::Execution.create!(data)
            end
          rescue => e
            Rails.logger.error("[RubyLLM::Agents] Failed to record execution: #{e.message}") if defined?(Rails)
          end

          def tracking_enabled?(context)
            cfg = RubyLLM::Agents.configuration
            case context.agent_type
            when :embedding then cfg.track_embeddings
            when :moderation then cfg.track_moderations
            when :image then cfg.track_image_generations
            when :audio then cfg.track_audio
            else cfg.track_executions
            end
          end
        end
      end
    end
  end
end
```

### 7. Reliability Middleware

Handles retries, fallbacks, and circuit breakers.

**File:** `lib/ruby_llm/agents/pipeline/middleware/reliability.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Provides reliability features: retries, fallbacks, circuit breakers.
        #
        # Execution flow:
        # 1. Try primary model with retries
        # 2. On failure, try each fallback model with retries
        # 3. Circuit breakers prevent calls to failing models
        #
        class Reliability < Base
          def call(context)
            return @app.call(context) unless reliability_enabled?

            check_total_timeout!(context)
            models_to_try = [context.model] + fallback_models

            models_to_try.each_with_index do |model, index|
              last_model = (index == models_to_try.size - 1)

              begin
                return try_model(context, model)
              rescue => e
                raise if last_model
                raise unless fallback_eligible?(e)
                # Continue to next model
              end
            end
          end

          private

          def reliability_enabled?
            max_retries.positive? || fallback_models.any?
          end

          def try_model(context, model)
            context.model = model
            breaker = circuit_breaker_for(model, context.tenant_id)

            if breaker&.open?
              raise CircuitOpenError, "Circuit open for #{model}"
            end

            with_retries(context) do
              @app.call(context)
            end

            breaker&.record_success
            context
          rescue => e
            breaker&.record_failure
            raise
          end

          def with_retries(context)
            attempt = 0

            begin
              attempt += 1
              context.attempt = attempt
              context.attempts_made += 1
              check_total_timeout!(context)
              yield
            rescue => e
              if attempt <= max_retries && retryable?(e)
                sleep(backoff_delay(attempt))
                retry
              end
              raise
            end
          end

          def max_retries
            config(:retries, 0)
          end

          def fallback_models
            config(:fallback_models, [])
          end

          def retry_delay
            config(:retry_delay, 1.0)
          end

          def total_timeout
            config(:total_timeout)
          end

          def backoff_delay(attempt)
            retry_delay * (2 ** (attempt - 1)) + rand(0.0..0.5)
          end

          def retryable?(error)
            Reliability.retryable_error?(error)
          end

          def fallback_eligible?(error)
            Reliability.fallback_eligible_error?(error)
          end

          def circuit_breaker_for(model, tenant_id)
            return nil unless enabled?(:circuit_breaker_enabled?)
            Reliability::BreakerManager.breaker_for(model, tenant_id: tenant_id)
          end

          def check_total_timeout!(context)
            return unless total_timeout && context.started_at

            elapsed = Time.current - context.started_at
            if elapsed > total_timeout
              raise TotalTimeoutError, "Total timeout of #{total_timeout}s exceeded"
            end
          end
        end
      end
    end
  end
end
```

### 8. Pipeline Builder

Constructs the middleware stack from agent configuration.

**File:** `lib/ruby_llm/agents/pipeline/builder.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      # Builds the middleware pipeline from agent DSL configuration.
      #
      # @example Manual pipeline construction
      #   builder = Builder.new(MyEmbedder)
      #   builder.use(Middleware::Tenant)
      #   builder.use(Middleware::Cache)
      #   pipeline = builder.build(core_executor)
      #
      # @example Automatic from DSL
      #   pipeline = Builder.for(MyEmbedder).build(core_executor)
      #
      class Builder
        def initialize(agent_class)
          @agent_class = agent_class
          @stack = []
        end

        # Add middleware to the stack
        #
        # @param middleware_class [Class] Middleware class
        # @return [self]
        def use(middleware_class)
          @stack << middleware_class
          self
        end

        # Build the pipeline, wrapping the core executor
        #
        # @param core [#call] The core execution logic
        # @return [#call] The complete pipeline
        def build(core)
          @stack.reverse.reduce(core) do |app, middleware_class|
            middleware_class.new(app, @agent_class)
          end
        end

        # Build default pipeline for an agent class
        #
        # Reads DSL configuration to determine which middleware to include.
        #
        # @param agent_class [Class] The agent class
        # @return [Builder]
        def self.for(agent_class)
          new(agent_class).tap do |builder|
            # Always included
            builder.use(Middleware::Tenant)

            # Conditional middleware
            builder.use(Middleware::Budget) if budgets_enabled?
            builder.use(Middleware::Cache) if cache_enabled?(agent_class)
            builder.use(Middleware::Instrumentation)
            builder.use(Middleware::Reliability) if reliability_enabled?(agent_class)
          end
        end

        private_class_method def self.budgets_enabled?
          RubyLLM::Agents.configuration.budgets_enabled?
        end

        private_class_method def self.cache_enabled?(agent_class)
          agent_class.respond_to?(:cache_enabled?) && agent_class.cache_enabled?
        end

        private_class_method def self.reliability_enabled?(agent_class)
          retries = agent_class.respond_to?(:retries) ? agent_class.retries : 0
          fallbacks = agent_class.respond_to?(:fallback_models) ? agent_class.fallback_models : []
          retries.positive? || fallbacks.any?
        end
      end
    end
  end
end
```

### 9. Core Executor Wrapper

Wraps the agent's execute method to work with the pipeline.

**File:** `lib/ruby_llm/agents/pipeline/executor.rb`

```ruby
module RubyLLM
  module Agents
    module Pipeline
      # Wraps an agent's execute method to work with the pipeline.
      #
      # This is the "core" that middleware wraps around.
      #
      class Executor
        def initialize(agent)
          @agent = agent
        end

        def call(context)
          @agent.execute(context)
          context
        end
      end
    end
  end
end
```

---

## Updated Agent Types

### Base Agent Class

All agents inherit from this. It sets up the pipeline infrastructure.

**File:** `lib/ruby_llm/agents/base_agent.rb`

```ruby
module RubyLLM
  module Agents
    # Universal base class for all LLM-powered agents.
    #
    # Uses middleware pipeline for cross-cutting concerns:
    # - Tenant resolution
    # - Budget checking
    # - Caching
    # - Instrumentation
    # - Reliability (retries, fallbacks, circuit breakers)
    #
    # Subclasses only need to:
    # 1. Set agent_type
    # 2. Implement execute(context)
    # 3. Add agent-specific DSL if needed
    #
    # @abstract Subclass and implement #execute
    #
    class BaseAgent
      # Shared DSL for all agents
      extend DSL::Base
      extend DSL::Reliability
      extend DSL::Caching

      class << self
        # Agent type discriminator
        # @return [Symbol] :conversation, :embedding, :image, :moderation, :audio
        attr_accessor :agent_type

        # Factory method
        def call(*args, **kwargs, &block)
          new(**kwargs).call(*args, &block)
        end

        # Ensure subclasses inherit agent_type
        def inherited(subclass)
          super
          subclass.agent_type = agent_type
        end
      end

      attr_reader :options

      def initialize(**options)
        @options = options
        @pipeline = build_pipeline
      end

      # Execute the agent
      #
      # @return [Object] The result (agent-specific)
      def call(*args, &block)
        context = build_context(*args)
        @pipeline.call(context)
        context.output
      end

      # Agent-specific execution logic
      #
      # @abstract Subclasses must implement this
      # @param context [Pipeline::Context] The execution context
      # @return [void] Should set context.output
      def execute(context)
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      private

      def build_pipeline
        Pipeline::Builder
          .for(self.class)
          .build(Pipeline::Executor.new(self))
      end

      def build_context(*args)
        # Subclasses override to customize context creation
        Pipeline::Context.new(
          input: args.first,
          agent_class: self.class,
          **@options
        )
      end
    end
  end
end
```

### Embedder

Clean, focused implementation.

**File:** `lib/ruby_llm/agents/embedder.rb`

```ruby
module RubyLLM
  module Agents
    # Embedding generator agent.
    #
    # Generates vector embeddings for text using LLM embedding models.
    # Now supports all reliability features via middleware pipeline.
    #
    # @example Basic usage
    #   class MyEmbedder < RubyLLM::Agents::Embedder
    #     model "text-embedding-3-small"
    #     dimensions 512
    #   end
    #
    #   result = MyEmbedder.call(text: "Hello world")
    #   result.embedding  # => [0.123, -0.456, ...]
    #
    # @example With reliability
    #   class ReliableEmbedder < RubyLLM::Agents::Embedder
    #     model "text-embedding-3-large"
    #     retries 3
    #     fallback_models "text-embedding-3-small", "text-embedding-ada-002"
    #     circuit_breaker threshold: 5, timeout: 30
    #   end
    #
    class Embedder < BaseAgent
      self.agent_type = :embedding

      extend DSL::Embedding

      class << self
        def call(text: nil, texts: nil, **options)
          new(**options).call(text: text, texts: texts)
        end
      end

      def call(text: nil, texts: nil, &block)
        input = texts || [text].compact
        raise ArgumentError, "Must provide text or texts" if input.empty?

        context = build_context(input)
        @pipeline.call(context)
        context.output
      end

      # Core embedding logic - this is all Embedder needs to know
      def execute(context)
        client = RubyLLM.client

        response = client.embed(
          context.input,
          model: context.model,
          dimensions: self.class.dimensions
        )

        context.output = build_result(response, context)
        context.input_tokens = response.input_tokens
        context.total_cost = calculate_cost(response)
      end

      private

      def build_context(input)
        Pipeline::Context.new(
          input: input,
          agent_class: self.class,
          **@options
        )
      end

      def build_result(response, context)
        EmbeddingResult.new(
          embeddings: response.embeddings,
          model: context.model,
          input_tokens: response.input_tokens,
          dimensions: self.class.dimensions
        )
      end

      def calculate_cost(response)
        CostCalculator.calculate(
          model: response.model,
          input_tokens: response.input_tokens
        )
      end
    end
  end
end
```

### ImageGenerator

**File:** `lib/ruby_llm/agents/image_generator.rb`

```ruby
module RubyLLM
  module Agents
    # Image generation agent.
    #
    # @example With reliability
    #   class MyGenerator < RubyLLM::Agents::ImageGenerator
    #     model "dall-e-3"
    #     size "1024x1024"
    #     quality "hd"
    #     retries 2
    #     fallback_models "dall-e-2"
    #   end
    #
    class ImageGenerator < BaseAgent
      self.agent_type = :image

      extend DSL::ImageGeneration

      class << self
        def call(prompt:, **options)
          new(**options).call(prompt: prompt)
        end
      end

      def call(prompt:, &block)
        context = build_context(prompt)
        @pipeline.call(context)
        context.output
      end

      def execute(context)
        client = RubyLLM.client

        response = client.generate_image(
          context.input,
          model: context.model,
          size: self.class.size,
          quality: self.class.quality,
          style: self.class.style
        )

        context.output = ImageResult.new(
          url: response.url,
          model: context.model,
          revised_prompt: response.revised_prompt
        )
        context.total_cost = calculate_cost(context.model)
      end

      private

      def build_context(prompt)
        Pipeline::Context.new(
          input: prompt,
          agent_class: self.class,
          **@options
        )
      end

      def calculate_cost(model)
        CostCalculator.calculate_image(
          model: model,
          size: self.class.size,
          quality: self.class.quality
        )
      end
    end
  end
end
```

### Conversation Agent (Base)

The existing `Base` class refactored to use the pipeline.

**File:** `lib/ruby_llm/agents/base.rb`

```ruby
module RubyLLM
  module Agents
    # Base class for conversation-based LLM agents.
    #
    # Provides a DSL for configuring agents that have multi-turn
    # conversations with language models.
    #
    class Base < BaseAgent
      self.agent_type = :conversation

      extend DSL::Conversation
      extend DSL::Moderation
      extend DSL::Tools

      attr_reader :model, :temperature, :accumulated_tool_calls

      def initialize(model: nil, temperature: nil, **options)
        @model = model || self.class.model
        @temperature = temperature || self.class.temperature
        @accumulated_tool_calls = []
        super(**options)
      end

      def call(&block)
        context = build_context(user_prompt)
        @pipeline.call(context)
        process_response(context.output)
      end

      def execute(context)
        messages = build_messages(context)
        client = build_client

        response = client.chat(
          messages: messages,
          model: context.model,
          temperature: @temperature,
          tools: self.class.tools,
          schema: schema,
          &stream_handler
        )

        handle_tool_calls(response) if response.tool_calls?
        context.output = response
        context.input_tokens = response.input_tokens
        context.output_tokens = response.output_tokens
        context.total_cost = response.total_cost
      end

      # Template methods for subclasses
      def user_prompt
        raise NotImplementedError, "#{self.class} must implement #user_prompt"
      end

      def system_prompt
        nil
      end

      def schema
        nil
      end

      def messages
        []
      end

      def process_response(response)
        content = response.content
        return content unless content.is_a?(Hash)
        content.transform_keys(&:to_sym)
      end

      private

      def build_context(prompt)
        Pipeline::Context.new(
          input: prompt,
          agent_class: self.class,
          model: @model,
          **@options
        )
      end

      def build_messages(context)
        msgs = []
        msgs << { role: :system, content: system_prompt } if system_prompt
        msgs.concat(messages)
        msgs << { role: :user, content: context.input }
        msgs
      end

      def build_client
        RubyLLM.client
      end

      def stream_handler
        return nil unless self.class.streaming_enabled?
        ->(chunk) { handle_stream_chunk(chunk) }
      end

      def handle_stream_chunk(chunk)
        # Override in subclass if needed
      end

      def handle_tool_calls(response)
        # Tool execution logic
      end
    end
  end
end
```

---

## DSL Modules

Keep DSL simple and focused on configuration only.

**File:** `lib/ruby_llm/agents/dsl/base.rb`

```ruby
module RubyLLM
  module Agents
    module DSL
      # Base DSL available to all agents
      module Base
        def model(value = nil)
          @model = value if value
          @model
        end

        def version(value = nil)
          @version = value if value
          @version || "1.0"
        end
      end
    end
  end
end
```

**File:** `lib/ruby_llm/agents/dsl/reliability.rb`

```ruby
module RubyLLM
  module Agents
    module DSL
      # Reliability DSL for retries, fallbacks, circuit breakers
      module Reliability
        def retries(value = nil)
          @retries = value if value
          @retries || 0
        end

        def retry_delay(value = nil)
          @retry_delay = value if value
          @retry_delay || 1.0
        end

        def fallback_models(*models)
          @fallback_models = models.flatten if models.any?
          @fallback_models || []
        end

        def total_timeout(value = nil)
          @total_timeout = value if value
          @total_timeout
        end

        def circuit_breaker(threshold: 5, timeout: 30, half_open_limit: 3)
          @circuit_breaker_config = {
            threshold: threshold,
            timeout: timeout,
            half_open_limit: half_open_limit
          }
          @circuit_breaker_enabled = true
        end

        def circuit_breaker_enabled?
          @circuit_breaker_enabled || false
        end

        def circuit_breaker_config
          @circuit_breaker_config || {}
        end
      end
    end
  end
end
```

**File:** `lib/ruby_llm/agents/dsl/caching.rb`

```ruby
module RubyLLM
  module Agents
    module DSL
      # Caching DSL
      module Caching
        def cache_for(duration)
          @cache_ttl = duration
          @cache_enabled = true
        end

        def cache_enabled?
          @cache_enabled || false
        end

        def cache_ttl
          @cache_ttl
        end
      end
    end
  end
end
```

---

## File Structure (Target State)

```
lib/ruby_llm/agents/
├── agents.rb                           # Main entry point

├── pipeline/                           # NEW: Middleware pipeline
│   ├── context.rb                      # Request/response context
│   ├── builder.rb                      # Pipeline construction
│   ├── executor.rb                     # Core executor wrapper
│   └── middleware/
│       ├── base.rb                     # Middleware base class
│       ├── tenant.rb                   # Tenant resolution
│       ├── budget.rb                   # Budget checking
│       ├── cache.rb                    # Response caching
│       ├── instrumentation.rb          # Execution tracking
│       └── reliability.rb              # Retries, fallbacks, circuit breakers

├── dsl/                                # Configuration DSL modules
│   ├── base.rb                         # Common DSL (model, version)
│   ├── reliability.rb                  # Retry/fallback DSL
│   ├── caching.rb                      # Cache DSL
│   ├── conversation.rb                 # Conversation-specific DSL
│   ├── embedding.rb                    # Embedding-specific DSL
│   ├── image_generation.rb             # Image-specific DSL
│   ├── moderation.rb                   # Moderation DSL
│   └── tools.rb                        # Tool registration DSL

├── base_agent.rb                       # Universal base class
├── base.rb                             # Conversation agent (inherits BaseAgent)
├── embedder.rb                         # Embedding agent (inherits BaseAgent)
├── image_generator.rb                  # Image gen agent (inherits BaseAgent)
├── image_analyzer.rb                   # Image analysis (inherits BaseAgent)
├── moderator.rb                        # Moderation agent (inherits BaseAgent)
├── speaker.rb                          # TTS agent (inherits BaseAgent)
├── transcriber.rb                      # STT agent (inherits BaseAgent)

├── results/                            # Result objects (unchanged)
│   ├── embedding_result.rb
│   ├── image_result.rb
│   └── ...

├── infrastructure/                     # Supporting infrastructure
│   ├── reliability/
│   │   ├── breaker_manager.rb
│   │   ├── circuit_breaker.rb
│   │   └── errors.rb
│   ├── budget/
│   │   └── budget_tracker.rb
│   └── cost_calculator.rb

└── errors.rb                           # Error classes
```

---

## Implementation Phases

### Phase 1: Create Pipeline Infrastructure

**Goal:** Build the middleware pipeline system without touching existing agents.

#### Tasks

1. **Create pipeline directory structure**

2. **Implement Context class**
   - All attributes explicit
   - Helper methods (duration_ms, success?, etc.)
   - Comprehensive tests

3. **Implement Middleware::Base**
   - Simple interface: initialize(app, agent_class) + call(context)
   - Config helper method

4. **Implement Pipeline::Builder**
   - `use(middleware)` method
   - `build(core)` method
   - `self.for(agent_class)` factory

5. **Implement Pipeline::Executor**
   - Wraps agent.execute(context)

#### Acceptance Criteria

- [ ] Context holds all execution state
- [ ] Builder can construct middleware chain
- [ ] Pipeline can execute with mock middleware
- [ ] 100% test coverage on pipeline infrastructure

---

### Phase 2: Implement Core Middleware

**Goal:** Create all middleware classes, tested in isolation.

#### Tasks

1. **Implement Middleware::Tenant**
   - Extract logic from existing agents
   - Test all tenant formats

2. **Implement Middleware::Budget**
   - Extract from existing agents
   - Test budget check/record flow

3. **Implement Middleware::Cache**
   - Extract from existing agents
   - Test cache hit/miss scenarios

4. **Implement Middleware::Instrumentation**
   - Extract from existing agents
   - Test success/failure recording

5. **Implement Middleware::Reliability**
   - Extract from Base::ReliabilityExecution
   - Test retries, fallbacks, circuit breakers independently

#### Testing Strategy

Each middleware tested with mock `app`:

```ruby
RSpec.describe Middleware::Reliability do
  let(:successful_app) { ->(ctx) { ctx.output = "success"; ctx } }
  let(:failing_app) { ->(ctx) { raise RetryableError } }
  let(:agent_class) { double(retries: 2, fallback_models: ["backup"]) }

  it "retries on failure" do
    call_count = 0
    flaky_app = ->(ctx) {
      call_count += 1
      raise RetryableError if call_count < 2
      ctx.output = "success"
      ctx
    }

    middleware = described_class.new(flaky_app, agent_class)
    context = Context.new(input: "test", agent_class: agent_class)

    result = middleware.call(context)

    expect(result.output).to eq("success")
    expect(call_count).to eq(2)
  end
end
```

#### Acceptance Criteria

- [ ] Each middleware works in isolation
- [ ] Each middleware has >95% test coverage
- [ ] No dependencies between middleware
- [ ] Middleware order doesn't matter (except for data dependencies)

---

### Phase 3: Create BaseAgent and DSL

**Goal:** Build the new base class and DSL modules.

#### Tasks

1. **Create DSL modules**
   - DSL::Base (model, version)
   - DSL::Reliability (retries, fallbacks, circuit_breaker)
   - DSL::Caching (cache_for)
   - Migrate existing DSL methods

2. **Create BaseAgent class**
   - Include DSL modules
   - Pipeline integration
   - Abstract execute method

3. **Add agent_type inheritance**

#### Acceptance Criteria

- [ ] DSL methods work on BaseAgent
- [ ] BaseAgent builds correct pipeline
- [ ] agent_type propagates to subclasses

---

### Phase 4: Migrate Agents One at a Time

**Goal:** Update each agent to inherit from BaseAgent.

Order: Start with simplest, end with most complex.

#### 4.1 Migrate Embedder

```ruby
# Before (200+ lines with duplicated code)
class Embedder
  extend DSL
  include Execution
  # ... tenant resolution, budget, cache, instrumentation duplicated
end

# After (~50 lines)
class Embedder < BaseAgent
  self.agent_type = :embedding
  extend DSL::Embedding

  def execute(context)
    # ONLY embedding logic
  end
end
```

#### 4.2 Migrate ImageGenerator

#### 4.3 Migrate Speaker

#### 4.4 Migrate Transcriber

#### 4.5 Migrate Moderator

#### 4.6 Migrate Base (Conversation)

This is the most complex - do last.

#### Migration Checklist per Agent

- [ ] Change inheritance to `< BaseAgent`
- [ ] Set `self.agent_type`
- [ ] Move DSL to appropriate module
- [ ] Implement `execute(context)` with ONLY core logic
- [ ] Remove duplicated tenant/budget/cache/instrumentation code
- [ ] Update tests
- [ ] Verify all existing tests pass

#### Acceptance Criteria

- [ ] All agents inherit from BaseAgent
- [ ] All agents use pipeline
- [ ] Zero duplicated infrastructure code
- [ ] All existing tests pass unchanged

---

### Phase 5: Cleanup and Documentation

**Goal:** Remove old code, update docs, ensure smooth migration.

#### Tasks

1. **Remove dead code**
   - Old Execution modules
   - Old concern includes
   - Duplicated methods

2. **Update documentation**
   - Architecture diagram
   - Middleware documentation
   - Migration guide

3. **Add deprecation warnings** (if any old patterns still work)

4. **Update CHANGELOG**

5. **Performance benchmarks**
   - Before/after comparison
   - Ensure no regression

#### Acceptance Criteria

- [ ] No dead code
- [ ] Complete documentation
- [ ] CHANGELOG updated
- [ ] No performance regression

---

## Testing Strategy

### Unit Tests: Middleware in Isolation

```ruby
# spec/ruby_llm/agents/pipeline/middleware/cache_spec.rb
RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Cache do
  let(:app) { ->(ctx) { ctx.output = "computed"; ctx } }
  let(:agent_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Caching
      cache_for 1.hour

      def self.name
        "TestAgent"
      end
    end
  end
  let(:middleware) { described_class.new(app, agent_class) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
  end

  describe "#call" do
    it "caches successful responses" do
      context = build_context(input: "hello")

      middleware.call(context)
      expect(context.output).to eq("computed")
      expect(context.cached?).to be false

      # Second call should hit cache
      context2 = build_context(input: "hello")
      middleware.call(context2)
      expect(context2.output).to eq("computed")
      expect(context2.cached?).to be true
    end

    it "does not cache failed responses" do
      failing_app = ->(ctx) { raise "boom" }
      middleware = described_class.new(failing_app, agent_class)

      expect {
        middleware.call(build_context(input: "hello"))
      }.to raise_error("boom")

      # Cache should be empty
      expect(cache_store.read(anything)).to be_nil
    end
  end

  def build_context(input:)
    RubyLLM::Agents::Pipeline::Context.new(
      input: input,
      agent_class: agent_class
    )
  end
end
```

### Integration Tests: Full Pipeline

```ruby
# spec/ruby_llm/agents/integration/pipeline_spec.rb
RSpec.describe "Full Pipeline Integration" do
  let(:embedder_class) do
    Class.new(RubyLLM::Agents::Embedder) do
      model "text-embedding-3-small"
      retries 2
      cache_for 1.hour
    end
  end

  it "executes through full middleware stack" do
    stub_embedding_api

    result = embedder_class.call(text: "hello world", tenant: { id: "t1" })

    expect(result.embedding).to be_present
    # Verify middleware executed
    expect(RubyLLM::Agents::Execution.count).to eq(1)
    expect(RubyLLM::Agents::Execution.last.tenant_id).to eq("t1")
  end

  it "retries on transient failure" do
    stub_embedding_api_with_failures(2)

    result = embedder_class.call(text: "hello world")

    expect(result.embedding).to be_present
    expect(RubyLLM::Agents::Execution.last.attempts_made).to eq(3)
  end
end
```

### Backward Compatibility Tests

```ruby
# spec/ruby_llm/agents/backward_compatibility_spec.rb
RSpec.describe "Backward Compatibility" do
  it "existing Embedder subclasses work unchanged" do
    # This class definition should work exactly as before
    klass = Class.new(RubyLLM::Agents::Embedder) do
      model "text-embedding-3-small"
      dimensions 512
    end

    stub_embedding_api
    result = klass.call(text: "hello")
    expect(result.embedding).to be_present
  end

  it "existing Base subclasses work unchanged" do
    klass = Class.new(RubyLLM::Agents::Base) do
      model "gpt-4"

      def user_prompt
        "Hello"
      end
    end

    stub_chat_api
    result = klass.call
    expect(result).to be_present
  end

  it "new reliability DSL works on all agents" do
    klass = Class.new(RubyLLM::Agents::Embedder) do
      model "text-embedding-3-large"
      retries 3
      fallback_models "text-embedding-3-small"
      circuit_breaker threshold: 5
    end

    expect(klass.retries).to eq(3)
    expect(klass.fallback_models).to eq(["text-embedding-3-small"])
    expect(klass.circuit_breaker_enabled?).to be true
  end
end
```

---

## Debugging Comparison

### Before (Concerns)

```
NoMethodError: undefined method 'embeddings' for nil:NilClass
  from lib/ruby_llm/agents/embedder/execution.rb:45:in `execute'
  from lib/ruby_llm/agents/concerns/reliable.rb:67:in `with_retries'
  from lib/ruby_llm/agents/concerns/reliable.rb:34:in `block in with_reliability'
  from lib/ruby_llm/agents/concerns/reliable.rb:28:in `each'
  from lib/ruby_llm/agents/concerns/reliable.rb:28:in `with_reliability'
  from lib/ruby_llm/agents/concerns/instrumentable.rb:42:in `record_execution'
  from lib/ruby_llm/agents/concerns/cache_aware.rb:23:in `with_cache'
  from lib/ruby_llm/agents/concerns/budget_aware.rb:15:in `check_budget!'
  from lib/ruby_llm/agents/concerns/tenant_aware.rb:12:in `resolve_tenant_context!'
  from lib/ruby_llm/agents/embedder/execution.rb:12:in `call'
  ... 20 more lines of module inclusion
```

### After (Middleware)

```
NoMethodError: undefined method 'embeddings' for nil:NilClass
  from lib/ruby_llm/agents/embedder.rb:45:in `execute'
  from lib/ruby_llm/agents/pipeline/executor.rb:12:in `call'
  from lib/ruby_llm/agents/pipeline/middleware/reliability.rb:34:in `call'
  from lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb:18:in `call'
  from lib/ruby_llm/agents/pipeline/middleware/cache.rb:15:in `call'
  from lib/ruby_llm/agents/pipeline/middleware/budget.rb:12:in `call'
  from lib/ruby_llm/agents/pipeline/middleware/tenant.rb:10:in `call'
  from lib/ruby_llm/agents/base_agent.rb:52:in `call'
```

**5 fewer frames, linear flow, each frame is a single class.**

---

## Migration Guide

### For Users with Custom Agents

#### Before (Works Unchanged!)

```ruby
class MyEmbedder < RubyLLM::Agents::Embedder
  model "text-embedding-3-small"
  dimensions 512
end
```

#### After (Same Code, New Features Available!)

```ruby
class MyEmbedder < RubyLLM::Agents::Embedder
  model "text-embedding-3-small"
  dimensions 512

  # NEW: These now work!
  retries 3
  fallback_models "text-embedding-ada-002"
  circuit_breaker threshold: 5, timeout: 30
  cache_for 1.hour
end
```

### Custom Middleware

Users can add custom middleware:

```ruby
# Custom logging middleware
class MyLoggingMiddleware < RubyLLM::Agents::Pipeline::Middleware::Base
  def call(context)
    Rails.logger.info("Starting: #{context.agent_class.name}")
    result = @app.call(context)
    Rails.logger.info("Completed in #{context.duration_ms}ms")
    result
  end
end

# Register globally
RubyLLM::Agents.configure do |config|
  config.middleware.insert_before(
    RubyLLM::Agents::Pipeline::Middleware::Instrumentation,
    MyLoggingMiddleware
  )
end
```

---

## Error Hierarchy

```ruby
module RubyLLM
  module Agents
    class Error < StandardError; end

    # Pipeline errors
    class PipelineError < Error; end

    # Reliability errors
    class ReliabilityError < Error; end
    class RetryableError < ReliabilityError; end
    class CircuitOpenError < ReliabilityError; end
    class TotalTimeoutError < ReliabilityError; end
    class AllModelsFailedError < ReliabilityError; end

    # Budget errors
    class BudgetError < Error; end
    class BudgetExceededError < BudgetError; end

    # Configuration errors
    class ConfigurationError < Error; end
  end
end
```

---

## Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Reliability opt-in or opt-out? | **Opt-in** | Only active if DSL methods used; safer default |
| Circuit breaker key format? | `{agent_type}:{model}:{tenant_id}` | Different agent types have different failure modes |
| Should BaseAgent be abstract? | **No** | Allow direct use for advanced cases |
| Middleware order configurable? | **Yes** | Via configuration, with sensible defaults |
| Context mutable or immutable? | **Mutable** | Simpler, follows Rack convention |

---

## Success Metrics

1. **Code Reduction:** ~300 lines of duplicated code eliminated
2. **Feature Parity:** All 8+ agent types support retries, fallbacks, circuit breakers
3. **Test Coverage:** >95% coverage on pipeline and middleware
4. **Zero Breaking Changes:** All existing tests pass without modification
5. **Debugging Improvement:** Stack traces reduced by 50%+
6. **Documentation:** Complete API reference and migration guide

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing subclasses | High | Extensive backward compatibility tests |
| Performance overhead from middleware chain | Low | Benchmark; middleware is lightweight |
| Learning curve for contributors | Medium | Clear documentation; familiar pattern (Rack) |
| Middleware order bugs | Medium | Explicit dependencies; integration tests |

---

## Next Steps

1. [ ] Review and approve plan
2. [ ] Create feature branch: `feature/middleware-pipeline-architecture`
3. [ ] Phase 1: Create Pipeline Infrastructure
4. [ ] Phase 2: Implement Core Middleware
5. [ ] Phase 3: Create BaseAgent and DSL
6. [ ] Phase 4: Migrate Agents (one at a time, starting with Embedder)
7. [ ] Phase 5: Cleanup and Documentation
8. [ ] Update CHANGELOG
9. [ ] Release as minor version (backward compatible)
