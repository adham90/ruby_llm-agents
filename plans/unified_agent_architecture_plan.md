# Unified Agent Architecture Plan

## Overview

Consolidate all agent types (conversation, embedding, image, moderation, audio) under a single `Agent` base class with type discrimination. This eliminates code duplication, ensures feature parity across all agent types, and provides a clear, extensible architecture.

---

## Goals

1. **Single inheritance hierarchy** - One `Agent` base class for all agent types
2. **Feature parity** - All agents get reliability, budgeting, caching, and instrumentation
3. **Type discrimination** - Agent-specific behavior handled via `agent_type` attribute
4. **Backward compatible** - Existing agent subclasses continue to work with deprecation warnings
5. **Extensible** - Adding new agent types is trivial
6. **Reduced duplication** - Eliminate ~300+ lines of repeated code across standalone agents

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
| Moderation hooks | ✅ | ❌ |
| Streaming support | ✅ | ❌ (where applicable) |

---

## Target State

### New Architecture Diagram

```
                    ┌─────────────────────────────────────┐
                    │           RubyLLM::Agents           │
                    └─────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
        ┌───────────────────┐               ┌───────────────────┐
        │   Agent (Base)    │               │   Configuration   │
        │                   │               │                   │
        │ - TenantAware     │               │ - Global settings │
        │ - BudgetAware     │               │ - Defaults        │
        │ - CacheAware      │               └───────────────────┘
        │ - Instrumentation │
        │ - Reliability     │
        └───────────────────┘
                    │
    ┌───────────────┼───────────────┬───────────────┬───────────────┐
    │               │               │               │               │
    ▼               ▼               ▼               ▼               ▼
┌───────┐     ┌──────────┐   ┌───────────┐   ┌──────────┐   ┌───────────┐
│ Base  │     │ Embedder │   │ Image*    │   │ Speaker  │   │Transcriber│
│       │     │          │   │           │   │          │   │           │
│:convo │     │:embedding│   │:image     │   │:audio    │   │:audio     │
└───────┘     └──────────┘   └───────────┘   └──────────┘   └───────────┘
    │               │               │               │               │
    ▼               ▼               ▼               ▼               ▼
 User            User            User            User            User
Agents          Agents          Agents          Agents          Agents
```

### Core Agent Class

**File:** `lib/ruby_llm/agents/core/agent.rb`

```ruby
module RubyLLM
  module Agents
    # Universal base class for all LLM-powered agents
    #
    # Provides shared infrastructure for tenant management, budget tracking,
    # caching, reliability (retries, fallbacks, circuit breakers), and
    # execution instrumentation.
    #
    # @abstract Subclass and set agent_type to create specific agent types
    # @api public
    class Agent
      # Shared infrastructure (all agents get these)
      include Concerns::TenantAware
      include Concerns::BudgetAware
      include Concerns::CacheAware
      include Concerns::Instrumentable
      include Concerns::Reliable

      # Shared DSL (all agents get these)
      extend Concerns::BaseDSL
      extend Concerns::ReliabilityDSL

      class << self
        # Agent type discriminator
        # @return [Symbol] One of :conversation, :embedding, :image, :moderation, :audio
        attr_accessor :agent_type

        # Factory method - all agents use this pattern
        def call(*args, **kwargs, &block)
          new(*args, **kwargs).call(&block)
        end

        # Ensure subclasses inherit agent_type
        def inherited(subclass)
          super
          subclass.agent_type = agent_type
        end
      end

      attr_reader :options, :tenant_id, :tenant_object

      def initialize(**options)
        @options = options
        @execution_started_at = nil
        @execution_completed_at = nil
        resolve_tenant_context!
      end

      # @abstract Subclasses must implement this
      def call(&block)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Hook for subclasses to define execution type for tracking
      def execution_type
        self.class.agent_type&.to_s || "unknown"
      end
    end
  end
end
```

### Shared Concerns

#### TenantAware Concern

**File:** `lib/ruby_llm/agents/concerns/tenant_aware.rb`

