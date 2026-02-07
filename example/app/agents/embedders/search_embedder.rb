# frozen_string_literal: true

# SearchEmbedder - High-quality embeddings for semantic search
#
# Uses the larger embedding model with maximum dimensions for
# highest-quality similarity matching. Ideal for search systems
# where accuracy is more important than storage or speed.
#
# Use cases:
# - Semantic search engines
# - Question-answering systems
# - Document retrieval for RAG
# - High-stakes similarity matching
#
# @example Search query embedding
#   query_result = Embedders::SearchEmbedder.call(text: "How do I configure Rails routes?")
#   # Use query_result.vector to find similar documents
#
# @example Building a search index
#   documents = Article.all.pluck(:content)
#   result = Embedders::SearchEmbedder.call(texts: documents)
#   result.vectors.each_with_index do |vector, idx|
#     Article.all[idx].update!(search_embedding: vector)
#   end
#
# @example Finding relevant documents
#   query = Embedders::SearchEmbedder.call(text: user_question)
#   doc_embeddings = Article.all.pluck(:search_embedding)
#   matches = query.most_similar(doc_embeddings, limit: 5)
#   relevant_articles = matches.map { |m| Article.all[m[:index]] }
#
module Embedders
  class SearchEmbedder < ApplicationEmbedder
    description 'High-quality embeddings for semantic search'

    # Use large model for highest quality
    model 'text-embedding-3-large'

    # Maximum dimensions for best accuracy
    # text-embedding-3-large supports up to 3072 dimensions
    dimensions 3072

    # Cache embeddings for longer since quality matters most
    cache_for 2.weeks
  end
end
