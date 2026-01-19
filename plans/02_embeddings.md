# Embeddings Support Implementation Plan

## Overview

Add an `Embedder` base class to ruby_llm-agents for generating text embeddings (vectors). This enables semantic search, RAG pipelines, document similarity, and recommendations while maintaining the gem's execution tracking, budget controls, and multi-tenancy features.

## Why Embedder as a Base Class?

Embeddings are fundamentally different from chat agents:
- No prompts or system instructions
- No streaming
- No tool calling
- Batch processing is common
- Output is vectors, not text

However, they still benefit from:
- Execution tracking (cost monitoring)
- Budget controls (embeddings cost money)
- Multi-tenancy (per-tenant API keys and limits)
- Consistent class-based pattern

## Supported Models

| Provider | Model | Dimensions | Notes |
|----------|-------|------------|-------|
| OpenAI | `text-embedding-3-small` | 1536 (default) | Default model |
| OpenAI | `text-embedding-3-large` | 3072 (default) | Higher quality |
| Google | `text-embedding-004` | 768 | Gemini embeddings |
| Voyage | `voyage-3` | 1024 | Specialized embeddings |
| Cohere | `embed-english-v3.0` | 1024 | Multilingual available |

## API Design

### Basic Usage

```ruby
class DocumentEmbedder < RubyLLM::Agents::Embedder
  model 'text-embedding-3-small'
  dimensions 512  # Optional: reduce dimensions for storage
end

# Single text
result = DocumentEmbedder.call(text: "Ruby is a great language")
result.vectors      # [0.123, -0.456, 0.789, ...]
result.dimensions   # 512
result.model_id     # "text-embedding-3-small"
result.input_tokens # 6
result.total_cost   # 0.00001

# Batch processing
result = DocumentEmbedder.call(texts: [
  "First document",
  "Second document",
  "Third document"
])
result.vectors      # [[...], [...], [...]]
result.count        # 3
result.input_tokens # 9
result.total_cost   # 0.00003
```

### With Configuration Options

```ruby
class ProductEmbedder < RubyLLM::Agents::Embedder
  model 'text-embedding-3-large'
  dimensions 1024
  batch_size 100        # Max texts per API call

  # Optional: preprocessing
  def preprocess(text)
    text.strip.downcase.gsub(/\s+/, ' ')
  end
end
```

### Runtime Override

```ruby
# Override model at call time
result = DocumentEmbedder.call(
  text: "Hello",
  model: 'text-embedding-3-large',
  dimensions: 256
)

# With tenant
result = DocumentEmbedder.call(
  text: "Hello",
  tenant: current_organization
)
```

### Batch Processing with Progress

```ruby
# Large batch with automatic chunking
texts = Document.pluck(:content)  # 10,000 documents

DocumentEmbedder.call(texts: texts) do |batch_result, index|
  # Called after each batch completes
  puts "Processed batch #{index}: #{batch_result.count} texts"
end
```

## Implementation Tasks

### 1. Embedder Base Class (`lib/ruby_llm/agents/embedder.rb`)

Create the main Embedder class with DSL methods:

```ruby
module RubyLLM
  module Agents
    class Embedder
      class << self
        def model(model_name = nil)
          @model = model_name if model_name
          @model || RubyLLM::Agents.configuration.default_embedding_model
        end

        def dimensions(dims = nil)
          @dimensions = dims if dims
          @dimensions
        end

        def batch_size(size = nil)
          @batch_size = size if size
          @batch_size || 100
        end

        def call(text: nil, texts: nil, **options, &block)
          new.call(text: text, texts: texts, **options, &block)
        end
      end

      def call(text: nil, texts: nil, **options, &block)
        # Implementation
      end
    end
  end
end
```

### 2. Embedder DSL (`lib/ruby_llm/agents/embedder/dsl.rb`)

DSL methods for configuration:

```ruby
module RubyLLM
  module Agents
    class Embedder
      module DSL
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # model - embedding model to use
          def model(model_name = nil)
            if model_name
              @model = model_name
            end
            @model || RubyLLM::Agents.configuration.default_embedding_model
          end

          # dimensions - vector dimensions (some models support reduction)
          def dimensions(dims = nil)
            if dims
              @dimensions = dims
            end
            @dimensions
          end

          # batch_size - max texts per API call
          def batch_size(size = nil)
            if size
              @batch_size = size
            end
            @batch_size || 100
          end

          # version - for cache invalidation
          def version(v = nil)
            if v
              @version = v
            end
            @version
          end
        end
      end
    end
  end
end
```

