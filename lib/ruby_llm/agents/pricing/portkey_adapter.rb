# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Normalizes Portkey AI per-model pricing into the common format.
      #
      # Portkey prices are in **cents per token**. This adapter converts to
      # USD per token for consistency with other adapters.
      #
      # Requires knowing the provider for a model, resolved via PROVIDER_MAP.
      #
      # @example
      #   PortkeyAdapter.find_model("gpt-4o")
      #   # => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :portkey }
      #
      module PortkeyAdapter
        extend self

        PROVIDER_MAP = [
          [/^(gpt-|o1|o3|o4|whisper|dall-e|tts-|chatgpt)/, "openai"],
          [/^claude/, "anthropic"],
          [/^gemini/, "google"],
          [/^(mistral|codestral|pixtral|ministral)/, "mistralai"],
          [/^llama/, "meta"],
          [/^(command|embed)/, "cohere"],
          [/^deepseek/, "deepseek"],
          [/^(nova|titan)/, "amazon"]
        ].freeze

        # Find and normalize pricing for a model
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          provider, model_name = resolve_provider(model_id)
          return nil unless provider

          raw = DataStore.portkey_data(provider, model_name)
          return nil unless raw.is_a?(Hash) && raw["pay_as_you_go"]

          normalize(raw)
        end

        private

        def resolve_provider(model_id)
          id = model_id.to_s

          # Handle prefixed model IDs like "azure/gpt-4o" or "groq/llama-3"
          if id.include?("/")
            parts = id.split("/", 2)
            return [parts[0], parts[1]]
          end

          PROVIDER_MAP.each do |pattern, provider|
            return [provider, id] if id.match?(pattern)
          end

          nil
        end

        def normalize(raw)
          pag = raw["pay_as_you_go"]
          return nil unless pag

          result = {source: :portkey}

          # Main text token pricing (cents → USD)
          req_price = dig_price(pag, "request_token", "price")
          resp_price = dig_price(pag, "response_token", "price")
          result[:input_cost_per_token] = req_price / 100.0 if req_price&.positive?
          result[:output_cost_per_token] = resp_price / 100.0 if resp_price&.positive?

          # Additional units (audio tokens, etc.)
          additional = pag["additional_units"]
          if additional.is_a?(Hash)
            audio_in = dig_price(additional, "request_audio_token", "price")
            audio_out = dig_price(additional, "response_audio_token", "price")
            result[:input_cost_per_audio_token] = audio_in / 100.0 if audio_in&.positive?
            result[:output_cost_per_audio_token] = audio_out / 100.0 if audio_out&.positive?
          end

          (result.keys.size > 1) ? result : nil
        end

        def dig_price(hash, *keys)
          value = hash.dig(*keys)
          value.is_a?(Numeric) ? value : nil
        end
      end
    end
  end
end
