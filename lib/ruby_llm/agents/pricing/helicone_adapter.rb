# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Normalizes Helicone bulk cost list into the common pricing format.
      #
      # Helicone prices are **per 1M tokens**. This adapter converts to
      # per-token for consistency.
      #
      # Coverage: 172 text LLM models, some realtime audio models.
      # No transcription, TTS, image, or embedding models.
      #
      # @example
      #   HeliconeAdapter.find_model("gpt-4o")
      #   # => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :helicone }
      #
      module HeliconeAdapter
        extend self

        # Find and normalize pricing for a model
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          data = DataStore.helicone_data
          return nil unless data.is_a?(Array) && data.any?

          entry = find_matching(data, model_id)
          return nil unless entry

          normalize(entry)
        end

        private

        def find_matching(data, model_id)
          normalized = model_id.to_s.downcase

          # Exact match on model field
          entry = data.find { |e| e["model"]&.downcase == normalized }
          return entry if entry

          # Try without provider prefix
          entry = data.find do |e|
            model_name = e["model"].to_s.downcase
            model_name == normalized || model_name.end_with?("/#{normalized}")
          end
          return entry if entry

          # Fuzzy: model field contains the normalized ID
          data.find do |e|
            e["model"].to_s.downcase.include?(normalized)
          end
        end

        def normalize(entry)
          result = {source: :helicone}

          # Per-1M-token → per-token
          if (input_1m = safe_number(entry["input_cost_per_1m"]))
            result[:input_cost_per_token] = input_1m / 1_000_000.0
          end

          if (output_1m = safe_number(entry["output_cost_per_1m"]))
            result[:output_cost_per_token] = output_1m / 1_000_000.0
          end

          # Audio tokens (realtime models)
          if (audio_in = safe_number(entry["prompt_audio_per_1m"]))
            result[:input_cost_per_audio_token] = audio_in / 1_000_000.0
          end

          if (audio_out = safe_number(entry["completion_audio_per_1m"]))
            result[:output_cost_per_audio_token] = audio_out / 1_000_000.0
          end

          (result.keys.size > 1) ? result : nil
        end

        def safe_number(value)
          return nil unless value.is_a?(Numeric) && value.positive?
          value
        end
      end
    end
  end
end
