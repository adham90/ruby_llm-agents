# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Normalizes LLM Pricing AI per-model data into the common pricing format.
      #
      # This API returns **calculated costs** for a given token count, not raw rates.
      # We query with 1M tokens to derive per-token rates.
      #
      # Coverage: ~79 models across 4 providers (OpenAI, Anthropic, Groq, Mistral).
      # Text LLM only — no transcription, TTS, image, or embedding.
      #
      # @example
      #   LLMPricingAdapter.find_model("gpt-4o")
      #   # => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :llmpricing }
      #
      module LLMPricingAdapter
        extend self

        PROVIDER_MAP = [
          [/^(gpt-|o1|o3|o4|whisper|dall-e|tts-|chatgpt)/, "OpenAI"],
          [/^claude/, "Anthropic"],
          [/^(mixtral|mistral|codestral|pixtral|ministral)/, "Mistral"],
          [/^(gemma|llama)/, "Groq"]
        ].freeze

        QUERY_TOKENS = 1_000_000

        # Find and normalize pricing for a model
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          provider = resolve_provider(model_id)
          return nil unless provider

          raw = DataStore.llmpricing_data(provider, model_id, QUERY_TOKENS, QUERY_TOKENS)
          return nil unless raw.is_a?(Hash)
          return nil unless raw["input_cost"].is_a?(Numeric) && raw["input_cost"].positive?

          normalize(raw)
        end

        private

        def resolve_provider(model_id)
          id = model_id.to_s.downcase

          PROVIDER_MAP.each do |pattern, provider|
            return provider if id.match?(pattern)
          end

          nil
        end

        def normalize(raw)
          result = {source: :llmpricing}

          if raw["input_cost"].is_a?(Numeric)
            result[:input_cost_per_token] = raw["input_cost"] / QUERY_TOKENS.to_f
          end

          if raw["output_cost"].is_a?(Numeric) && raw["output_cost"].positive?
            result[:output_cost_per_token] = raw["output_cost"] / QUERY_TOKENS.to_f
          end

          result
        end
      end
    end
  end
end
