# frozen_string_literal: true

require_relative "../results/embedding_result"
require_relative "embedder/dsl"
require_relative "embedder/execution"

module RubyLLM
  module Agents
    # Base class for creating embedding generators
    #
    # Embedder provides a DSL for configuring embedding operations with
    # built-in execution tracking, budget controls, and multi-tenancy support.
    #
    # @example Basic usage
    #   class DocumentEmbedder < RubyLLM::Agents::Embedder
    #     model 'text-embedding-3-small'
    #     dimensions 512
    #   end
    #
    #   result = DocumentEmbedder.call(text: "Hello world")
    #   result.vector  # => [0.123, -0.456, ...]
    #
    # @example Batch processing
    #   result = DocumentEmbedder.call(texts: ["Hello", "World"])
    #   result.vectors  # => [[...], [...]]
    #
    # @example With preprocessing
    #   class CleanEmbedder < RubyLLM::Agents::Embedder
    #     model 'text-embedding-3-small'
    #
    #     def preprocess(text)
    #       text.strip.downcase.gsub(/\s+/, ' ')
    #     end
    #   end
    #
    # @api public
    class Embedder
      extend DSL
      include Execution

      # @!attribute [r] options
      #   @return [Hash] The options passed to the embedder
      attr_reader :options

      # Creates a new Embedder instance
      #
      # @param options [Hash] Configuration options
      # @option options [String] :model Override the class-level model
      # @option options [Integer] :dimensions Override the class-level dimensions
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(**options)
        @options = options
        @tenant_id = nil
        @tenant_object = nil
        @tenant_config = nil
      end

      class << self
        # Executes the embedder with the given parameters
        #
        # @param text [String, nil] Single text to embed
        # @param texts [Array<String>, nil] Multiple texts to embed
        # @param options [Hash] Additional options
        # @yield [batch_result, index] Called after each batch completes
        # @yieldparam batch_result [EmbeddingResult] Result for the batch
        # @yieldparam index [Integer] Batch index (0-based)
        # @return [EmbeddingResult] The embedding result
        # @raise [ArgumentError] If both text: and texts: are provided
        # @example Single text
        #   DocumentEmbedder.call(text: "Hello world")
        # @example Batch
        #   DocumentEmbedder.call(texts: ["Hello", "World"])
        # @example With progress callback
        #   DocumentEmbedder.call(texts: large_array) do |batch, idx|
        #     puts "Processed batch #{idx}"
        #   end
        def call(text: nil, texts: nil, **options, &block)
          new(**options).call(text: text, texts: texts, &block)
        end
      end
    end
  end
end
