# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result object for embedding operations
    #
    # Wraps embedding vectors with metadata about the operation including
    # token usage, cost, timing, and utility methods for similarity calculations.
    #
    # @example Single text embedding
    #   result = MyEmbedder.call(text: "Hello world")
    #   result.vector        # => [0.123, -0.456, ...]
    #   result.dimensions    # => 1536
    #   result.input_tokens  # => 2
    #
    # @example Batch embedding
    #   result = MyEmbedder.call(texts: ["Hello", "World"])
    #   result.vectors       # => [[...], [...]]
    #   result.count         # => 2
    #
    # @example Similarity comparison
    #   result1 = MyEmbedder.call(text: "Ruby programming")
    #   result2 = MyEmbedder.call(text: "Python programming")
    #   result1.similarity(result2)  # => 0.85
    #
    # @api public
    class EmbeddingResult
      # @!attribute [r] vectors
      #   @return [Array<Array<Float>>] The embedding vectors
      attr_reader :vectors

      # @!attribute [r] model_id
      #   @return [String, nil] The embedding model used
      attr_reader :model_id

      # @!attribute [r] dimensions
      #   @return [Integer, nil] The dimensionality of the vectors
      attr_reader :dimensions

      # @!attribute [r] input_tokens
      #   @return [Integer, nil] Number of input tokens consumed
      attr_reader :input_tokens

      # @!attribute [r] total_cost
      #   @return [Float, nil] Total cost in USD
      attr_reader :total_cost

      # @!attribute [r] duration_ms
      #   @return [Integer, nil] Execution duration in milliseconds
      attr_reader :duration_ms

      # @!attribute [r] count
      #   @return [Integer] Number of texts embedded
      attr_reader :count

      # @!attribute [r] started_at
      #   @return [Time, nil] When execution started
      attr_reader :started_at

      # @!attribute [r] completed_at
      #   @return [Time, nil] When execution completed
      attr_reader :completed_at

      # @!attribute [r] tenant_id
      #   @return [String, nil] Tenant identifier if multi-tenancy enabled
      attr_reader :tenant_id

      # @!attribute [r] error_class
      #   @return [String, nil] Exception class name if failed
      attr_reader :error_class

      # @!attribute [r] error_message
      #   @return [String, nil] Exception message if failed
      attr_reader :error_message

      # Creates a new EmbeddingResult instance
      #
      # @param attributes [Hash] Result attributes
      # @option attributes [Array<Array<Float>>] :vectors The embedding vectors
      # @option attributes [String] :model_id The model used
      # @option attributes [Integer] :dimensions Vector dimensionality
      # @option attributes [Integer] :input_tokens Tokens consumed
      # @option attributes [Float] :total_cost Cost in USD
      # @option attributes [Integer] :duration_ms Duration in milliseconds
      # @option attributes [Integer] :count Number of texts
      # @option attributes [Time] :started_at Start time
      # @option attributes [Time] :completed_at Completion time
      # @option attributes [String] :tenant_id Tenant identifier
      # @option attributes [String] :error_class Error class name
      # @option attributes [String] :error_message Error message
      def initialize(attributes = {})
        @vectors = attributes[:vectors] || []
        @model_id = attributes[:model_id]
        @dimensions = attributes[:dimensions]
        @input_tokens = attributes[:input_tokens]
        @total_cost = attributes[:total_cost]
        @duration_ms = attributes[:duration_ms]
        @count = attributes[:count] || @vectors.size
        @started_at = attributes[:started_at]
        @completed_at = attributes[:completed_at]
        @tenant_id = attributes[:tenant_id]
        @error_class = attributes[:error_class]
        @error_message = attributes[:error_message]
      end

      # Returns whether this result contains a single embedding
      #
      # @return [Boolean] true if count is 1
      def single?
        count == 1
      end

      # Returns whether this result contains multiple embeddings
      #
      # @return [Boolean] true if count > 1
      def batch?
        count > 1
      end

      # Returns the first (or only) embedding vector
      #
      # Convenience method for single-text embeddings.
      #
      # @return [Array<Float>, nil] The embedding vector or nil if batch
      def vector
        vectors.first
      end

      # Returns whether the execution succeeded
      #
      # @return [Boolean] true if no error occurred
      def success?
        error_class.nil?
      end

      # Returns whether the execution failed
      #
      # @return [Boolean] true if an error occurred
      def error?
        !success?
      end

      # Calculates cosine similarity between this embedding and another
      #
      # @param other [EmbeddingResult, Array<Float>] Another embedding or vector
      # @param index [Integer] Index of the vector to compare (for batch results)
      # @return [Float] Cosine similarity score (-1.0 to 1.0)
      # @example Compare two results
      #   result1.similarity(result2)  # => 0.85
      # @example Compare with raw vector
      #   result.similarity([0.1, 0.2, 0.3])
      # @example Compare specific vector from batch
      #   batch_result.similarity(other, index: 2)
      def similarity(other, index: 0)
        v1 = vectors[index]
        return nil if v1.nil?

        v2 = case other
             when EmbeddingResult
               other.vector
             when Array
               other
             else
               raise ArgumentError, "other must be EmbeddingResult or Array, got #{other.class}"
             end

        return nil if v2.nil?

        cosine_similarity(v1, v2)
      end

      # Finds the most similar vectors from a collection
      #
      # @param others [Array<EmbeddingResult, Array<Float>>] Collection to search
      # @param limit [Integer] Maximum results to return
      # @param index [Integer] Index of the source vector (for batch results)
      # @return [Array<Hash>] Sorted results with :index and :similarity keys
      # @example Find top 5 similar
      #   result.most_similar(document_embeddings, limit: 5)
      def most_similar(others, limit: 10, index: 0)
        v1 = vectors[index]
        return [] if v1.nil?

        similarities = others.each_with_index.map do |other, idx|
          v2 = case other
               when EmbeddingResult
                 other.vector
               when Array
                 other
               else
                 next nil
               end

          next nil if v2.nil?

          { index: idx, similarity: cosine_similarity(v1, v2) }
        end.compact

        similarities.sort_by { |s| -s[:similarity] }.first(limit)
      end

      # Converts the result to a hash
      #
      # @return [Hash] All result data as a hash
      def to_h
        {
          vectors: vectors,
          model_id: model_id,
          dimensions: dimensions,
          input_tokens: input_tokens,
          total_cost: total_cost,
          duration_ms: duration_ms,
          count: count,
          started_at: started_at,
          completed_at: completed_at,
          tenant_id: tenant_id,
          error_class: error_class,
          error_message: error_message
        }
      end

      private

      # Calculates cosine similarity between two vectors
      #
      # @param a [Array<Float>] First vector
      # @param b [Array<Float>] Second vector
      # @return [Float] Cosine similarity (-1.0 to 1.0)
      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty?
        return 0.0 if a.size != b.size

        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x * x })
        magnitude_b = Math.sqrt(b.sum { |x| x * x })

        return 0.0 if magnitude_a.zero? || magnitude_b.zero?

        dot_product / (magnitude_a * magnitude_b)
      end
    end
  end
end
