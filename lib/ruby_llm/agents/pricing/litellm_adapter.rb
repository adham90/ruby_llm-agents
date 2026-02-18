# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Normalizes LiteLLM bulk JSON into the common pricing format.
      #
      # Supports all model types:
      # - Text LLM: input_cost_per_token, output_cost_per_token
      # - Transcription: input_cost_per_second, input_cost_per_audio_token
      # - TTS/Speech: input_cost_per_character, output_cost_per_character
      # - Image: input_cost_per_image, input_cost_per_pixel
      # - Embedding: input_cost_per_token (with mode: "embedding")
      #
      # @example
      #   LiteLLMAdapter.find_model("whisper-1")
      #   # => { input_cost_per_second: 0.0001, mode: "audio_transcription", source: :litellm }
      #
      module LiteLLMAdapter
        extend self

        # Find and normalize pricing for a model
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          data = DataStore.litellm_data
          return nil unless data.is_a?(Hash) && data.any?

          model_data = find_by_candidates(data, model_id)
          return nil unless model_data

          normalize(model_data)
        end

        private

        def find_by_candidates(data, model_id)
          normalized = normalize_model_id(model_id)

          # Exact and prefix candidate keys
          candidates = [
            model_id,
            normalized,
            "audio_transcription/#{model_id}",
            "tts/#{model_id}",
            "openai/#{model_id}",
            "elevenlabs/#{model_id}",
            "whisper/#{model_id}"
          ]

          candidates.each do |key|
            return data[key] if data[key].is_a?(Hash)
          end

          # Fuzzy match: find keys containing the normalized model ID
          normalized_lower = normalized.downcase
          data.each do |key, value|
            next unless value.is_a?(Hash)
            key_lower = key.to_s.downcase

            if key_lower.include?(normalized_lower) || normalized_lower.include?(key_lower.split("/").last.to_s)
              return value
            end
          end

          nil
        end

        def normalize(raw)
          result = {source: :litellm}

          # Text LLM / Embedding
          result[:input_cost_per_token] = raw["input_cost_per_token"] if raw["input_cost_per_token"]
          result[:output_cost_per_token] = raw["output_cost_per_token"] if raw["output_cost_per_token"]

          # Transcription
          result[:input_cost_per_second] = raw["input_cost_per_second"] if raw["input_cost_per_second"]
          result[:input_cost_per_audio_token] = raw["input_cost_per_audio_token"] if raw["input_cost_per_audio_token"]

          # TTS / Speech
          result[:input_cost_per_character] = raw["input_cost_per_character"] if raw["input_cost_per_character"]
          result[:output_cost_per_character] = raw["output_cost_per_character"] if raw["output_cost_per_character"]
          result[:output_cost_per_audio_token] = raw["output_cost_per_audio_token"] if raw["output_cost_per_audio_token"]

          # Image
          result[:input_cost_per_image] = raw["input_cost_per_image"] if raw["input_cost_per_image"]
          result[:input_cost_per_pixel] = raw["input_cost_per_pixel"] if raw["input_cost_per_pixel"]
          result[:input_cost_per_image_hd] = raw["input_cost_per_image_hd"] if raw["input_cost_per_image_hd"]

          # Metadata
          result[:mode] = raw["mode"] if raw["mode"]

          result
        end

        def normalize_model_id(model_id)
          model_id.to_s.downcase
            .gsub(/[^a-z0-9._\/-]/, "-").squeeze("-")
            .gsub(/^-|-$/, "")
        end
      end
    end
  end
end