```ruby
module RubyLLM
  module Agents
    module Concerns
      # Provides tenant resolution for multi-tenancy support
      #
      # Extracts tenant context from options and resolves tenant ID,
      # object, and configuration for use in budget tracking and
      # execution recording.
      module TenantAware
        extend ActiveSupport::Concern

        included do
          attr_reader :tenant_id, :tenant_object, :tenant_config
        end

        private

        # Resolves tenant context from options
        #
        # Supports three formats:
        # - Object with llm_tenant_id method (recommended)
        # - Hash with :id key (legacy)
        # - nil (no tenant)
        #
        # @return [void]
        # @raise [ArgumentError] If tenant format is invalid
        def resolve_tenant_context!
          return if @tenant_context_resolved

          tenant_value = @options[:tenant]

          if tenant_value.nil?
            @tenant_id = nil
            @tenant_object = nil
            @tenant_config = nil
          elsif tenant_value.is_a?(Hash)
            @tenant_id = tenant_value[:id]&.to_s
            @tenant_object = nil
            @tenant_config = tenant_value.except(:id)
          elsif tenant_value.respond_to?(:llm_tenant_id)
            @tenant_id = tenant_value.llm_tenant_id
            @tenant_object = tenant_value
            @tenant_config = nil
          else
            raise ArgumentError,
                  "tenant must respond to :llm_tenant_id (use llm_tenant DSL), got #{tenant_value.class}"
          end

          @tenant_context_resolved = true
        end

        # Returns whether tenant context has been resolved
        def tenant_context_resolved?
          @tenant_context_resolved == true
        end
      end
    end
  end
end
```

#### BudgetAware Concern

**File:** `lib/ruby_llm/agents/concerns/budget_aware.rb`

```ruby
module RubyLLM
  module Agents
    module Concerns
      # Provides budget checking and spend recording
      #
      # Integrates with BudgetTracker for cost control and
      # usage limits across all agent types.
      module BudgetAware
        extend ActiveSupport::Concern

        private

        # Checks budget before execution
        #
        # @raise [BudgetExceededError] If budget exceeded with hard enforcement
        def check_budget!
          return unless budgets_enabled?

          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: execution_type
          )
        end

        # Records spend after execution
        #
        # @param cost [Float] Cost in USD
        # @param tokens [Integer] Total tokens used
        def record_spend!(cost:, tokens:)
          return unless budgets_enabled?

          BudgetTracker.record_spend!(
            tenant_id: @tenant_id,
            cost: cost,
            tokens: tokens
          )
        end

        # Returns whether budgets are enabled
        def budgets_enabled?
          RubyLLM::Agents.configuration.budgets_enabled?
        end
      end
    end
  end
end
```

#### CacheAware Concern

**File:** `lib/ruby_llm/agents/concerns/cache_aware.rb`

```ruby
module RubyLLM
  module Agents
    module Concerns
      # Provides caching infrastructure for agent results
      #
      # Handles cache key generation, store access, and
      # TTL management across all agent types.
      module CacheAware
        extend ActiveSupport::Concern

        private

        # Returns the configured cache store
        #
        # @return [ActiveSupport::Cache::Store]
        def cache_store
          RubyLLM::Agents.configuration.cache_store
        end

        # Checks if caching is enabled for this agent
        #
        # @return [Boolean]
        def cache_enabled?
          self.class.respond_to?(:cache_enabled?) && self.class.cache_enabled?
        end

        # Returns the cache TTL for this agent
        #
        # @return [ActiveSupport::Duration, nil]
        def cache_ttl
          self.class.respond_to?(:cache_ttl) ? self.class.cache_ttl : nil
        end

        # Generates a cache key for the given data
        #
        # @param data [Hash, String] Data to include in cache key
        # @return [String] The cache key
        def generate_cache_key(data)
          components = [
            "ruby_llm_agents",
            execution_type,
            self.class.name,
            self.class.respond_to?(:version) ? self.class.version : "1.0",
            Digest::SHA256.hexdigest(data.to_json)
          ].compact

          components.join("/")
        end

        # Reads from cache
        #
        # @param key [String] Cache key
        # @return [Object, nil] Cached value or nil
        def cache_read(key)
          return nil unless cache_enabled?
          cache_store.read(key)
        end

        # Writes to cache
        #
        # @param key [String] Cache key
        # @param value [Object] Value to cache
        def cache_write(key, value)
          return unless cache_enabled?
          cache_store.write(key, value, expires_in: cache_ttl)
        end
      end
    end
  end
end
```

#### Instrumentable Concern

