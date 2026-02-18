# frozen_string_literal: true

require "net/http"
require "json"

module RubyLLM
  module Agents
    module Pricing
      # Centralized HTTP fetch + two-layer cache for all pricing sources.
      #
      # Replaces the duplicated fetch_from_url / litellm_data / cache_expired?
      # code previously copy-pasted across TranscriptionPricing, SpeechPricing,
      # and ImageGenerator::Pricing.
      #
      # Two-layer cache:
      #   Layer 1: In-memory (per-process, instant)
      #   Layer 2: Rails.cache (cross-process, survives restarts)
      #
      # Thread-safety: All cache writes are protected by a Mutex.
      #
      # @example Fetch LiteLLM data
      #   DataStore.litellm_data # => Hash of all models
      #
      # @example Fetch Portkey data for a specific model
      #   DataStore.portkey_data("openai", "gpt-4o") # => Hash
      #
      # @example Refresh all caches
      #   DataStore.refresh!
      #
      module DataStore
        extend self

        DEFAULT_CACHE_TTL = 24 * 60 * 60 # 24 hours

        LITELLM_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        OPENROUTER_URL = "https://openrouter.ai/api/v1/models"
        HELICONE_URL = "https://www.helicone.ai/api/llm-costs"
        PORTKEY_BASE_URL = "https://api.portkey.ai/model-configs/pricing"
        LLMPRICING_BASE_URL = "https://llmpricing.ai/api"

        # ============================================================
        # Bulk fetchers (one HTTP call gets all models)
        # ============================================================

        # @return [Hash] model_id => { pricing fields }
        def litellm_data
          fetch_bulk(:litellm, litellm_url) { |body| JSON.parse(body) }
        end

        # @return [Array<Hash>] Array of model entries with pricing
        def openrouter_data
          return nil unless source_enabled?(:openrouter)

          fetch_bulk(:openrouter, openrouter_url) do |body|
            parsed = JSON.parse(body)
            parsed.is_a?(Hash) ? (parsed["data"] || []) : parsed
          end
        end

        # @return [Array<Hash>] Array of cost entries
        def helicone_data
          return nil unless source_enabled?(:helicone)

          fetch_bulk(:helicone, helicone_url) do |body|
            parsed = JSON.parse(body)
            parsed.is_a?(Array) ? parsed : (parsed["data"] || parsed["costs"] || [])
          end
        end

        # ============================================================
        # Per-model fetchers (one HTTP call per model)
        # ============================================================

        # @param provider [String] e.g., "openai"
        # @param model [String] e.g., "gpt-4o"
        # @return [Hash, nil] Pricing data for this model
        def portkey_data(provider, model)
          return nil unless source_enabled?(:portkey)

          cache_key = "portkey:#{provider}/#{model}"
          fetch_per_model(cache_key, "#{portkey_base_url}/#{provider}/#{model}")
        end

        # @param provider [String] e.g., "OpenAI"
        # @param model [String] e.g., "gpt-4o"
        # @param input_tokens [Integer] Token count for cost calculation
        # @param output_tokens [Integer] Token count for cost calculation
        # @return [Hash, nil] Pricing data
        def llmpricing_data(provider, model, input_tokens, output_tokens)
          return nil unless source_enabled?(:llmpricing)

          cache_key = "llmpricing:#{provider}/#{model}"
          url = "#{llmpricing_base_url}/prices?provider=#{uri_encode(provider)}&model=#{uri_encode(model)}&input_tokens=#{input_tokens}&output_tokens=#{output_tokens}"
          fetch_per_model(cache_key, url)
        end

        # ============================================================
        # Cache management
        # ============================================================

        # Clear caches and optionally re-fetch
        #
        # @param source [Symbol] :all, :litellm, :openrouter, :helicone, :portkey, :llmpricing
        def refresh!(source = :all)
          mutex.synchronize do
            case source
            when :all
              @bulk_cache = {}
              @bulk_fetched_at = {}
              @per_model_cache = {}
              @per_model_fetched_at = {}
            when :litellm, :openrouter, :helicone
              @bulk_cache&.delete(source)
              @bulk_fetched_at&.delete(source)
            when :portkey
              @per_model_cache&.reject! { |k, _| k.start_with?("portkey:") }
              @per_model_fetched_at&.reject! { |k, _| k.start_with?("portkey:") }
            when :llmpricing
              @per_model_cache&.reject! { |k, _| k.start_with?("llmpricing:") }
              @per_model_fetched_at&.reject! { |k, _| k.start_with?("llmpricing:") }
            end
          end
        end

        # @return [Hash] Cache statistics for each source
        def cache_stats
          {
            litellm: bulk_stats(:litellm),
            openrouter: bulk_stats(:openrouter),
            helicone: bulk_stats(:helicone),
            portkey: per_model_stats("portkey:"),
            llmpricing: per_model_stats("llmpricing:")
          }
        end

        private

        def mutex
          @mutex ||= Mutex.new
        end

        # ============================================================
        # Bulk fetch with two-layer cache
        # ============================================================

        def fetch_bulk(source, url, &parser)
          @bulk_cache ||= {}
          @bulk_fetched_at ||= {}

          # Layer 1: In-memory
          if @bulk_cache[source] && !bulk_cache_expired?(source)
            return @bulk_cache[source]
          end

          # Layer 2: Rails.cache
          data = from_rails_cache("ruby_llm_agents:pricing:#{source}") do
            raw_fetch(url, &parser)
          end

          mutex.synchronize do
            @bulk_cache[source] = data
            @bulk_fetched_at[source] = Time.now
          end

          data
        rescue => e
          warn "[RubyLLM::Agents::Pricing] Failed to fetch #{source}: #{e.message}"
          mutex.synchronize { @bulk_cache[source] = nil }
          nil
        end

        # ============================================================
        # Per-model fetch with two-layer cache
        # ============================================================

        def fetch_per_model(cache_key, url)
          @per_model_cache ||= {}
          @per_model_fetched_at ||= {}

          # Layer 1: In-memory
          if @per_model_cache.key?(cache_key) && !per_model_cache_expired?(cache_key)
            return @per_model_cache[cache_key]
          end

          # Layer 2: Rails.cache
          data = from_rails_cache("ruby_llm_agents:pricing:#{cache_key}") do
            raw_fetch(url) { |body| JSON.parse(body) }
          end

          mutex.synchronize do
            @per_model_cache[cache_key] = data
            @per_model_fetched_at[cache_key] = Time.now
          end

          data
        rescue => e
          warn "[RubyLLM::Agents::Pricing] Failed to fetch #{cache_key}: #{e.message}"
          nil
        end

        # ============================================================
        # HTTP fetch
        # ============================================================

        def raw_fetch(url)
          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 15

          request = Net::HTTP::Get.new(uri)
          request["Accept"] = "application/json"
          response = http.request(request)

          return nil unless response.is_a?(Net::HTTPSuccess)

          if block_given?
            yield response.body
          else
            JSON.parse(response.body)
          end
        rescue => e
          warn "[RubyLLM::Agents::Pricing] HTTP error: #{e.message}"
          nil
        end

        # ============================================================
        # Rails.cache layer
        # ============================================================

        def from_rails_cache(key)
          if rails_cache_available?
            Rails.cache.fetch(key, expires_in: cache_ttl) { yield }
          else
            yield
          end
        end

        def rails_cache_available?
          defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        end

        # ============================================================
        # Cache expiration
        # ============================================================

        def bulk_cache_expired?(source)
          fetched_at = @bulk_fetched_at&.dig(source)
          return true unless fetched_at
          Time.now - fetched_at > cache_ttl
        end

        def per_model_cache_expired?(cache_key)
          fetched_at = @per_model_fetched_at&.dig(cache_key)
          return true unless fetched_at
          Time.now - fetched_at > cache_ttl
        end

        def cache_ttl
          cfg = config
          ttl = cfg.respond_to?(:pricing_cache_ttl) && cfg.pricing_cache_ttl
          ttl ||= cfg.respond_to?(:litellm_pricing_cache_ttl) && cfg.litellm_pricing_cache_ttl
          return DEFAULT_CACHE_TTL unless ttl
          ttl.respond_to?(:to_i) ? ttl.to_i : DEFAULT_CACHE_TTL
        end

        # ============================================================
        # URL helpers
        # ============================================================

        def litellm_url
          cfg = config
          (cfg.respond_to?(:litellm_pricing_url) && cfg.litellm_pricing_url) || LITELLM_URL
        end

        def openrouter_url
          cfg = config
          (cfg.respond_to?(:openrouter_pricing_url) && cfg.openrouter_pricing_url) || OPENROUTER_URL
        end

        def helicone_url
          cfg = config
          (cfg.respond_to?(:helicone_pricing_url) && cfg.helicone_pricing_url) || HELICONE_URL
        end

        def portkey_base_url
          cfg = config
          (cfg.respond_to?(:portkey_pricing_url) && cfg.portkey_pricing_url) || PORTKEY_BASE_URL
        end

        def llmpricing_base_url
          cfg = config
          (cfg.respond_to?(:llmpricing_url) && cfg.llmpricing_url) || LLMPRICING_BASE_URL
        end

        def source_enabled?(source)
          cfg = config
          method_name = :"#{source}_pricing_enabled"
          return true unless cfg.respond_to?(method_name)
          cfg.send(method_name) != false
        end

        def uri_encode(str)
          URI.encode_www_form_component(str.to_s)
        end

        # ============================================================
        # Stats helpers
        # ============================================================

        def bulk_stats(source)
          data = @bulk_cache&.dig(source)
          {
            fetched_at: @bulk_fetched_at&.dig(source),
            size: if data.is_a?(Hash)
                    data.size
                  else
                    (data.is_a?(Array) ? data.size : 0)
                  end,
            cached: !data.nil?
          }
        end

        def per_model_stats(prefix)
          entries = (@per_model_cache || {}).select { |k, _| k.start_with?(prefix) }
          {
            cached_models: entries.size,
            keys: entries.keys
          }
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
