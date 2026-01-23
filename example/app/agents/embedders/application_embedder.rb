# frozen_string_literal: true

# ApplicationEmbedder - Base class for all embedders in this application
#
# All embedders inherit from this class. Configure shared settings here
# that apply to all embedders, or override them per-embedder as needed.
#
# ============================================================================
# EMBEDDER DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "text-embedding-3-small"  # Embedding model identifier
#   dimensions 512                   # Vector dimensions (some models support reduction)
#   batch_size 50                    # Max texts per API call
#   version "1.0"                    # Embedder version (affects cache keys)
#   description "..."                # Human-readable embedder description
#
# CACHING:
# --------
#   cache_for 1.week                 # Enable embedding caching with TTL
#   # Same text always produces the same embedding, so caching is very effective
#
# TEXT PREPROCESSING:
# -------------------
#   Override the preprocess(text) method to transform text before embedding:
#
#   def preprocess(text)
#     text.strip.downcase.gsub(/\s+/, ' ')  # Normalize whitespace
#   end
#
# ============================================================================
# AVAILABLE MODELS
# ============================================================================
#
# OpenAI Models:
#   - text-embedding-3-small   # Cost-effective, 1536 dimensions (reducible)
#   - text-embedding-3-large   # Highest quality, 3072 dimensions (reducible)
#   - text-embedding-ada-002   # Legacy model, 1536 dimensions (fixed)
#
# Dimension Reduction:
#   text-embedding-3-* models support reducing dimensions:
#   - text-embedding-3-small: 512, 1024, 1536 (default)
#   - text-embedding-3-large: 256, 512, 1024, 1536, 3072 (default)
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Single text embedding
#   result = Embedders::MyEmbedder.call(text: "Hello world")
#   result.vector        # => [0.123, -0.456, ...]
#   result.dimensions    # => 1536
#   result.input_tokens  # => 2
#
#   # Batch embedding
#   result = Embedders::MyEmbedder.call(texts: ["Hello", "World"])
#   result.vectors       # => [[...], [...]]
#   result.count         # => 2
#
#   # With progress callback (for large batches)
#   Embedders::MyEmbedder.call(texts: large_array) do |batch_result, idx|
#     puts "Processed batch #{idx}: #{batch_result.count} embeddings"
#   end
#
#   # Similarity comparison
#   result1 = Embedders::MyEmbedder.call(text: "Ruby programming")
#   result2 = Embedders::MyEmbedder.call(text: "Python programming")
#   result1.similarity(result2)  # => 0.85
#
#   # Find most similar
#   query = Embedders::MyEmbedder.call(text: "search query")
#   documents = Embedders::MyEmbedder.call(texts: document_texts)
#   matches = query.most_similar(documents.vectors, limit: 5)
#   # => [{index: 3, similarity: 0.92}, {index: 7, similarity: 0.87}, ...]
#
#   # With tenant for budget tracking
#   Embedders::MyEmbedder.call(text: "hello", tenant: organization)
#
# ============================================================================
# OTHER EMBEDDER EXAMPLES
# ============================================================================
#
# See these files for specialized embedder implementations:
#   - document_embedder.rb     - Basic embedder with caching
#   - search_embedder.rb       - High-quality embeddings for search
#   - batch_embedder.rb        - Bulk processing with progress callbacks
#   - clean_text_embedder.rb   - Text preprocessing before embedding
#   - code_embedder.rb         - Domain-specific for source code
#
module Embedders
  class ApplicationEmbedder < RubyLLM::Agents::Embedder
    # ============================================
    # Shared Model Configuration
    # ============================================
    # These settings are inherited by all embedders

    # model "text-embedding-3-small"   # Default model for all embedders
    # dimensions 1536                   # Default dimensions

    # ============================================
    # Shared Caching
    # ============================================

    # cache_for 1.day  # Enable caching for all embedders

    # ============================================
    # Shared Helper Methods
    # ============================================
    # Define methods here that can be used by all embedders

    # Example: Common preprocessing
    # def preprocess(text)
    #   text.to_s.strip
    # end
  end
end