**File:** `lib/ruby_llm/agents/concerns/instrumentable.rb`

```ruby
module RubyLLM
  module Agents
    module Concerns
      # Provides execution tracking and instrumentation
      #
      # Records successful and failed executions for observability,
      # cost tracking, and usage analytics.
      module Instrumentable
        extend ActiveSupport::Concern

        included do
          attr_reader :execution_started_at, :execution_completed_at
        end

        private

        # Marks execution start
        def start_execution!
          @execution_started_at = Time.current
        end

        # Marks execution completion
        def complete_execution!
          @execution_completed_at = Time.current
        end

        # Returns execution duration in milliseconds
        #
        # @return [Integer, nil]
        def duration_ms
          return nil unless @execution_started_at && @execution_completed_at
          ((@execution_completed_at - @execution_started_at) * 1000).to_i
        end

        # Records a successful execution
        #
        # @param result [Result] The execution result
        # @param metadata [Hash] Additional metadata
        def record_execution(result, metadata: {})
          return unless tracking_enabled?

          execution_data = build_execution_data(
            status: "success",
            result: result,
            metadata: metadata
          )

          persist_execution(execution_data)
        end

        # Records a failed execution
        #
        # @param error [StandardError] The error that occurred
        # @param metadata [Hash] Additional metadata
        def record_failed_execution(error, metadata: {})
          return unless tracking_enabled?

          execution_data = build_execution_data(
            status: "error",
            error: error,
            metadata: metadata
          )

          persist_execution(execution_data)
        end

        # Builds execution data hash
        #
        # @param status [String] "success" or "error"
        # @param result [Result, nil] Execution result
        # @param error [StandardError, nil] Error if failed
        # @param metadata [Hash] Additional metadata
        # @return [Hash]
        def build_execution_data(status:, result: nil, error: nil, metadata: {})
          data = {
            agent_type: self.class.name,
            execution_type: execution_type,
            model_id: resolve_model_for_tracking,
            status: status,
            duration_ms: duration_ms,
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            tenant_id: @tenant_id,
            metadata: metadata
          }

          if result
            data.merge!(
              input_tokens: result.respond_to?(:input_tokens) ? result.input_tokens : 0,
              output_tokens: result.respond_to?(:output_tokens) ? result.output_tokens : 0,
              total_cost: result.respond_to?(:total_cost) ? result.total_cost : 0
            )
          end

          if error
            data.merge!(
              error_class: error.class.name,
              error_message: error.message.to_s.truncate(1000)
            )
          end

          data
        end

        # Persists execution data (sync or async)
        #
        # @param data [Hash] Execution data
        def persist_execution(data)
          return unless defined?(RubyLLM::Agents::Execution)

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(data)
          else
            RubyLLM::Agents::Execution.create!(data)
          end
        rescue StandardError => e
          log_tracking_error(e)
        end

        # Returns whether execution tracking is enabled
        #
        # @return [Boolean]
        def tracking_enabled?
          config = RubyLLM::Agents.configuration
          case execution_type
          when "embedding" then config.track_embeddings
          when "moderation" then config.track_moderations
          when "image" then config.track_image_generations
          when "audio" then config.track_audio
          else config.track_executions
          end
        end

        # Resolves model for tracking purposes
        #
        # @return [String, nil]
        def resolve_model_for_tracking
          return @options[:model] if @options[:model]
          return self.class.model if self.class.respond_to?(:model)
          nil
        end

        # Logs tracking errors without raising
        #
        # @param error [StandardError]
        def log_tracking_error(error)
          return unless defined?(Rails)
          Rails.logger.error("[RubyLLM::Agents] Failed to record execution: #{error.message}")
        end
      end
    end
  end
end
```

#### Reliable Concern

**File:** `lib/ruby_llm/agents/concerns/reliable.rb`

