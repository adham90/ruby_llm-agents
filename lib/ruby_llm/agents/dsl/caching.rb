# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Caching DSL for agent response caching.
      #
      # This module provides configuration methods for caching features
      # that can be mixed into any agent class.
      #
      # @example Basic usage
      #   class MyAgent < RubyLLM::Agents::BaseAgent
      #     extend DSL::Caching
      #
      #     cache_for 1.hour
      #   end
      #
      # @example With conditional caching
      #   class MyAgent < RubyLLM::Agents::BaseAgent
      #     extend DSL::Caching
      #
      #     cache_for 30.minutes
      #     cache_key_includes :user_id, :query
      #   end
      #
      module Caching
        # Default cache TTL when none specified
        DEFAULT_CACHE_TTL = 1.hour

        # @!group Caching DSL

        # Enables caching for this agent with explicit TTL
        #
        # This is the preferred method for enabling caching.
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache_for 1.hour
        #   cache_for 30.minutes
        def cache_for(ttl)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this agent
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          return @cache_enabled if defined?(@cache_enabled)

          inherited_cache_enabled
        end

        # Returns the cache TTL for this agent
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || inherited_cache_ttl || DEFAULT_CACHE_TTL
        end

        # Specifies which parameters should be included in the cache key
        #
        # By default, all options except :skip_cache and :dry_run are included.
        # Use this to explicitly define which parameters affect caching.
        #
        # @param keys [Array<Symbol>] Parameter keys to include in cache key
        # @return [Array<Symbol>, nil] The current cache key includes
        # @example
        #   cache_key_includes :user_id, :query, :context
        def cache_key_includes(*keys)
          @cache_key_includes = keys.flatten if keys.any?
          @cache_key_includes || inherited_cache_key_includes
        end

        # Specifies which parameters should be excluded from the cache key
        #
        # @param keys [Array<Symbol>] Parameter keys to exclude from cache key
        # @return [Array<Symbol>] The current cache key excludes
        # @example
        #   cache_key_excludes :timestamp, :request_id
        def cache_key_excludes(*keys)
          @cache_key_excludes = keys.flatten if keys.any?
          @cache_key_excludes || inherited_cache_key_excludes || default_cache_key_excludes
        end

        # Returns the complete caching configuration hash
        #
        # Used by the Cache middleware to get all settings.
        #
        # @return [Hash, nil] The caching configuration
        def caching_config
          return nil unless cache_enabled?

          {
            enabled: true,
            ttl: cache_ttl,
            key_includes: cache_key_includes,
            key_excludes: cache_key_excludes
          }.compact
        end

        # @!endgroup

        private

        def inherited_cache_enabled
          return false unless superclass.respond_to?(:cache_enabled?)

          superclass.cache_enabled?
        end

        def inherited_cache_ttl
          return nil unless superclass.respond_to?(:cache_ttl)

          superclass.cache_ttl
        end

        def inherited_cache_key_includes
          return nil unless superclass.respond_to?(:cache_key_includes)

          superclass.cache_key_includes
        end

        def inherited_cache_key_excludes
          return nil unless superclass.respond_to?(:cache_key_excludes)

          superclass.cache_key_excludes
        end

        def default_cache_key_excludes
          %i[skip_cache dry_run with]
        end
      end
    end
  end
end
