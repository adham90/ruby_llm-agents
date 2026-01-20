# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Caches results to avoid redundant API calls.
        #
        # This middleware provides caching for agent executions:
        # - Checks cache before execution
        # - Stores successful results in cache
        # - Respects TTL configuration from agent DSL
        #
        # Caching is skipped if:
        # - Caching is not enabled on the agent class (no cache_for DSL)
        # - The cache store is not configured
        #
        # @example Enable caching on an agent
        #   class MyEmbedder < RubyLLM::Agents::Embedder
        #     model "text-embedding-3-small"
        #     cache_for 1.hour
        #   end
        #
        # @example Cache versioning
        #   class MyEmbedder < RubyLLM::Agents::Embedder
        #     model "text-embedding-3-small"
        #     version "2.0"  # Change to invalidate cache
        #     cache_for 1.hour
        #   end
        #
        class Cache < Base
          # Process caching
          #
          # @param context [Context] The execution context
          # @return [Context] The context (possibly from cache)
          def call(context)
            return @app.call(context) unless cache_enabled?

            cache_key = generate_cache_key(context)

            # Try to read from cache
            if (cached = cache_read(cache_key))
              context.output = cached
              context.cached = true
              debug("Cache hit for #{cache_key}")
              return context
            end

            # Execute the chain
            @app.call(context)

            # Cache successful results
            if context.success?
              cache_write(cache_key, context.output)
              debug("Cache write for #{cache_key}")
            end

            context
          end

          private

          # Returns whether caching is enabled for this agent
          #
          # @return [Boolean]
          def cache_enabled?
            enabled?(:cache_enabled?) && cache_store.present?
          end

          # Returns the cache store
          #
          # @return [ActiveSupport::Cache::Store, nil]
          def cache_store
            global_config.cache_store
          rescue StandardError
            nil
          end

          # Returns the cache TTL
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def cache_ttl
            config(:cache_ttl)
          end

          # Generates a cache key for the context
          #
          # The cache key includes:
          # - Namespace prefix
          # - Agent type
          # - Agent class name
          # - Version (for cache invalidation)
          # - Model
          # - SHA256 hash of input
          #
          # @param context [Context] The execution context
          # @return [String] The cache key
          def generate_cache_key(context)
            components = [
              "ruby_llm_agents",
              context.agent_type,
              context.agent_class&.name,
              config(:version, "1.0"),
              context.model,
              hash_input(context.input)
            ].compact

            components.join("/")
          end

          # Hashes the input for cache key
          #
          # @param input [Object] The input to hash
          # @return [String] SHA256 hash
          def hash_input(input)
            Digest::SHA256.hexdigest(serialize_input(input))
          end

          # Serializes input for hashing
          #
          # @param input [Object] The input to serialize
          # @return [String] Serialized representation
          def serialize_input(input)
            case input
            when String
              input
            when Array
              input.map { |i| serialize_input(i) }.join("|")
            when Hash
              input.sort.map { |k, v| "#{k}:#{serialize_input(v)}" }.join("|")
            else
              input.to_json
            end
          rescue StandardError
            input.to_s
          end

          # Reads from cache
          #
          # @param key [String] Cache key
          # @return [Object, nil] Cached value or nil
          def cache_read(key)
            cache_store.read(key)
          rescue StandardError => e
            error("Cache read failed: #{e.message}")
            nil
          end

          # Writes to cache
          #
          # @param key [String] Cache key
          # @param value [Object] Value to cache
          def cache_write(key, value)
            options = {}
            options[:expires_in] = cache_ttl if cache_ttl

            cache_store.write(key, value, **options)
          rescue StandardError => e
            error("Cache write failed: #{e.message}")
          end
        end
      end
    end
  end
end
