# frozen_string_literal: true

require "faraday"
require "json"

module RubyLLM
  module Agents
    module Audio
      # Direct HTTP client for text-to-speech APIs.
      #
      # Supports OpenAI and ElevenLabs providers, bypassing the need for
      # a RubyLLM.speak() method that does not exist in the base gem.
      #
      # @example OpenAI
      #   client = SpeechClient.new(provider: :openai)
      #   response = client.speak("Hello", model: "tts-1", voice: "nova")
      #   response.audio  # => binary audio data
      #
      # @example ElevenLabs
      #   client = SpeechClient.new(provider: :elevenlabs)
      #   response = client.speak("Hello",
      #     model: "eleven_v3",
      #     voice: "Rachel",
      #     voice_id: "21m00Tcm4TlvDq8ikWAM",
      #     voice_settings: { stability: 0.5, similarity_boost: 0.75 }
      #   )
      #
      class SpeechClient
        SUPPORTED_PROVIDERS = %i[openai elevenlabs].freeze

        Response = Struct.new(:audio, :format, :model, :voice, keyword_init: true) do
          def duration
            nil
          end

          def cost
            nil
          end
        end

        StreamChunk = Struct.new(:audio, keyword_init: true)

        # @param provider [Symbol] :openai or :elevenlabs
        # @raise [UnsupportedProviderError] if provider is not supported
        def initialize(provider:)
          validate_provider!(provider)
          @provider = provider
        end

        # Synthesize speech (non-streaming)
        #
        # @param text [String] text to convert
        # @param model [String] model identifier
        # @param voice [String] voice name
        # @param voice_id [String, nil] voice ID (required for ElevenLabs)
        # @param speed [Float, nil] speed multiplier
        # @param response_format [String] output format
        # @param voice_settings [Hash, nil] ElevenLabs voice settings
        # @return [Response]
        def speak(text, model:, voice:, voice_id: nil, speed: nil,
          response_format: "mp3", voice_settings: nil)
          case @provider
          when :openai
            openai_speak(text, model: model, voice: voice_id || voice,
              speed: speed, response_format: response_format)
          when :elevenlabs
            elevenlabs_speak(text, model: model, voice_id: voice_id || voice,
              speed: speed, response_format: response_format,
              voice_settings: voice_settings)
          end
        end

        # Synthesize speech with streaming
        #
        # @param text [String] text to convert
        # @param model [String] model identifier
        # @param voice [String] voice name
        # @param voice_id [String, nil] voice ID
        # @param speed [Float, nil] speed multiplier
        # @param response_format [String] output format
        # @param voice_settings [Hash, nil] ElevenLabs voice settings
        # @yield [StreamChunk] each audio chunk as it arrives
        # @return [Response]
        def speak_streaming(text, model:, voice:, voice_id: nil, speed: nil,
          response_format: "mp3", voice_settings: nil, &block)
          case @provider
          when :openai
            openai_speak_streaming(text, model: model, voice: voice_id || voice,
                                   speed: speed, response_format: response_format,
              &block)
          when :elevenlabs
            elevenlabs_speak_streaming(text, model: model,
                                       voice_id: voice_id || voice,
                                       speed: speed,
                                       response_format: response_format,
                                       voice_settings: voice_settings, &block)
          end
        end

        private

        # ============================================================
        # Provider validation
        # ============================================================

        def validate_provider!(provider)
          return if SUPPORTED_PROVIDERS.include?(provider)

          raise UnsupportedProviderError.new(
            "Provider :#{provider} is not yet supported for text-to-speech. " \
            "Supported providers: #{SUPPORTED_PROVIDERS.map { |p| ":#{p}" }.join(", ")}.",
            provider: provider
          )
        end

        # ============================================================
        # OpenAI implementation
        # ============================================================

        def openai_speak(text, model:, voice:, speed:, response_format:)
          body = openai_request_body(text, model: model, voice: voice,
            speed: speed, response_format: response_format)

          response = openai_connection.post("/v1/audio/speech") do |req|
            req.headers["Content-Type"] = "application/json"
            req.body = body.to_json
          end

          handle_error_response!(response) unless response.success?

          Response.new(
            audio: response.body,
            format: response_format.to_sym,
            model: model,
            voice: voice
          )
        end

        def openai_speak_streaming(text, model:, voice:, speed:,
          response_format:, &block)
          body = openai_request_body(text, model: model, voice: voice,
            speed: speed, response_format: response_format)
          chunks = []

          openai_connection.post("/v1/audio/speech") do |req|
            req.headers["Content-Type"] = "application/json"
            req.body = body.to_json
            req.options.on_data = proc do |chunk, _size, env|
              if env.status == 200
                chunk_obj = StreamChunk.new(audio: chunk)
                chunks << chunk
                block&.call(chunk_obj)
              end
            end
          end

          Response.new(
            audio: chunks.join,
            format: response_format.to_sym,
            model: model,
            voice: voice
          )
        end

        def openai_request_body(text, model:, voice:, speed:, response_format:)
          body = {
            model: model,
            input: text,
            voice: voice,
            response_format: response_format.to_s
          }
          body[:speed] = speed if speed && (speed - 1.0).abs > Float::EPSILON
          body
        end

        def openai_connection
          @openai_connection ||= Faraday.new(url: openai_api_base) do |f|
            f.headers["Authorization"] = "Bearer #{openai_api_key}"
            f.adapter Faraday.default_adapter
            f.options.timeout = 120
            f.options.open_timeout = 30
          end
        end

        def openai_api_key
          key = RubyLLM.config.openai_api_key
          unless key
            raise ConfigurationError,
              "OpenAI API key is required for text-to-speech. " \
              "Set it via: RubyLLM.configure { |c| c.openai_api_key = 'sk-...' }"
          end
          key
        end

        def openai_api_base
          base = RubyLLM.config.openai_api_base
          (base && !base.empty?) ? base : "https://api.openai.com"
        end

        # ============================================================
        # ElevenLabs implementation
        # ============================================================

        def elevenlabs_speak(text, model:, voice_id:, speed:,
          response_format:, voice_settings:)
          path = "/v1/text-to-speech/#{voice_id}"
          body = elevenlabs_request_body(text, model: model, speed: speed,
            voice_settings: voice_settings)
          format_param = elevenlabs_output_format(response_format)

          response = elevenlabs_connection.post(path) do |req|
            req.headers["Content-Type"] = "application/json"
            req.params["output_format"] = format_param
            req.body = body.to_json
          end

          handle_error_response!(response) unless response.success?

          Response.new(
            audio: response.body,
            format: response_format.to_sym,
            model: model,
            voice: voice_id
          )
        end

        def elevenlabs_speak_streaming(text, model:, voice_id:, speed:,
          response_format:, voice_settings:, &block)
          path = "/v1/text-to-speech/#{voice_id}/stream"
          body = elevenlabs_request_body(text, model: model, speed: speed,
            voice_settings: voice_settings)
          format_param = elevenlabs_output_format(response_format)
          chunks = []

          elevenlabs_connection.post(path) do |req|
            req.headers["Content-Type"] = "application/json"
            req.params["output_format"] = format_param
            req.body = body.to_json
            req.options.on_data = proc do |chunk, _size, env|
              if env.status == 200
                chunk_obj = StreamChunk.new(audio: chunk)
                chunks << chunk
                block&.call(chunk_obj)
              end
            end
          end

          Response.new(
            audio: chunks.join,
            format: response_format.to_sym,
            model: model,
            voice: voice_id
          )
        end

        def elevenlabs_request_body(text, model:, speed:, voice_settings:)
          body = {
            text: text,
            model_id: model
          }

          vs = voice_settings&.dup || {}
          vs[:speed] = speed if speed && (speed - 1.0).abs > Float::EPSILON
          body[:voice_settings] = vs unless vs.empty?

          body
        end

        ELEVENLABS_FORMAT_MAP = {
          "mp3" => "mp3_44100_128",
          "pcm" => "pcm_44100",
          "ulaw" => "ulaw_8000"
        }.freeze

        def elevenlabs_output_format(format)
          ELEVENLABS_FORMAT_MAP[format.to_s] || "mp3_44100_128"
        end

        def elevenlabs_connection
          @elevenlabs_connection ||= Faraday.new(url: elevenlabs_api_base) do |f|
            f.headers["xi-api-key"] = elevenlabs_api_key
            f.adapter Faraday.default_adapter
            f.options.timeout = 120
            f.options.open_timeout = 30
          end
        end

        def elevenlabs_api_key
          key = RubyLLM::Agents.configuration.elevenlabs_api_key
          unless key
            raise ConfigurationError,
              "ElevenLabs API key is required for text-to-speech. " \
              "Set it via: RubyLLM::Agents.configure { |c| c.elevenlabs_api_key = 'xi-...' }"
          end
          key
        end

        def elevenlabs_api_base
          base = RubyLLM::Agents.configuration.elevenlabs_api_base
          (base && !base.empty?) ? base : "https://api.elevenlabs.io"
        end

        # ============================================================
        # Shared error handling
        # ============================================================

        def handle_error_response!(response)
          raise SpeechApiError.new(
            "TTS API request failed (HTTP #{response.status}): #{error_message_from(response)}",
            status: response.status,
            response_body: response.body
          )
        end

        def error_message_from(response)
          parsed = JSON.parse(response.body)
          if parsed.is_a?(Hash)
            parsed.dig("error", "message") || parsed["detail"] || parsed["error"] || response.body
          else
            response.body
          end
        rescue JSON::ParserError
          response.body.to_s[0, 200]
        end
      end
    end
  end
end
