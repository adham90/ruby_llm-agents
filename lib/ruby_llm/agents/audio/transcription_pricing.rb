# frozen_string_literal: true

require_relative "../pricing/data_store"
require_relative "../pricing/ruby_llm_adapter"
require_relative "../pricing/litellm_adapter"
require_relative "../pricing/portkey_adapter"
require_relative "../pricing/openrouter_adapter"
require_relative "../pricing/helicone_adapter"
require_relative "../pricing/llmpricing_adapter"

module RubyLLM
  module Agents
    module Audio
      # Dynamic pricing resolution for audio transcription models.
      #
      # Cascades through multiple pricing sources to maximize coverage:
      # 1. User config (instant, always wins)
      # 2. RubyLLM gem (local, no HTTP, already a dependency)
      # 3. LiteLLM (bulk, most comprehensive for transcription)
      # 4. Portkey AI (per-model, good transcription coverage)
      # 5. OpenRouter (bulk, audio-capable chat models only)
      # 6. Helicone (text LLM only — pass-through, future-proof)
      # 7. LLM Pricing AI (text LLM only — pass-through, future-proof)
      #
      # When no pricing is found, methods return nil to signal the caller
      # should warn the user with actionable configuration instructions.
      #
      # All prices are per minute of audio.
      #
      # @example Get cost for a transcription
      #   TranscriptionPricing.calculate_cost(model_id: "whisper-1", duration_seconds: 120)
      #   # => 0.012 (or nil if no pricing found)
      #
      # @example User-configured pricing
      #   RubyLLM::Agents.configure do |c|
      #     c.transcription_model_pricing = { "whisper-1" => 0.006 }
      #   end
      #
      module TranscriptionPricing
        extend self

        LITELLM_PRICING_URL = Pricing::DataStore::LITELLM_URL

        SOURCES = [:config, :ruby_llm, :litellm, :portkey, :openrouter, :helicone, :llmpricing].freeze

        # Calculate total cost for a transcription operation
        #
        # @param model_id [String] The model identifier
        # @param duration_seconds [Numeric] Duration of audio in seconds
        # @return [Float, nil] Total cost in USD, or nil if no pricing found
        def calculate_cost(model_id:, duration_seconds:)
          price = cost_per_minute(model_id)
          return nil unless price

          duration_minutes = duration_seconds / 60.0
          (duration_minutes * price).round(6)
        end

        # Get cost per minute for a transcription model
        #
        # @param model_id [String] Model identifier
        # @return [Float, nil] Cost per minute in USD, or nil if not found
        def cost_per_minute(model_id)
          SOURCES.each do |source|
            price = send(:"from_#{source}", model_id)
            return price if price
          end
          nil
        end

        # Check whether pricing is available for a model
        #
        # @param model_id [String] Model identifier
        # @return [Boolean] true if pricing is available
        def pricing_found?(model_id)
          !cost_per_minute(model_id).nil?
        end

        # Force refresh of cached pricing data
        def refresh!
          Pricing::DataStore.refresh!
        end

        # Expose all known pricing for debugging/dashboard
        #
        # @return [Hash] Pricing from all tiers
        def all_pricing
          {
            ruby_llm: {},  # local gem, per-model lookup
            litellm: litellm_transcription_models,
            portkey: {},  # per-model, populated on demand
            openrouter: {},  # no dedicated transcription models
            helicone: {},  # no transcription models
            configured: config.transcription_model_pricing || {}
          }
        end

        private

        # ============================================================
        # Tier 1: User configuration (highest priority)
        # ============================================================

        def from_config(model_id)
          table = config.transcription_model_pricing
          return nil unless table.is_a?(Hash) && !table.empty?

          normalized = normalize_model_id(model_id)

          price = table[model_id] || table[normalized] ||
            table[model_id.to_sym] || table[normalized.to_sym]

          price if price.is_a?(Numeric)
        end

        # ============================================================
        # Tier 2: RubyLLM gem (local, no HTTP)
        # ============================================================

        def from_ruby_llm(model_id)
          data = Pricing::RubyLLMAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Tier 3: LiteLLM
        # ============================================================

        def from_litellm(model_id)
          data = Pricing::LiteLLMAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Tier 4: Portkey AI
        # ============================================================

        def from_portkey(model_id)
          data = Pricing::PortkeyAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Tier 5: OpenRouter (audio-capable chat models only)
        # ============================================================

        def from_openrouter(model_id)
          data = Pricing::OpenRouterAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Tier 6: Helicone (text LLM only — future-proof)
        # ============================================================

        def from_helicone(model_id)
          data = Pricing::HeliconeAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Tier 7: LLM Pricing AI (text LLM only — future-proof)
        # ============================================================

        def from_llmpricing(model_id)
          data = Pricing::LLMPricingAdapter.find_model(model_id)
          return nil unless data

          extract_per_minute(data)
        end

        # ============================================================
        # Price extraction
        # ============================================================

        def extract_per_minute(data)
          # Per-second pricing (most common for transcription: whisper-1, etc.)
          if data[:input_cost_per_second]
            return (data[:input_cost_per_second] * 60).round(6)
          end

          # Per-audio-token pricing (GPT-4o-transcribe models)
          # ~25 audio tokens/second = 1500 tokens/minute
          if data[:input_cost_per_audio_token]
            return (data[:input_cost_per_audio_token] * 1500).round(6)
          end

          nil
        end

        def litellm_transcription_models
          data = Pricing::DataStore.litellm_data
          return {} unless data.is_a?(Hash)

          data.select do |key, value|
            value.is_a?(Hash) && (
              value["mode"] == "audio_transcription" ||
              value["input_cost_per_second"] ||
              key.to_s.match?(/whisper|transcri/i)
            )
          end
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