```ruby
module RubyLLM
  module Agents
    module Concerns
      # Provides reliability features: retries, fallbacks, circuit breakers
      #
      # Wraps agent execution with automatic retry logic, model fallback
      # routing, and circuit breaker protection.
      module Reliable
        extend ActiveSupport::Concern

        private

        # Executes with reliability wrapper
        #
        # @yield The execution block
        # @return [Object] Result from the block
        def with_reliability(&block)
          return yield unless reliability_enabled?

          attempts = 0
          current_model = resolve_model_for_tracking
          models_to_try = [current_model] + (self.class.fallback_models || [])

          models_to_try.each do |model|
            attempts += 1

            # Check circuit breaker
            breaker = get_circuit_breaker(model)
            next if breaker&.open?

            begin
              check_total_timeout!
              result = with_retries(model: model, &block)
              breaker&.record_success
              return result
            rescue => e
              breaker&.record_failure
              raise unless should_fallback?(e) && models_to_try.index(model) < models_to_try.size - 1
            end
          end

          raise Reliability::AllModelsFailedError, "All models failed after #{attempts} attempts"
        end

        # Executes with retry logic for a specific model
        #
        # @param model [String] Model to use
        # @yield The execution block
        # @return [Object] Result from the block
        def with_retries(model:, &block)
          max_retries = self.class.respond_to?(:retries) ? self.class.retries : 0
          attempt = 0

          begin
            attempt += 1
            @current_model = model
            yield
          rescue => e
            if attempt <= max_retries && retryable_error?(e)
              sleep(backoff_delay(attempt))
              retry
            end
            raise
          end
        end

        # Returns whether reliability features are enabled
        #
        # @return [Boolean]
        def reliability_enabled?
          return false unless self.class.respond_to?(:retries) || self.class.respond_to?(:fallback_models)
          (self.class.retries&.positive? || self.class.fallback_models&.any?)
        end

        # Returns whether an error is retryable
        #
        # @param error [StandardError]
        # @return [Boolean]
        def retryable_error?(error)
          Reliability.retryable_error?(error)
        end

        # Returns whether to fallback on error
        #
        # @param error [StandardError]
        # @return [Boolean]
        def should_fallback?(error)
          Reliability.fallback_eligible_error?(error)
        end

        # Returns backoff delay for retry attempt
        #
        # @param attempt [Integer] Current attempt number
        # @return [Float] Delay in seconds
        def backoff_delay(attempt)
          base = self.class.respond_to?(:retry_delay) ? self.class.retry_delay : 1.0
          base * (2 ** (attempt - 1)) + rand(0.0..0.5)
        end

        # Gets circuit breaker for model
        #
        # @param model [String]
        # @return [CircuitBreaker, nil]
        def get_circuit_breaker(model)
          return nil unless self.class.respond_to?(:circuit_breaker_enabled?) && self.class.circuit_breaker_enabled?
          Reliability::BreakerManager.breaker_for(model, tenant_id: @tenant_id)
        end

        # Checks total timeout
        #
        # @raise [TotalTimeoutError] If total timeout exceeded
        def check_total_timeout!
          return unless @execution_started_at
          return unless self.class.respond_to?(:total_timeout) && self.class.total_timeout

          elapsed = Time.current - @execution_started_at
          if elapsed > self.class.total_timeout
            raise Reliability::TotalTimeoutError, "Total timeout of #{self.class.total_timeout}s exceeded"
          end
        end
      end
    end
  end
end
```

### Updated Agent Types

#### Conversation Agent (Base)

**File:** `lib/ruby_llm/agents/core/base.rb`

```ruby
module RubyLLM
  module Agents
    # Base class for conversation-based LLM agents
    #
    # Provides a DSL for configuring agents that have multi-turn
    # conversations with language models.
    class Base < Agent
      self.agent_type = :conversation

      # Conversation-specific concerns
      include Conversation::ToolTracking
      include Conversation::ResponseBuilding
      include Conversation::ModerationExecution
      include Conversation::Execution

      # Conversation-specific DSL
      extend Conversation::DSL
      extend Conversation::ModerationDSL

      attr_reader :model, :temperature, :client, :accumulated_tool_calls

      def initialize(model: self.class.model, temperature: self.class.temperature, **options)
        super(**options)
        @model = model
        @temperature = temperature
        @accumulated_tool_calls = []
        validate_required_params!
        @client = build_client
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
    end
  end
end
```

#### Embedder

**File:** `lib/ruby_llm/agents/text/embedder.rb`