### 3. Embedder Execution (`lib/ruby_llm/agents/embedder/execution.rb`)

Core execution logic:

```ruby
module RubyLLM
  module Agents
    class Embedder
      module Execution
        def call(text: nil, texts: nil, **options, &block)
          input_texts = normalize_input(text, texts)
          validate_input!(input_texts)

          results = []
          batches = input_texts.each_slice(resolved_batch_size).to_a

          batches.each_with_index do |batch, index|
            batch_result = execute_batch(batch, options)
            results << batch_result

            yield(batch_result, index) if block_given?
          end

          build_result(results, input_texts)
        end

        private

        def execute_batch(texts, options)
          preprocessed = texts.map { |t| preprocess(t) }

          embedding = RubyLLM.embed(
            preprocessed,
            model: resolved_model(options),
            dimensions: resolved_dimensions(options)
          )

          record_execution(embedding, texts.size)
          embedding
        end

        def preprocess(text)
          # Override in subclass for custom preprocessing
          text
        end

        def normalize_input(text, texts)
          if text && texts
            raise ArgumentError, "Provide either text: or texts:, not both"
          end
          texts || [text]
        end
      end
    end
  end
end
```

### 4. Embedding Result (`lib/ruby_llm/agents/embedder/result.rb`)

Result object for embeddings:

```ruby
module RubyLLM
  module Agents
    class EmbeddingResult
      attr_reader :vectors, :model_id, :dimensions, :input_tokens,
                  :total_cost, :duration_ms, :count, :started_at,
                  :completed_at, :tenant_id

      def initialize(attributes = {})
        @vectors = attributes[:vectors]
        @model_id = attributes[:model_id]
        @dimensions = attributes[:dimensions]
        @input_tokens = attributes[:input_tokens]
        @total_cost = attributes[:total_cost]
        @duration_ms = attributes[:duration_ms]
        @count = attributes[:count]
        @started_at = attributes[:started_at]
        @completed_at = attributes[:completed_at]
        @tenant_id = attributes[:tenant_id]
      end

      def single?
        count == 1
      end

      def batch?
        count > 1
      end

      # For single embeddings, return the vector directly
      def vector
        single? ? vectors.first : nil
      end

      # Cosine similarity helper
      def similarity(other_vector, index: 0)
        v1 = vectors[index]
        v2 = other_vector.is_a?(EmbeddingResult) ? other_vector.vector : other_vector
        cosine_similarity(v1, v2)
      end

      private

      def cosine_similarity(a, b)
        dot = a.zip(b).sum { |x, y| x * y }
        mag_a = Math.sqrt(a.sum { |x| x * x })
        mag_b = Math.sqrt(b.sum { |x| x * x })
        dot / (mag_a * mag_b)
      end
    end
  end
end
```

### 5. Execution Tracking Integration

Update instrumentation to track embedding executions:

```ruby
# In embedder/execution.rb
def record_execution(embedding, text_count)
  return unless RubyLLM::Agents.configuration.track_embeddings

  RubyLLM::Agents::Execution.create!(
    agent_type: self.class.name,
    execution_type: 'embedding',  # New field
    model_id: embedding.model,
    input_tokens: embedding.input_tokens,
    output_tokens: 0,
    total_cost: calculate_cost(embedding),
    duration_ms: @duration_ms,
    status: 'success',
    metadata: {
      text_count: text_count,
      dimensions: embedding.vectors.first&.size
    },
    tenant_id: @tenant_id
  )
end
```

### 6. Database Migration (Optional)

Add execution_type to executions table:

```ruby
class AddExecutionTypeToExecutions < ActiveRecord::Migration[7.0]
  def change
    add_column :ruby_llm_agents_executions, :execution_type, :string, default: 'chat'
    add_index :ruby_llm_agents_executions, :execution_type
  end
end
```

### 7. Configuration Options (`lib/ruby_llm/agents/configuration.rb`)

Add embedding-specific configuration:

```ruby
module RubyLLM
  module Agents
    class Configuration
      # Existing options...

      # Embedding defaults
      attr_accessor :default_embedding_model
      attr_accessor :default_embedding_dimensions
      attr_accessor :default_embedding_batch_size
      attr_accessor :track_embeddings

      def initialize
        # Existing defaults...

        # Embedding defaults
        @default_embedding_model = 'text-embedding-3-small'
        @default_embedding_dimensions = nil  # Use model default
        @default_embedding_batch_size = 100
        @track_embeddings = true
      end
    end
  end
end
```

### 8. Budget Integration

Embeddings should count toward budgets:

