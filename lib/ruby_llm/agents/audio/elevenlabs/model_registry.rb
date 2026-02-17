# frozen_string_literal: true

require "faraday"
require "json"

module RubyLLM
  module Agents
    module Audio
      module ElevenLabs
        # Fetches and caches ElevenLabs model data from the /v1/models API.
        #
        # Used for:
        # - Dynamic cost calculation via character_cost_multiplier
        # - Model validation (TTS vs STS capability)
        # - Capability awareness (style, speaker_boost, max chars, languages)
        #
        # @example Check if a model supports TTS
        #   ElevenLabs::ModelRegistry.tts_model?("eleven_v3") # => true
        #   ElevenLabs::ModelRegistry.tts_model?("eleven_english_sts_v2") # => false
        #
        # @example Get cost multiplier
        #   ElevenLabs::ModelRegistry.cost_multiplier("eleven_flash_v2_5") # => 0.5
        #
        module ModelRegistry
          extend self

          # Returns all models from the ElevenLabs API (cached)
          #
          # @return [Array<Hash>] Array of model hashes
          def models
            @mutex ||= Mutex.new
            @mutex.synchronize do
              if @models && !cache_expired?
                return @models
              end

              @models = fetch_models
              @fetched_at = Time.now
              @models
            end
          end

          # Find a specific model by ID
          #
          # @param model_id [String] The model identifier
          # @return [Hash, nil] Model hash or nil if not found
          def find(model_id)
            models.find { |m| m["model_id"] == model_id.to_s }
          end

          # Check if model supports text-to-speech
          #
          # @param model_id [String] The model identifier
          # @return [Boolean]
          def tts_model?(model_id)
            model = find(model_id)
            return false unless model

            model["can_do_text_to_speech"] == true
          end

          # Get character_cost_multiplier for a model
          #
          # @param model_id [String] The model identifier
          # @return [Float] Cost multiplier (defaults to 1.0 for unknown models)
          def cost_multiplier(model_id)
            model = find(model_id)
            model&.dig("model_rates", "character_cost_multiplier") || 1.0
          end

          # Get max characters per request for a model
          #
          # @param model_id [String] The model identifier
          # @return [Integer, nil] Max characters or nil if unknown
          def max_characters(model_id)
            model = find(model_id)
            model&.dig("maximum_text_length_per_request")
          end

          # Get supported language IDs for a model
          #
          # @param model_id [String] The model identifier
          # @return [Array<String>] Language IDs (e.g. ["en", "es", "ja"])
          def languages(model_id)
            model = find(model_id)
            model&.dig("languages")&.map { |l| l["language_id"] } || []
          end

          # Check if model supports the style voice setting
          #
          # @param model_id [String] The model identifier
          # @return [Boolean]
          def supports_style?(model_id)
            find(model_id)&.dig("can_use_style") == true
          end

          # Check if model supports the speaker_boost setting
          #
          # @param model_id [String] The model identifier
          # @return [Boolean]
          def supports_speaker_boost?(model_id)
            find(model_id)&.dig("can_use_speaker_boost") == true
          end

          # Check if model supports voice conversion (speech-to-speech)
          # Used by VoiceConverter agent (see plans/elevenlabs_voice_converter.md)
          #
          # @param model_id [String] The model identifier
          # @return [Boolean]
          def voice_conversion_model?(model_id)
            model = find(model_id)
            return false unless model

            model["can_do_voice_conversion"] == true
          end

          # Force refresh the cache
          #
          # @return [Array<Hash>] Fresh model data
          def refresh!
            @mutex ||= Mutex.new
            @mutex.synchronize do
              @models = nil
              @fetched_at = nil
            end
            models
          end

          # Clear cache without re-fetching (useful for tests)
          #
          # @return [void]
          def clear_cache!
            @mutex ||= Mutex.new
            @mutex.synchronize do
              @models = nil
              @fetched_at = nil
            end
          end

          private

          def fetch_models
            return [] unless api_key

            response = connection.get("/v1/models")

            if response.success?
              parsed = JSON.parse(response.body)
              parsed.is_a?(Array) ? parsed : []
            else
              warn "[RubyLLM::Agents] ElevenLabs /v1/models returned HTTP #{response.status}"
              @models || []
            end
          rescue Faraday::Error, JSON::ParserError => e
            warn "[RubyLLM::Agents] Failed to fetch ElevenLabs models: #{e.message}"
            @models || []
          end

          def cache_expired?
            return true unless @fetched_at

            ttl = RubyLLM::Agents.configuration.elevenlabs_models_cache_ttl || 21_600
            Time.now - @fetched_at > ttl
          end

          def api_key
            RubyLLM::Agents.configuration.elevenlabs_api_key
          end

          def api_base
            base = RubyLLM::Agents.configuration.elevenlabs_api_base
            (base && !base.empty?) ? base : "https://api.elevenlabs.io"
          end

          def connection
            Faraday.new(url: api_base) do |f|
              f.headers["xi-api-key"] = api_key
              f.adapter Faraday.default_adapter
              f.options.timeout = 10
              f.options.open_timeout = 5
            end
          end
        end
      end
    end
  end
end
