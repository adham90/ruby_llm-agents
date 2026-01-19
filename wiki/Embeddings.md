# Embeddings

Transform text into numerical vectors for semantic search, recommendations, and content similarity.

## Overview

The `Embedder` base class provides a DSL for creating embedding generators with:
- Built-in execution tracking and cost monitoring
- Budget controls (embeddings count toward limits)
- Multi-tenancy support
- Batch processing with progress callbacks
- Caching for repeated queries

## Quick Start

### Generate an Embedder

```bash
rails generate ruby_llm_agents:embedder Document
```

This creates `app/embedders/document_embedder.rb`:

```ruby
class DocumentEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"
end
```

### Basic Usage

```ruby
# Single text
result = DocumentEmbedder.call(text: "Ruby is a great language")
result.vector        # [0.123, -0.456, 0.789, ...]
result.dimensions    # 1536
result.input_tokens  # 6
result.total_cost    # 0.00001

# Multiple texts (batch)
result = DocumentEmbedder.call(texts: [
  "First document",
  "Second document",
  "Third document"
])
result.vectors  # [[...], [...], [...]]
result.count    # 3
```

## Configuration DSL

### Model Selection

```ruby
class DocumentEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"  # OpenAI small
  # or
  model "text-embedding-3-large"  # OpenAI large
  # or
  model "text-embedding-004"      # Google
end
```

### Dimension Reduction

Some models support reducing dimensions for more efficient storage:

```ruby
class CompactEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"
  dimensions 512  # Reduce from 1536 to 512
end
```

### Batch Size

Control how many texts are sent per API call:

```ruby
class BulkEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"
  batch_size 50  # Default is 100
end
```

### Caching

Same text always produces the same embedding, so caching is very effective:

```ruby
class CachedEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"
  cache_for 1.week
end
```

### Custom Preprocessing

Override the `preprocess` method to normalize text before embedding:

```ruby
class CleanEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"

  def preprocess(text)
    text
      .strip
      .downcase
      .gsub(/\s+/, ' ')
      .truncate(8000)  # Model limit
  end
end
```

## EmbeddingResult

The result object provides access to vectors and metadata:

```ruby
result = MyEmbedder.call(text: "Hello world")

# Vectors
result.vector           # Single vector (for single text)
result.vectors          # Array of vectors (for batch)
result.dimensions       # Vector size

# Metadata
result.model_id         # Model used
result.input_tokens     # Tokens consumed
result.total_cost       # Cost in USD
result.duration_ms      # Execution time
result.count            # Number of texts embedded

# Timing
result.started_at       # Start time
result.completed_at     # End time

# Status
result.success?         # true if no error
result.error?           # true if failed
result.single?          # true if single text
result.batch?           # true if batch
```

### Similarity Calculation

Built-in cosine similarity for comparing embeddings:

```ruby
# Compare two results
result1 = MyEmbedder.call(text: "Ruby programming")
result2 = MyEmbedder.call(text: "Python programming")

similarity = result1.similarity(result2)
# => 0.85 (high similarity)

# Compare with raw vector
result.similarity([0.1, 0.2, 0.3])

# For batch results, specify index
batch.similarity(other, index: 2)
```

### Finding Similar Items

```ruby
query = MyEmbedder.call(text: "How to deploy Rails apps?")
document_vectors = documents.map(&:embedding)

similar = query.most_similar(document_vectors, limit: 5)
# => [{ index: 42, similarity: 0.95 }, ...]
```

## Batch Processing with Progress

For large datasets, use the block form for progress tracking:

```ruby
texts = Article.pluck(:content)  # 10,000 documents

result = BulkEmbedder.call(texts: texts) do |batch_result, index|
  puts "Processed batch #{index}: #{batch_result.count} texts"
  # Update progress bar, etc.
end

puts "Total cost: $#{result.total_cost}"
puts "Total tokens: #{result.input_tokens}"
```

## Runtime Overrides

Override class settings at call time:

```ruby
# Override model
result = DocumentEmbedder.call(
  text: "Hello",
  model: "text-embedding-3-large"
)

# Override dimensions
result = DocumentEmbedder.call(
  text: "Hello",
  dimensions: 256
)

# With tenant for multi-tenancy
result = DocumentEmbedder.call(
  text: "Hello",
  tenant: current_organization
)
```

## Semantic Search Example

```ruby
class SearchEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"
  dimensions 512
  cache_for 1.day
end

# Index documents (run once)
Document.find_each do |doc|
  result = SearchEmbedder.call(text: doc.content)
  doc.update!(embedding: result.vector)
end

# Search
def search(query)
  query_result = SearchEmbedder.call(text: query)

  # Using pgvector
  Document
    .nearest_neighbors(:embedding, query_result.vector, distance: :cosine)
    .limit(10)
end
```

## RAG Pipeline Example

```ruby
class RAGEmbedder < ApplicationEmbedder
  model "text-embedding-3-small"

  def preprocess(text)
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

      If the answer isn't in the context, say "I don't know."
    PROMPT
  end

  private

  def retrieve_context(question)
    embedding = RAGEmbedder.call(text: question)

    chunks = KnowledgeChunk
      .nearest_neighbors(:embedding, embedding.vector, distance: :cosine)
      .limit(5)

    chunks.map(&:content).join("\n\n")
  end
end
```

## Execution Tracking

Embedding executions are tracked in the same `ruby_llm_agents_executions` table:

```ruby
# View embedding executions
RubyLLM::Agents::Execution
  .where(execution_type: 'embedding')
  .sum(:total_cost)

# Per-embedder stats
RubyLLM::Agents::Execution
  .where(agent_type: 'DocumentEmbedder')
  .group(:model_id)
  .sum(:input_tokens)
```

## Budget Controls

Embedding costs count toward tenant and global budgets:

```ruby
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 25.0,      # Includes embeddings
    global_monthly: 500.0,
    enforcement: :hard
  }
end
```

## Global Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Default embedding model
  config.default_embedding_model = "text-embedding-3-small"

  # Default dimensions (nil = model default)
  config.default_embedding_dimensions = nil

  # Default batch size
  config.default_embedding_batch_size = 100

  # Enable/disable tracking
  config.track_embeddings = true
end
```

## Supported Models

| Provider | Model | Default Dimensions | Notes |
|----------|-------|-------------------|-------|
| OpenAI | `text-embedding-3-small` | 1536 | Default, cost-effective |
| OpenAI | `text-embedding-3-large` | 3072 | Higher quality |
| OpenAI | `text-embedding-ada-002` | 1536 | Legacy |
| Google | `text-embedding-004` | 768 | Gemini embeddings |
| Voyage | `voyage-3` | 1024 | Specialized |
| Cohere | `embed-english-v3.0` | 1024 | Multilingual available |

## Cost Considerations

Embeddings are cheap but can add up at scale:

| Model | Price per 1M tokens |
|-------|---------------------|
| text-embedding-3-small | $0.02 |
| text-embedding-3-large | $0.13 |
| text-embedding-ada-002 | $0.10 |

**Tips:**
- Use caching for repeated queries
- Reduce dimensions when possible (512 is often sufficient)
- Batch multiple texts in single calls
- Monitor costs in the dashboard