```ruby
# In embedder/execution.rb
def check_budget!
  return unless RubyLLM::Agents.configuration.budgets

  BudgetTracker.check!(
    agent_type: self.class.name,
    tenant_id: @tenant_id,
    execution_type: 'embedding'
  )
end
```

### 9. Multi-Tenancy Support

```ruby
# Tenant-specific embedding
result = DocumentEmbedder.call(
  text: "Hello",
  tenant: current_organization  # Uses tenant's API keys and counts toward their budget
)
```

### 10. Documentation (`wiki/Embeddings.md`)

Create comprehensive documentation covering:
- Overview and use cases
- Basic usage examples
- Batch processing
- Configuration options
- RAG integration patterns
- Cost considerations
- Database storage with pgvector

## File Structure

```
lib/ruby_llm/agents/
├── embedder.rb                    # Main embedder class
├── embedder/
│   ├── dsl.rb                     # DSL methods
│   ├── execution.rb               # Execution logic
│   └── result.rb                  # EmbeddingResult class
├── embedding_result.rb            # Result object (alternative location)
└── configuration.rb               # Updated with embedding config

wiki/
└── Embeddings.md                  # Documentation

spec/
├── embedder_spec.rb               # Unit tests
└── embedder/
    ├── dsl_spec.rb
    ├── execution_spec.rb
    └── result_spec.rb
```

## Usage Examples

### Semantic Search

```ruby
class SearchEmbedder < RubyLLM::Agents::Embedder
  model 'text-embedding-3-small'
  dimensions 512
end

# Index documents
Document.find_each do |doc|
  result = SearchEmbedder.call(text: doc.content)
  doc.update!(embedding: result.vector)
end

# Search
query_result = SearchEmbedder.call(text: "How to deploy Rails apps?")
similar_docs = Document.nearest_neighbors(:embedding, query_result.vector, distance: :cosine).limit(10)
```

### RAG Pipeline

```ruby
class RAGEmbedder < RubyLLM::Agents::Embedder
  model 'text-embedding-3-small'

  def preprocess(text)
    # Clean and normalize text for better embeddings
    text.strip.gsub(/\s+/, ' ').truncate(8000)
  end
end

class RAGAgent < ApplicationAgent
  model 'gpt-4o'

  param :question, required: true

  def system_prompt
    context = retrieve_context(question)
    <<~PROMPT
      Answer based on this context:
      #{context}
    PROMPT
  end

  private

  def retrieve_context(question)
    embedding = RAGEmbedder.call(text: question)
    chunks = KnowledgeChunk.nearest_neighbors(:embedding, embedding.vector, distance: :cosine).limit(5)
    chunks.map(&:content).join("\n\n")
  end
end
```

### Batch Processing with Progress

```ruby
class BulkEmbedder < RubyLLM::Agents::Embedder
  model 'text-embedding-3-small'
  batch_size 50
end

texts = Article.pluck(:content)
progress = ProgressBar.create(total: texts.size)

result = BulkEmbedder.call(texts: texts) do |batch_result, index|
  progress.progress += batch_result.count
end

puts "Total cost: $#{result.total_cost}"
puts "Total tokens: #{result.input_tokens}"
```

## Cost Tracking

Embeddings are cheap but can add up at scale:

| Model | Price per 1M tokens |
|-------|---------------------|
| text-embedding-3-small | $0.02 |
| text-embedding-3-large | $0.13 |
| text-embedding-004 | $0.00 (free tier) |

With execution tracking, users can monitor:
- Total embedding costs per day/month
- Costs per tenant
- Costs per embedder class

## Testing Strategy

1. **Unit Tests**
   - DSL configuration parsing
   - Input normalization (text vs texts)
   - Batch splitting logic
   - Result object construction

2. **Integration Tests**
   - Mock ruby_llm embed responses
   - Verify execution tracking
   - Test budget enforcement
   - Test multi-tenancy

3. **Cost Calculation Tests**
   - Verify cost calculations match expected values

## Open Questions

1. **Should we add caching for embeddings?**
   - Pros: Same text always produces same embedding, good for repeated queries
   - Cons: Storage overhead, cache invalidation complexity
   - **Recommendation**: Yes, opt-in with `cache_for` similar to agents

2. **Should we add a helper for pgvector integration?**
   - **Recommendation**: Document patterns but don't add hard dependency

3. **Should embeddings have their own execution model?**
   - **Recommendation**: No, use same Execution model with `execution_type` field

4. **Should we support async/batch jobs for large embedding tasks?**
   - **Recommendation**: Phase 2 feature, document ActiveJob pattern for now
