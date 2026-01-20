# frozen_string_literal: true

module RubyLLM
  module Agents
    # Shared cache utilities for RubyLLM::Agents
    #
    # Provides consistent cache key generation and store access across
    # BudgetTracker, CircuitBreaker, and Base caching modules.
    #
    # @example Using in a class method context
    #   extend CacheHelper
    #   cache_store.read(cache_key("budget", "global", "2024-01"))
    #
    # @example Using in an instance method context
    #   include CacheHelper
    #   cache_store.write(cache_key("agent", agent_type), data, expires_in: 1.hour)
    #
    # @api private
    module CacheHelper
      # Cache key namespace prefix
      NAMESPACE = "ruby_llm_agents"

      # Returns the configured cache store
      #
      # @return [ActiveSupport::Cache::Store]
      def cache_store
        RubyLLM::Agents.configuration.cache_store
      end

      # Generates a namespaced cache key from the given parts
      #
      # @param parts [Array<String, Symbol>] Key components to join
      # @return [String] Namespaced cache key
      # @example
      #   cache_key("budget", "global", "2024-01")
      #   # => "ruby_llm_agents:budget:global:2024-01"
      def cache_key(*parts)
        ([NAMESPACE] + parts.map(&:to_s)).join(":")
      end

      # Reads a value from the cache
      #
      # @param key [String] The cache key
      # @return [Object, nil] The cached value or nil
      def cache_read(key)
        cache_store.read(key)
      end

      # Writes a value to the cache
      #
      # @param key [String] The cache key
      # @param value [Object] The value to cache
      # @param options [Hash] Options passed to cache store (e.g., expires_in:)
      # @return [Boolean] Whether the write succeeded
      def cache_write(key, value, **options)
        cache_store.write(key, value, **options)
      end

      # Checks if a key exists in the cache
      #
      # @param key [String] The cache key
      # @return [Boolean] True if the key exists
      def cache_exist?(key)
        cache_store.exist?(key)
      end

      # Deletes a key from the cache
      #
      # @param key [String] The cache key
      # @return [Boolean] Whether the delete succeeded
      def cache_delete(key)
        cache_store.delete(key)
      end

      # Increments a numeric value in the cache
      #
      # Falls back to read-modify-write if the cache store doesn't support increment.
      #
      # @param key [String] The cache key
      # @param amount [Numeric] The amount to increment by (default: 1)
      # @param expires_in [ActiveSupport::Duration, nil] Optional TTL for the key
      # @return [Numeric] The new value
      def cache_increment(key, amount = 1, expires_in: nil)
        if cache_store.respond_to?(:increment)
          # Ensure key exists with TTL
          cache_store.write(key, 0, expires_in: expires_in, unless_exist: true) if expires_in
          cache_store.increment(key, amount)
        else
          # Fallback for cache stores without atomic increment
          current = (cache_store.read(key) || 0).to_f
          new_value = current + amount
          cache_store.write(key, new_value, expires_in: expires_in)
          new_value
        end
      end
    end
  end
end
