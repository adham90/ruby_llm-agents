# frozen_string_literal: true

require "net/http"
require "json"

module RubyLLM
  module Agents
    module Audio
      # Dynamic pricing resolution for text-to-speech models.
      #
      # Uses a four-tier pricing cascade:
      # 1. LiteLLM JSON (primary) - future-proof, auto-updating
      # 2. Configurable pricing table - user overrides via config.tts_model_pricing
      # 3. ElevenLabs API - dynamic multiplier × base rate from /v1/models
      # 4. Hardcoded fallbacks - per-model defaults
      #
      # All prices are per 1,000 characters.
      #
      # @example Get cost for a speech operation
      #   SpeechPricing.calculate_cost(provider: :openai, model_id: "tts-1", characters: 5000)
      #   # => 0.075
      #
      # @example User-configured pricing
      #   RubyLLM::Agents.configure do |c|
      #     c.tts_model_pricing = {
      #       "eleven_v3" => 0.24,
      #       "tts-1" => 0.015
      #     }
      #   end
      #
      module SpeechPricing
        extend self

        LITELLM_PRICING_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        DEFAULT_CACHE_TTL = 24 * 60 * 60 # 24 hours

        # Calculate total cost for a speech operation
        #
        # @param provider [Symbol] :openai or :elevenlabs
        # @param model_id [String] The model identifier
        # @param characters [Integer] Number of characters synthesized
        # @return [Float] Total cost in USD
        def calculate_cost(provider:, model_id:, characters:)
          price_per_1k = cost_per_1k_characters(provider, model_id)
          ((characters / 1000.0) * price_per_1k).round(6)
        end

        # Get cost per 1,000 characters for a model
        #
        # @param provider [Symbol] Provider identifier
        # @param model_id [String] Model identifier
        # @return [Float] Cost per 1K characters in USD
        def cost_per_1k_characters(provider, model_id)
          # Tier 1: LiteLLM
          if (litellm_price = from_litellm(model_id))
            return litellm_price
          end

          # Tier 2: User config overrides
          if (config_price = from_config(model_id))
            return config_price
          end

          # Tier 3: ElevenLabs API multiplier × base rate
          if provider == :elevenlabs && (api_price = from_elevenlabs_api(model_id))
            return api_price
          end

          # Tier 4: Hardcoded fallbacks
          fallback_price(provider, model_id)
        end

        # Force refresh of cached LiteLLM data
        def refresh!
          @litellm_data = nil
          @litellm_fetched_at = nil
          litellm_data
        end

        # Expose all known pricing for debugging/dashboard
        def all_pricing
          {
            litellm: litellm_tts_models,
            configured: config.tts_model_pricing || {},
            elevenlabs_api: elevenlabs_api_pricing,
            fallbacks: fallback_pricing_table
          }
        end

        private

        # ============================================================
        # Tier 1: LiteLLM
        # ============================================================

        def from_litellm(model_id)
          data = litellm_data
          return nil unless data

          model_data = find_litellm_model(data, model_id)
          return nil unless model_data

          extract_litellm_tts_price(model_data)
        end

        def find_litellm_model(data, model_id)
          normalized = normalize_model_id(model_id)

          candidates = [
            model_id,
            normalized,
            "tts/#{model_id}",
            "openai/#{model_id}",
            "elevenlabs/#{model_id}"
          ]

          candidates.each do |key|
            return data[key] if data[key]
          end

          data.find do |key, _|
            key.to_s.downcase.include?(normalized.downcase)
          end&.last
        end

        def extract_litellm_tts_price(model_data)
          if model_data["input_cost_per_character"]
            return model_data["input_cost_per_character"] * 1000
          end

          if model_data["output_cost_per_character"]
            return model_data["output_cost_per_character"] * 1000
          end

          if model_data["output_cost_per_audio_token"]
            return model_data["output_cost_per_audio_token"] * 250
          end

          nil
        end

        def litellm_data
          return @litellm_data if @litellm_data && !cache_expired?

          @litellm_data = fetch_litellm_data
          @litellm_fetched_at = Time.now
          @litellm_data
        end

        def fetch_litellm_data
          if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
            Rails.cache.fetch("litellm_tts_pricing_data", expires_in: cache_ttl) do
              fetch_from_url
            end
          else
            fetch_from_url
          end
        rescue => e
          warn "[RubyLLM::Agents] Failed to fetch LiteLLM TTS pricing: #{e.message}"
          {}
        end

        def fetch_from_url
          uri = URI(config.litellm_pricing_url || LITELLM_PRICING_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 10

          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          if response.is_a?(Net::HTTPSuccess)
            JSON.parse(response.body)
          else
            {}
          end
        rescue => e
          warn "[RubyLLM::Agents] HTTP error fetching LiteLLM pricing: #{e.message}"
          {}
        end

        def cache_expired?
          return true unless @litellm_fetched_at
          Time.now - @litellm_fetched_at > cache_ttl
        end

        def cache_ttl
          ttl = config.litellm_pricing_cache_ttl
          return DEFAULT_CACHE_TTL unless ttl
          ttl.respond_to?(:to_i) ? ttl.to_i : ttl
        end

        def litellm_tts_models
          litellm_data.select do |key, value|
            value.is_a?(Hash) && (
              value["input_cost_per_character"] ||
              key.to_s.match?(/tts|speech|eleven/i)
            )
          end
        end

        def elevenlabs_api_pricing
          return {} unless defined?(ElevenLabs::ModelRegistry)

          base = config.elevenlabs_base_cost_per_1k || 0.30
          ElevenLabs::ModelRegistry.models.each_with_object({}) do |model, hash|
            multiplier = model.dig("model_rates", "character_cost_multiplier") || 1.0
            hash[model["model_id"]] = (base * multiplier).round(6)
          end
        rescue => e
          warn "[RubyLLM::Agents] Failed to get ElevenLabs API pricing: #{e.message}"
          {}
        end

        # ============================================================
        # Tier 2: User configuration
        # ============================================================

        def from_config(model_id)
          table = config.tts_model_pricing
          return nil unless table.is_a?(Hash) && !table.empty?

          normalized = normalize_model_id(model_id)

          price = table[model_id] || table[normalized] ||
            table[model_id.to_sym] || table[normalized.to_sym]

          price if price.is_a?(Numeric)
        end

        # ============================================================
        # Tier 3: ElevenLabs API (dynamic multiplier × base rate)
        # ============================================================

        def from_elevenlabs_api(model_id)
          return nil unless defined?(ElevenLabs::ModelRegistry)

          model = ElevenLabs::ModelRegistry.find(model_id)
          return nil unless model

          multiplier = model.dig("model_rates", "character_cost_multiplier") || 1.0
          base = config.elevenlabs_base_cost_per_1k || 0.30
          (base * multiplier).round(6)
        rescue => e
          warn "[RubyLLM::Agents] Failed to get ElevenLabs API pricing: #{e.message}"
          nil
        end

        # ============================================================
        # Tier 4: Hardcoded fallbacks
        # ============================================================

        def fallback_price(provider, model_id)
          normalized = normalize_model_id(model_id)

          case provider
          when :openai
            openai_fallback_price(normalized)
          when :elevenlabs
            elevenlabs_fallback_price(normalized)
          else
            config.default_tts_cost || 0.015
          end
        end

        def openai_fallback_price(model_id)
          case model_id
          when /tts-1-hd/ then 0.030
          when /tts-1/ then 0.015
          else 0.015
          end
        end

        def elevenlabs_fallback_price(model_id)
          case model_id
          when /eleven_flash_v2/ then 0.15
          when /eleven_turbo_v2/ then 0.15
          when /eleven_v3/ then 0.30
          when /eleven_multilingual_v2/ then 0.30
          when /eleven_multilingual_v1/ then 0.30
          when /eleven_monolingual_v1/ then 0.30
          else 0.30
          end
        end

        def fallback_pricing_table
          {
            "tts-1" => 0.015,
            "tts-1-hd" => 0.030,
            "eleven_monolingual_v1" => 0.30,
            "eleven_multilingual_v1" => 0.30,
            "eleven_multilingual_v2" => 0.30,
            "eleven_turbo_v2" => 0.15,
            "eleven_flash_v2" => 0.15,
            "eleven_turbo_v2_5" => 0.15,
            "eleven_flash_v2_5" => 0.15,
            "eleven_v3" => 0.30
          }
        end

        def normalize_model_id(model_id)
          model_id.to_s.downcase
            .gsub(/[^a-z0-9._-]/, "-").squeeze("-")
            .gsub(/^-|-$/, "")
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
