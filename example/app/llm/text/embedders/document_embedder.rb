# frozen_string_literal: true

# DocumentEmbedder - Basic embedder for document indexing
#
# A simple, efficient embedder for general document embedding use cases.
# Uses reduced dimensions for storage efficiency and enables caching
# to minimize API costs for repeated embeddings.
#
# Use cases:
# - Document indexing for search systems
# - Content deduplication
# - Semantic clustering of documents
#
# @example Basic usage
#   result = Llm::Text::DocumentEmbedder.call(text: "Ruby is a dynamic language")
#   result.vector      # => [0.123, -0.456, ...] (512 dimensions)
#   result.dimensions  # => 512
#
# @example Batch indexing
#   documents = ["doc1 content", "doc2 content", "doc3 content"]
#   result = Llm::Text::DocumentEmbedder.call(texts: documents)
#   result.vectors.each_with_index do |vector, idx|
#     Document.find(idx).update!(embedding: vector)
#   end
#
# @example Similarity search
#   query_result = Llm::Text::DocumentEmbedder.call(text: "search query")
#   all_documents = Document.all.map(&:embedding)
#   matches = query_result.most_similar(all_documents, limit: 10)
#   # => [{index: 5, similarity: 0.92}, ...]
#
module Llm
  module Text
    class DocumentEmbedder < ApplicationEmbedder
      description "Embeds documents for indexing and search"
      version "1.0"

      # Use small model for cost efficiency
      model "text-embedding-3-small"

      # Reduced dimensions for storage efficiency
      # 512 dimensions still capture most semantic information
      dimensions 512

      # Cache embeddings for 1 week
      # Same text always produces the same embedding
      cache_for 1.week
    end
  end
end
