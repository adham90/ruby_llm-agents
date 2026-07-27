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
        class Cache < Base
          # Process caching
          #
          # @param context [Context] The execution context
          # @return [Context] The context (possibly from cache)
          def call(context)
            return @app.call(context) unless cache_enabled?

            cache_action = nil
            result = trace(context, action: "cache") do
              cache_key = generate_cache_key(context)

              # Skip cache read if skip_cache is true
              unless context.skip_cache
                # Try to read from cache
                if (cached = cache_read(cache_key))
                  context.output = mark_cached(cached, context)
                  replay_to_stream(context)
                  context.cached = true
                  context[:cache_key] = cache_key
                  cache_action = "hit"
                  debug("Cache hit for #{cache_key}", context)
                  emit_cache_notification("ruby_llm_agents.cache.hit", cache_key)
                  next context
                end
              end

              cache_action = "miss"
              emit_cache_notification("ruby_llm_agents.cache.miss", cache_key)

              # Execute the chain
              @app.call(context)

              # Cache successful results
              if context.success?
                cache_write(cache_key, context.output)
                debug("Cache write for #{cache_key}", context)
                emit_cache_notification("ruby_llm_agents.cache.write", cache_key)
              end

              context
            end

            # Update the last trace entry with the specific cache action
            if context.trace_enabled? && cache_action && context.trace.last
              context.trace.last[:action] = cache_action
            end

            result
          end

          private

          # Marks a cache-read result as cached and re-points its execution_id
          # at the row being written for THIS call.
          #
          # Without this, a cache hit returned the original result verbatim: it
          # reported no way to tell it was cached, carried the original's
          # execution_id (so it could not be correlated with the execution just
          # created), and replayed the original's cost — double-counting for
          # anyone summing #total_cost across calls.
          #
          # Results that predate #as_cache_hit (older cache entries mid-deploy)
          # are returned untouched rather than raising.
          #
          # @param cached [Object] The value read from the cache store
          # @param context [Context] The execution context
          # @return [Object] The marked result, or the original value
          def mark_cached(cached, context)
            return cached unless cached.respond_to?(:as_cache_hit)

            cached.as_cache_hit(
              execution_id: context.execution_id,
              cached_at: cached.try(:completed_at) || Time.current
            )
          rescue => e
            debug("Failed to mark result as cached: #{e.message}", context)
            cached
          end

          # Stand-in for a provider chunk when replaying a cached response.
          ReplayChunk = Struct.new(:content)

          # Feeds a cached response through the caller's stream block.
          #
          # A streaming agent with `cache_for` used to go silent on a hit: the
          # block never fired and the caller saw an empty stream, even though
          # the content was sitting in the return value.
          #
          # ponytail: replays as a single chunk, not token-by-token. The cache
          # stores the finished response, not the chunk boundaries — recreating
          # them would mean caching the stream itself.
          #
          # @param context [Context] The execution context
          def replay_to_stream(context)
            block = context.stream_block
            return unless block

            content = context.output.try(:content)
            return if content.nil?

            block.call(
              context.stream_events? ? StreamEvent.new(:chunk, {content: content}) : ReplayChunk.new(content)
            )
          rescue => e
            debug("Failed to replay cached response to stream: #{e.message}", context)
          end

          # Emits an AS::Notification for cache events
          #
          # @param event [String] The notification event name
          # @param cache_key [String] The cache key involved
          def emit_cache_notification(event, cache_key)
            ActiveSupport::Notifications.instrument(
              event,
              agent_type: @agent_class&.name,
              cache_key: cache_key
            )
          rescue => e
            debug("Cache notification failed: #{e.message}")
          end

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
          rescue => e
            debug("Failed to access cache_store config: #{e.message}")
            nil
          end

          # Returns the cache TTL
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def cache_ttl
            config(:cache_ttl)
          end

          # Execution options that change the response and must therefore change
          # the cache key. Anything omitted here is a silent stale-result bug:
          # attachments especially, since two calls with the same text prompt
          # and different images used to collide.
          KEYED_OPTIONS = %i[
            system_prompt assistant_prefill temperature schema messages thinking attachments
          ].freeze

          # Generates a cache key for the context
          #
          # Cache keys are content-based, including:
          # - Namespace prefix
          # - Agent type
          # - Agent class name
          # - Model
          # - Tenant (caches are never shared across tenants)
          # - SHA256 hash of input
          # - SHA256 hash of the response-affecting execution options
          #
          # This means caches automatically invalidate when inputs change.
          #
          # @param context [Context] The execution context
          # @return [String] The cache key
          def generate_cache_key(context)
            components = [
              "ruby_llm_agents",
              context.agent_type,
              context.agent_class&.name,
              context.model,
              context.tenant_id,
              hash_input(context.input),
              hash_options(context)
            ].compact

            components.join("/")
          end

          # Hashes the response-affecting execution options.
          #
          # Tools are reduced to their names: they arrive as classes or
          # instances whose default JSON encoding is neither stable nor
          # meaningful, and the name is what actually shapes the request.
          #
          # @param context [Context] The execution context
          # @return [String, nil] SHA256 hash, or nil when there are no options
          def hash_options(context)
            opts = context.options[:options]
            return nil unless opts.is_a?(Hash)

            keyed = opts.slice(*KEYED_OPTIONS)
            tools = Array(opts[:tools]).map { |t| t.respond_to?(:name) ? t.name : t.class.name }
            keyed[:tools] = tools if tools.any?
            return nil if keyed.empty?

            hash_input(keyed)
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
          rescue => e
            debug("Failed to serialize input for cache key: #{e.message}")
            input.to_s
          end

          # Reads from cache
          #
          # @param key [String] Cache key
          # @return [Object, nil] Cached value or nil
          def cache_read(key)
            cache_store.read(key)
          rescue => e
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
          rescue => e
            error("Cache write failed: #{e.message}")
          end
        end
      end
    end
  end
end
