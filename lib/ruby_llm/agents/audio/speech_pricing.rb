# frozen_string_literal: true

require_relative "../pricing/data_store"
require_relative "../pricing/ruby_llm_adapter"
require_relative "../pricing/litellm_adapter"

module RubyLLM
  module Agents
    module Audio
      # Dynamic pricing resolution for text-to-speech models.
      #
      # Uses a three-tier pricing cascade (no hardcoded prices):
      # 1. Configurable pricing table - user overrides via config.tts_model_pricing
      # 2. LiteLLM (via shared DataStore) - comprehensive, community-maintained
      # 3. ElevenLabs API - dynamic multiplier × user-configured base rate
      #
      # When no pricing is found, returns 0 to signal unknown cost.
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
        # @return [Float] Cost per 1K characters in USD (0 if unknown)
        def cost_per_1k_characters(provider, model_id)
          # Tier 1: User config overrides (highest priority)
          if (config_price = from_config(model_id))
            return config_price
          end

          # Tier 2: LiteLLM (via shared adapter/DataStore)
          if (litellm_price = from_litellm(model_id))
            return litellm_price
          end

          # Tier 3: ElevenLabs API multiplier × user-configured base rate
          if provider == :elevenlabs && (api_price = from_elevenlabs_api(model_id))
            return api_price
          end

          # No pricing found — return user-configured default or 0
          config.default_tts_cost || 0
        end

        # Force refresh of cached pricing data
        def refresh!
          Pricing::DataStore.refresh!
        end

        # Expose all known pricing for debugging/console inspection
        def all_pricing
          {
            litellm: litellm_tts_models,
            configured: config.tts_model_pricing || {},
            elevenlabs_api: elevenlabs_api_pricing
          }
        end

        private

        # ============================================================
        # Tier 1: User configuration
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
        # Tier 2: LiteLLM (via shared DataStore + adapter)
        # ============================================================

        def from_litellm(model_id)
          data = Pricing::LiteLLMAdapter.find_model(model_id)
          return nil unless data

          extract_tts_price(data)
        end

        def extract_tts_price(data)
          if data[:input_cost_per_character]
            return (data[:input_cost_per_character] * 1000).round(6)
          end

          if data[:output_cost_per_character]
            return (data[:output_cost_per_character] * 1000).round(6)
          end

          if data[:output_cost_per_audio_token]
            return (data[:output_cost_per_audio_token] * 250).round(6)
          end

          nil
        end

        def litellm_tts_models
          data = Pricing::DataStore.litellm_data
          return {} unless data.is_a?(Hash)

          data.select do |key, value|
            value.is_a?(Hash) && (
              value["input_cost_per_character"] ||
              key.to_s.match?(/tts|speech|eleven/i)
            )
          end
        end

        # ============================================================
        # Tier 3: ElevenLabs API (dynamic multiplier × base rate)
        # ============================================================

        def from_elevenlabs_api(model_id)
          return nil unless defined?(ElevenLabs::ModelRegistry)

          base = config.elevenlabs_base_cost_per_1k
          return nil unless base

          model = ElevenLabs::ModelRegistry.find(model_id)
          return nil unless model

          multiplier = model.dig("model_rates", "character_cost_multiplier") || 1.0
          (base * multiplier).round(6)
        rescue => e
          warn "[RubyLLM::Agents] Failed to get ElevenLabs API pricing: #{e.message}"
          nil
        end

        def elevenlabs_api_pricing
          return {} unless defined?(ElevenLabs::ModelRegistry)

          base = config.elevenlabs_base_cost_per_1k
          return {} unless base

          ElevenLabs::ModelRegistry.models.each_with_object({}) do |model, hash|
            multiplier = model.dig("model_rates", "character_cost_multiplier") || 1.0
            hash[model["model_id"]] = (base * multiplier).round(6)
          end
        rescue => e
          warn "[RubyLLM::Agents] Failed to get ElevenLabs API pricing: #{e.message}"
          {}
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