```ruby
module RubyLLM
  module Agents
    # Embedding generator agent
    #
    # Now inherits from Agent, gaining reliability features automatically.
    class Embedder < Agent
      self.agent_type = :embedding

      extend Embedding::DSL
      include Embedding::Execution

      attr_reader :options

      def initialize(**options)
        super(**options)
      end

      class << self
        def call(text: nil, texts: nil, **options, &block)
          new(**options).call(text: text, texts: texts, &block)
        end
      end

      # Now supports reliability!
      # class MyEmbedder < RubyLLM::Agents::Embedder
      #   model "text-embedding-3-large"
      #   retries 3
      #   fallback_models "text-embedding-3-small"
      # end
    end
  end
end
```

#### ImageGenerator

**File:** `lib/ruby_llm/agents/image/generator.rb`

```ruby
module RubyLLM
  module Agents
    # Image generation agent
    #
    # Now inherits from Agent, gaining reliability features automatically.
    class ImageGenerator < Agent
      self.agent_type = :image

      extend Image::GeneratorDSL
      include Image::GeneratorExecution

      attr_reader :prompt, :options

      def initialize(prompt:, **options)
        super(**options)
        @prompt = prompt
      end

      class << self
        def call(prompt:, **options)
          new(prompt: prompt, **options).call
        end
      end

      # Now supports reliability!
      # class MyGenerator < RubyLLM::Agents::ImageGenerator
      #   model "dall-e-3"
      #   retries 2
      #   fallback_models "dall-e-2"
      #   circuit_breaker threshold: 5
      # end
    end
  end
end
```

---

## Implementation Phases

### Phase 1: Create Shared Concerns

**Goal:** Extract common logic into reusable concerns without breaking existing code.

#### Tasks

1. **Create concerns directory structure**
   ```
   lib/ruby_llm/agents/concerns/
   ├── tenant_aware.rb
   ├── budget_aware.rb
   ├── cache_aware.rb
   ├── instrumentable.rb
   ├── reliable.rb
   ├── base_dsl.rb
   └── reliability_dsl.rb
   ```

2. **Extract TenantAware from Embedder::Execution**
   - Copy `resolve_tenant_context!` logic
   - Add tests for all tenant formats

3. **Extract BudgetAware from Embedder::Execution**
   - Copy `check_budget!` and spend recording
   - Ensure BudgetTracker compatibility

4. **Extract CacheAware from Base::Caching**
   - Generalize cache key generation
   - Support different cache strategies per agent type

5. **Extract Instrumentable from multiple sources**
   - Merge execution recording from all agents
   - Support execution_type discrimination

6. **Extract Reliable from Base::ReliabilityExecution**
   - Make retry/fallback/circuit breaker work for any agent
   - Support model resolution per agent type

#### Acceptance Criteria

- [ ] All concerns have comprehensive tests
- [ ] Concerns work in isolation (can be included individually)
- [ ] No changes to public API yet

---

### Phase 2: Create Agent Base Class

**Goal:** Introduce the unified Agent class that includes all concerns.

#### Tasks

1. **Create Agent class**
   ```ruby
   # lib/ruby_llm/agents/core/agent.rb
   class Agent
     include Concerns::TenantAware
     include Concerns::BudgetAware
     include Concerns::CacheAware
     include Concerns::Instrumentable
     include Concerns::Reliable

     extend Concerns::BaseDSL
     extend Concerns::ReliabilityDSL
   end
   ```

2. **Add agent_type class attribute**
   - Support: `:conversation`, `:embedding`, `:image`, `:moderation`, `:audio`
   - Inherit to subclasses

3. **Add shared DSL methods**
   - `model`, `version`, `cache_for`, `retries`, `fallback_models`, etc.
   - These become available to ALL agent types

4. **Update require order in agents.rb**
   - Load Agent before specific types
   - Maintain backward compatibility

#### Acceptance Criteria

- [ ] Agent class exists and includes all concerns
- [ ] agent_type propagates to subclasses
- [ ] Shared DSL methods work on Agent

---

### Phase 3: Migrate Existing Agents

**Goal:** Update all agent types to inherit from Agent.

#### 3.1 Migrate Base (Conversation Agents)

```ruby
# Before
class Base
  include Instrumentation
  include Caching
  # ... 8 more includes
end

# After
class Base < Agent
  self.agent_type = :conversation

  # Only conversation-specific concerns
  include Conversation::ToolTracking
  include Conversation::ResponseBuilding
  include Conversation::Execution

  extend Conversation::DSL
end
```

