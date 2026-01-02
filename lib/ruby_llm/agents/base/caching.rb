# frozen_string_literal: true

require_relative "../cache_helper"

module RubyLLM
  module Agents
    class Base
      # Cache management for agent responses
      #
      # Handles cache key generation and store access for
      # caching agent execution results.
      module Caching
        include CacheHelper

        # Generates the full cache key for this agent invocation
        #
        # @return [String] Cache key in format "ruby_llm_agent/ClassName/version/hash"
        def agent_cache_key
          ["ruby_llm_agent", self.class.name, self.class.version, cache_key_hash].join("/")
        end

        # Generates a hash of the cache key data
        #
        # @return [String] SHA256 hex digest of the cache key data
        def cache_key_hash
          Digest::SHA256.hexdigest(cache_key_data.to_json)
        end

        # Returns data to include in cache key generation
        #
        # Override to customize what parameters affect cache invalidation.
        #
        # @return [Hash] Data to hash for cache key
        def cache_key_data
          @options.except(:skip_cache, :dry_run, :with)
        end
      end
    end
  end
end
