# frozen_string_literal: true

# BatchEmbedder - Optimized for bulk embedding operations
#
# Designed for processing large volumes of text with progress tracking.
# Uses larger batch sizes and provides callbacks for monitoring progress
# in background jobs or CLI tools.
#
# Use cases:
# - Initial database embedding migration
# - Nightly content reindexing
# - Bulk document processing
# - Data pipeline operations
#
# @example Bulk processing with progress
#   texts = Document.all.pluck(:content)  # 10,000 documents
#
#   result = Embedders::BatchEmbedder.call(texts: texts) do |batch_result, batch_idx|
#     progress = ((batch_idx + 1) * 100.0 / total_batches).round(1)
#     puts "Batch #{batch_idx + 1}: #{batch_result.count} embeddings (#{progress}%)"
#   end
#
#   puts "Total: #{result.count} embeddings in #{result.duration_ms}ms"
#
# @example In a background job
#   class EmbedDocumentsJob < ApplicationJob
#     def perform(document_ids)
#       documents = Document.where(id: document_ids)
#       texts = documents.pluck(:content)
#
#       result = Embedders::BatchEmbedder.call(texts: texts) do |batch_result, idx|
#         # Update job progress
#         update_progress((idx + 1) * 100 / expected_batches)
#       end
#
#       documents.each_with_index do |doc, idx|
#         doc.update!(embedding: result.vectors[idx])
#       end
#     end
#   end
#
# @example Cost tracking
#   result = Embedders::BatchEmbedder.call(texts: large_array, tenant: organization)
#   puts "Processed #{result.count} texts"
#   puts "Token usage: #{result.input_tokens}"
#   puts "Cost: $#{result.total_cost.round(4)}"
#
module Embedders
  class BatchEmbedder < ApplicationEmbedder
    description "Optimized for bulk embedding operations"
    version "1.0"

    # Use small model for cost efficiency on large batches
    model "text-embedding-3-small"

    # Moderate dimensions balance quality and storage
    dimensions 1024

    # Larger batch size for fewer API calls
    # Reduces overhead when processing many texts
    batch_size 100

    # Cache embeddings to avoid re-embedding on retries
    cache_for 3.days
  end
end