#### 3.2 Migrate Embedder

```ruby
# Before
class Embedder
  extend DSL
  include Execution
end

# After
class Embedder < Agent
  self.agent_type = :embedding

  extend Embedding::DSL
  include Embedding::Execution
end
```

#### 3.3 Migrate Image Agents

- ImageGenerator
- ImageAnalyzer
- ImageEditor
- ImageTransformer
- ImageUpscaler
- ImageVariator
- BackgroundRemover
- ImagePipeline

#### 3.4 Migrate Audio Agents

- Speaker
- Transcriber

#### 3.5 Migrate Text Agents

- Moderator

#### Tasks per Agent

1. Change inheritance to `< Agent`
2. Set `self.agent_type = :type`
3. Remove duplicated concerns (tenant, budget, cache, instrumentation)
4. Keep only agent-specific DSL and Execution modules
5. Update tests

#### Acceptance Criteria

- [ ] All agents inherit from Agent
- [ ] All agents have correct agent_type
- [ ] Duplicated code removed
- [ ] All existing tests pass

---

### Phase 4: Enable Reliability for All Agents

**Goal:** Make retries, fallbacks, and circuit breakers work for all agent types.

#### Tasks

1. **Update Embedding::Execution to use `with_reliability`**
   ```ruby
   def call(text: nil, texts: nil, &block)
     start_execution!
     check_budget!

     with_reliability do
       # existing embedding logic
     end
   ensure
     complete_execution!
   end
   ```

2. **Update Image::GeneratorExecution similarly**

3. **Update Audio agent executions**

4. **Add reliability DSL examples to documentation**

#### Acceptance Criteria

- [ ] `retries` DSL works on Embedder
- [ ] `fallback_models` DSL works on ImageGenerator
- [ ] `circuit_breaker` DSL works on all agents
- [ ] New tests for reliability on standalone agents

---

### Phase 5: Cleanup and Documentation

**Goal:** Remove dead code, update documentation, ensure smooth migration.

#### Tasks

1. **Remove duplicate code from old Execution modules**
   - Delete `resolve_tenant_context!` from each agent
   - Delete `check_budget!` from each agent
   - Delete `record_execution` from each agent
   - Delete `cache_store` from each agent

2. **Add deprecation warnings for direct subclassing**
   ```ruby
   # If someone was doing something weird
   def self.inherited(subclass)
     super
     unless subclass.ancestors.include?(Agent)
       warn "[DEPRECATION] Direct inclusion of agent modules is deprecated. " \
            "Inherit from RubyLLM::Agents::Agent instead."
     end
   end
   ```

3. **Update YARD documentation**
   - Document Agent class
   - Document all concerns
   - Update examples

4. **Update README and Wiki**
   - New architecture diagram
   - Migration guide for custom agents
   - Reliability examples for all agent types

5. **Update CHANGELOG**

#### Acceptance Criteria

- [ ] No duplicate code remains
- [ ] All public APIs documented
- [ ] Migration guide exists
- [ ] CHANGELOG updated

---

## File Structure (Target State)

```
lib/ruby_llm/agents/
├── agents.rb                          # Main entry point

├── concerns/                          # NEW: Shared concerns
│   ├── tenant_aware.rb
│   ├── budget_aware.rb
│   ├── cache_aware.rb
│   ├── instrumentable.rb
│   ├── reliable.rb
│   ├── base_dsl.rb
│   └── reliability_dsl.rb

├── core/
│   ├── agent.rb                       # NEW: Universal base class
│   ├── base.rb                        # Updated: inherits from Agent
│   ├── base/
│   │   ├── dsl.rb                     # Renamed: conversation/dsl.rb
│   │   ├── execution.rb               # Renamed: conversation/execution.rb
│   │   ├── tool_tracking.rb
│   │   ├── response_building.rb
│   │   ├── moderation_dsl.rb
│   │   └── moderation_execution.rb
│   ├── configuration.rb
│   ├── errors.rb
│   └── version.rb

├── text/
│   ├── embedder.rb                    # Updated: inherits from Agent
│   ├── embedder/
│   │   ├── dsl.rb                     # Slimmed: no tenant/budget/cache
│   │   └── execution.rb               # Slimmed: uses with_reliability
│   └── moderator.rb                   # Updated: inherits from Agent

├── image/
│   ├── generator.rb                   # Updated: inherits from Agent
│   ├── generator/
│   │   ├── dsl.rb                     # Slimmed
│   │   └── execution.rb               # Slimmed
│   ├── analyzer.rb
│   ├── editor.rb
│   └── ...

├── audio/
│   ├── speaker.rb                     # Updated: inherits from Agent
│   └── transcriber.rb                 # Updated: inherits from Agent

├── infrastructure/                    # Unchanged
│   ├── reliability/
│   ├── budget/
│   └── ...

└── results/                           # Unchanged
    ├── base.rb
    ├── embedding_result.rb
    └── ...
```

