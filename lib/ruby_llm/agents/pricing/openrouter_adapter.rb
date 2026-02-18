# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Normalizes OpenRouter bulk model list into the common pricing format.
      #
      # OpenRouter prices are **strings** representing USD per token.
      # This adapter converts them to Float.
      #
      # Coverage: 400+ text LLM models, some audio-capable chat models.
      # No transcription, image generation, or embedding models.
      #
      # @example
      #   OpenRouterAdapter.find_model("openai/gpt-4o")
      #   # => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :openrouter }
      #
      module OpenRouterAdapter
        extend self

        # Find and normalize pricing for a model
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          models = DataStore.openrouter_data
          return nil unless models.is_a?(Array) && models.any?

          entry = find_by_id(models, model_id)
          return nil unless entry

          normalize(entry)
        end

        private

        def find_by_id(models, model_id)
          normalized = model_id.to_s.downcase

          # Exact match by id field
          entry = models.find { |m| m["id"]&.downcase == normalized }
          return entry if entry

          # Try without provider prefix (e.g., "gpt-4o" matches "openai/gpt-4o")
          entry = models.find do |m|
            id = m["id"].to_s.downcase
            id.end_with?("/#{normalized}") || id == normalized
          end
          return entry if entry

          # Try with common provider prefixes
          prefixes = %w[openai anthropic google meta-llama mistralai cohere deepseek]
          prefixes.each do |prefix|
            entry = models.find { |m| m["id"]&.downcase == "#{prefix}/#{normalized}" }
            return entry if entry
          end

          nil
        end

        def normalize(entry)
          pricing = entry["pricing"]
          return nil unless pricing.is_a?(Hash)

          result = {source: :openrouter}

          prompt_cost = safe_float(pricing["prompt"])
          completion_cost = safe_float(pricing["completion"])

          result[:input_cost_per_token] = prompt_cost if prompt_cost&.positive?
          result[:output_cost_per_token] = completion_cost if completion_cost&.positive?

          if pricing["image"]
            image_cost = safe_float(pricing["image"])
            result[:image_cost_raw] = image_cost if image_cost&.positive?
          end

          (result.keys.size > 1) ? result : nil
        end

        def safe_float(value)
          return nil if value.nil?
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
