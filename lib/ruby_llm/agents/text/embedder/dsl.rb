# frozen_string_literal: true

module RubyLLM
  module Agents
    class Embedder
      # Class-level DSL for configuring embedders
      #
      # Provides methods for setting model, dimensions, batch size,
      # and version for embedding operations.
      module DSL
        # @!group Configuration DSL

        # Sets or returns the embedding model for this embedder class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "text-embedding-3-small"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_embedding_model)
        end

        # Sets or returns the vector dimensions for this embedder
        #
        # Some models (like OpenAI text-embedding-3) support reducing
        # dimensions for more efficient storage.
        #
        # @param value [Integer, nil] The dimensions to set
        # @return [Integer, nil] The current dimensions setting
        # @example
        #   dimensions 512
        def dimensions(value = nil)
          @dimensions = value if value
          @dimensions || inherited_or_default(:dimensions, RubyLLM::Agents.configuration.default_embedding_dimensions)
        end

        # Sets or returns the batch size for this embedder
        #
        # When embedding multiple texts, they are split into batches
        # of this size for API calls.
        #
        # @param value [Integer, nil] Maximum texts per API call
        # @return [Integer] The current batch size
        # @example
        #   batch_size 50
        def batch_size(value = nil)
          @batch_size = value if value
          @batch_size || inherited_or_default(:batch_size, RubyLLM::Agents.configuration.default_embedding_batch_size)
        end

        # Sets or returns the version string for cache invalidation
        #
        # @param value [String, nil] Version string
        # @return [String] The current version
        # @example
        #   version "2.0"
        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, "1.0")
        end

        # Sets or returns the description for this embedder class
        #
        # @param value [String, nil] The description text
        # @return [String, nil] The current description
        # @example
        #   description "Embeds documents for semantic search"
        def description(value = nil)
          @description = value if value
          @description || inherited_or_default(:description, nil)
        end

        # @!endgroup

        # @!group Caching DSL

        # Enables caching for this embedder with explicit TTL
        #
        # Since the same text always produces the same embedding,
        # caching can significantly reduce API costs.
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache_for 1.day
        def cache_for(ttl)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this embedder
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          @cache_enabled || false
        end

        # Returns the cache TTL for this embedder
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || 1.hour
        end

        # @!endgroup

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end
      end
    end
  end
end