---

## Migration Guide

### For Users with Custom Agents

#### Before (Custom Embedder)

```ruby
class MyEmbedder < RubyLLM::Agents::Embedder
  model "text-embedding-3-small"
  dimensions 512
end
```

#### After (No Changes Required!)

```ruby
# Same code works, but now you can add:
class MyEmbedder < RubyLLM::Agents::Embedder
  model "text-embedding-3-small"
  dimensions 512

  # NEW: These now work!
  retries 3
  fallback_models "text-embedding-ada-002"
  circuit_breaker threshold: 5, timeout: 30
end
```

### For Users with Custom Base Agents

#### Before

```ruby
class MyAgent < RubyLLM::Agents::Base
  model "gpt-4"
  retries 3
end
```

#### After (No Changes Required!)

```ruby
# Same code works exactly the same
class MyAgent < RubyLLM::Agents::Base
  model "gpt-4"
  retries 3
end
```

### For Users Including Modules Directly

#### Before (Rare Edge Case)

```ruby
class CustomThing
  include RubyLLM::Agents::Embedder::Execution
  extend RubyLLM::Agents::Embedder::DSL
end
```

#### After

```ruby
# This still works but will show deprecation warning
# Recommended: inherit from Agent instead
class CustomThing < RubyLLM::Agents::Agent
  self.agent_type = :custom

  extend MyCustomDSL
  include MyCustomExecution
end
```

---

## API Reference (Final)

### Agent Class

```ruby
class RubyLLM::Agents::Agent
  # Class Attributes
  agent_type    # Symbol - :conversation, :embedding, :image, :moderation, :audio

  # Instance Attributes (from concerns)
  tenant_id       # String or nil
  tenant_object   # Object or nil
  tenant_config   # Hash or nil
  options         # Hash

  # Instance Methods
  call            # Abstract - must be implemented by subclasses
  execution_type  # String - returns agent_type as string
end
```

### Shared DSL (All Agents)

```ruby
class MyAgent < RubyLLM::Agents::Agent
  # Model configuration
  model "gpt-4"                    # Set default model
  version "1.0"                    # Cache version

  # Caching
  cache_for 1.hour                 # Enable caching with TTL

  # Reliability (NEW for standalone agents!)
  retries 3                        # Number of retry attempts
  retry_delay 1.0                  # Base delay between retries (exponential backoff)
  fallback_models "gpt-3.5", "..." # Models to try if primary fails
  total_timeout 60                 # Maximum total execution time

  # Circuit breaker (NEW for standalone agents!)
  circuit_breaker(
    threshold: 5,                  # Failures before opening
    timeout: 30,                   # Seconds before half-open
    half_open_limit: 3             # Requests in half-open state
  )
end
```

### Agent Types and Their DSL

#### Conversation (Base)

```ruby
class MyChat < RubyLLM::Agents::Base
  # Shared DSL (above) plus:
  temperature 0.7
  timeout 30
  streaming true

  # Parameters
  param :query, required: true
  param :context, default: nil

  # Tools
  tools MyTool, AnotherTool

  # Moderation
  moderate_input policy: :strict
  moderate_output policy: :standard

  # Thinking (Claude)
  enable_thinking budget_tokens: 5000
end
```

#### Embedding

```ruby
class MyEmbedder < RubyLLM::Agents::Embedder
  # Shared DSL plus:
  model "text-embedding-3-small"
  dimensions 512
  batch_size 100
end
```

#### Image Generation

```ruby
class MyGenerator < RubyLLM::Agents::ImageGenerator
  # Shared DSL plus:
  model "dall-e-3"
  size "1024x1024"
  quality "hd"
  style "vivid"

  content_policy :strict
  template "A {subject} in {style} style"
end
```

#### Audio (Speaker/Transcriber)

```ruby
class MySpeaker < RubyLLM::Agents::Speaker
  # Shared DSL plus:
  model "tts-1"
  voice "alloy"
  speed 1.0
end

class MyTranscriber < RubyLLM::Agents::Transcriber
  # Shared DSL plus:
  model "whisper-1"
  language "en"
end
```

---

## Testing Strategy

### Unit Tests for Concerns

```ruby
# spec/ruby_llm/agents/concerns/tenant_aware_spec.rb
RSpec.describe RubyLLM::Agents::Concerns::TenantAware do
  let(:test_class) do
    Class.new do
      include RubyLLM::Agents::Concerns::TenantAware
      attr_accessor :options
      def initialize(options = {})
        @options = options
      end
    end
  end

  describe "#resolve_tenant_context!" do
    it "handles nil tenant"
    it "handles hash tenant"
    it "handles object with llm_tenant_id"
    it "raises for invalid tenant"
    it "is idempotent"
  end
end
```

### Integration Tests

```ruby
# spec/ruby_llm/agents/integration/unified_architecture_spec.rb
RSpec.describe "Unified Agent Architecture" do
  describe "reliability on Embedder" do
    it "retries on transient errors"
    it "falls back to secondary model"
    it "respects circuit breaker"
  end

  describe "reliability on ImageGenerator" do
    it "retries on transient errors"
    it "falls back to secondary model"
  end

  describe "tenant isolation" do
    it "isolates circuit breakers by tenant"
    it "tracks budget per tenant"
  end
end
```

### Backward Compatibility Tests

```ruby
# spec/ruby_llm/agents/backward_compatibility_spec.rb
RSpec.describe "Backward Compatibility" do
  it "existing Base subclasses work unchanged"
  it "existing Embedder subclasses work unchanged"
  it "existing ImageGenerator subclasses work unchanged"
  it "shows deprecation for direct module inclusion"
end
```

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing subclasses | High | Extensive backward compatibility tests; deprecation warnings before removal |
| Performance overhead from additional inheritance | Low | Benchmark before/after; concerns are lightweight |
| Complexity in concern interactions | Medium | Clear concern boundaries; comprehensive tests |
| Reliability features causing unexpected behavior | Medium | Opt-in reliability (only if DSL methods used); clear documentation |

---

## Success Metrics

1. **Code Reduction:** ~300 lines of duplicated code eliminated
2. **Feature Parity:** All 8+ agent types support retries, fallbacks, circuit breakers
3. **Test Coverage:** >95% coverage on new concerns
4. **Zero Breaking Changes:** All existing tests pass without modification
5. **Documentation:** Complete API reference and migration guide

---

## Timeline Estimate

| Phase | Description | Complexity |
|-------|-------------|------------|
| Phase 1 | Create Shared Concerns | Medium |
| Phase 2 | Create Agent Base Class | Low |
| Phase 3 | Migrate Existing Agents | High |
| Phase 4 | Enable Reliability for All | Medium |
| Phase 5 | Cleanup and Documentation | Low |

---

## Open Questions

1. **Should reliability be opt-in or opt-out for standalone agents?**
   - Current plan: Opt-in (only active if DSL methods used)
   - Alternative: Always active with sensible defaults

2. **Should we add a `disable_reliability` DSL method?**
   - For cases where users want to handle errors themselves

3. **How to handle agent-specific circuit breaker keys?**
   - Current: `{model}:{tenant_id}`
   - Alternative: `{agent_type}:{model}:{tenant_id}`

4. **Should Agent be abstract (raise on direct instantiation)?**
   - Current plan: No, allow direct use for advanced cases
   - Alternative: Require subclassing

---

## Next Steps

1. [ ] Review and approve plan
2. [ ] Create feature branch: `feature/unified-agent-architecture`
3. [ ] Implement Phase 1: Shared Concerns
4. [ ] Implement Phase 2: Agent Base Class
5. [ ] Implement Phase 3: Migrate Agents (one at a time)
6. [ ] Implement Phase 4: Enable Reliability
7. [ ] Implement Phase 5: Cleanup
8. [ ] Update CHANGELOG
9. [ ] Release as minor version (backward compatible)
