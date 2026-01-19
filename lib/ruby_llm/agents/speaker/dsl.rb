# frozen_string_literal: true

module RubyLLM
  module Agents
    class Speaker
      # Class-level DSL for configuring speakers
      #
      # Provides methods for setting provider, model, voice,
      # and other text-to-speech options.
      module DSL
        # @!group Configuration DSL

        # Sets or returns the TTS provider for this speaker class
        #
        # @param value [Symbol, nil] The provider (:openai, :elevenlabs, :google, :polly)
        # @return [Symbol] The current provider setting
        # @example
        #   provider :openai
        #   provider :elevenlabs
        def provider(value = nil)
          @provider = value if value
          @provider || inherited_or_default(:provider, RubyLLM::Agents.configuration.default_tts_provider)
        end

        # Sets or returns the TTS model for this speaker class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "tts-1-hd"
        #   model "eleven_multilingual_v2"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_tts_model)
        end

        # Sets or returns the voice for this speaker class
        #
        # @param value [String, nil] The voice name or identifier
        # @return [String] The current voice setting
        # @example
        #   voice "nova"
        #   voice "Rachel"
        def voice(value = nil)
          @voice = value if value
          @voice || inherited_or_default(:voice, RubyLLM::Agents.configuration.default_tts_voice)
        end

        # Sets or returns the voice ID for custom/cloned voices
        #
        # @param value [String, nil] The voice ID
        # @return [String, nil] The current voice ID setting
        # @example
        #   voice_id "abc123xyz"
        def voice_id(value = nil)
          @voice_id = value if value
          @voice_id || inherited_or_default(:voice_id, nil)
        end

        # Sets or returns the speech speed
        #
        # @param value [Float, nil] Speed multiplier (0.25 to 4.0 for OpenAI)
        # @return [Float] The current speed setting
        # @example
        #   speed 1.0
        #   speed 1.5  # Faster
        #   speed 0.8  # Slower
        def speed(value = nil)
          @speed = value if value
          @speed || inherited_or_default(:speed, 1.0)
        end

        # Sets or returns the output audio format
        #
        # @param value [Symbol, nil] Output format (:mp3, :opus, :aac, :flac, :wav, :pcm)
        # @return [Symbol] The current output format
        # @example
        #   output_format :mp3
        #   output_format :wav
        def output_format(value = nil)
          @output_format = value if value
          @output_format || inherited_or_default(:output_format, :mp3)
        end

        # Sets or returns the version string for cache invalidation
        #
        # @param value [String, nil] Version string
        # @return [String] The current version
        # @example
        #   version "2.0"
        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, "1.0")
        end

        # Sets or returns the description for this speaker class
        #
        # @param value [String, nil] The description text
        # @return [String, nil] The current description
        # @example
        #   description "Narrates articles with professional voice"
        def description(value = nil)
          @description = value if value
          @description || inherited_or_default(:description, nil)
        end

        # @!endgroup

        # @!group Voice Settings DSL

        # Configures voice settings (ElevenLabs specific)
        #
        # @yield Block for configuring voice settings
        # @return [VoiceSettings] The voice settings configuration
        # @example
        #   voice_settings do
        #     stability 0.5
        #     similarity_boost 0.75
        #     style 0.5
        #     speaker_boost true
        #   end
        def voice_settings(&block)
          @voice_settings ||= VoiceSettings.new
          @voice_settings.instance_eval(&block) if block_given?
          @voice_settings
        end

        # Returns voice settings configuration
        #
        # @return [VoiceSettings, nil] The voice settings
        def voice_settings_config
          @voice_settings || inherited_or_default(:voice_settings_config, nil)
        end

        # @!endgroup

        # @!group Streaming DSL

        # Sets or returns whether streaming is enabled
        #
        # @param value [Boolean, nil] Enable streaming
        # @return [Boolean] The current streaming setting
        # @example
        #   streaming true
        def streaming(value = nil)
          @streaming = value unless value.nil?
          instance_variable_defined?(:@streaming) ? @streaming : inherited_or_default(:streaming, false)
        end

        # Returns whether streaming is enabled
        #
        # @return [Boolean] true if streaming is enabled
        def streaming?
          streaming
        end

        # @!endgroup

        # @!group SSML DSL

        # Sets or returns whether SSML input is enabled
        #
        # @param value [Boolean, nil] Enable SSML
        # @return [Boolean] The current SSML setting
        # @example
        #   ssml_enabled true
        def ssml_enabled(value = nil)
          @ssml_enabled = value unless value.nil?
          instance_variable_defined?(:@ssml_enabled) ? @ssml_enabled : inherited_or_default(:ssml_enabled, false)
        end

        # Returns whether SSML is enabled
        #
        # @return [Boolean] true if SSML is enabled
        def ssml_enabled?
          ssml_enabled
        end

        # @!endgroup

        # @!group Lexicon DSL

        # Configures pronunciation lexicon
        #
        # @yield Block for configuring pronunciations
        # @return [Lexicon] The lexicon configuration
        # @example
        #   lexicon do
        #     pronounce 'RubyLLM', 'ruby L L M'
        #     pronounce 'PostgreSQL', 'post-gres-Q-L'
        #     pronounce 'nginx', 'engine-X'
        #   end
        def lexicon(&block)
          @lexicon ||= Lexicon.new
          @lexicon.instance_eval(&block) if block_given?
          @lexicon
        end

        # Returns lexicon configuration
        #
        # @return [Lexicon, nil] The lexicon
        def lexicon_config
          @lexicon || inherited_or_default(:lexicon_config, nil)
        end

        # @!endgroup

        # @!group Caching DSL

        # Enables caching for this speaker with explicit TTL
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache_for 30.days
        def cache_for(ttl)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this speaker
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          @cache_enabled || false
        end

        # Returns the cache TTL for this speaker
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || 1.hour
        end

        # @!endgroup

        # @!group Reliability DSL

        # Configures reliability options
        #
        # @yield Block for configuring reliability options
        # @return [void]
        # @example
        #   reliability do
        #     retries max: 3, backoff: :exponential
        #     fallback_provider :openai, voice: 'nova'
        #     total_timeout 120
        #   end
        def reliability(&block)
          @reliability_config ||= ReliabilityConfig.new
          @reliability_config.instance_eval(&block) if block_given?
          @reliability_config
        end

        # Returns reliability configuration
        #
        # @return [ReliabilityConfig, nil] The reliability configuration
        def reliability_config
          @reliability_config || inherited_or_default(:reliability_config, nil)
        end

        # @!endgroup

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        # Configuration class for voice settings (ElevenLabs)
        class VoiceSettings
          attr_accessor :stability_value, :similarity_boost_value, :style_value, :speaker_boost_value

          def initialize
            @stability_value = 0.5
            @similarity_boost_value = 0.75
            @style_value = 0.0
            @speaker_boost_value = true
          end

          def stability(value)
            @stability_value = value
          end

          def similarity_boost(value)
            @similarity_boost_value = value
          end

          def style(value)
            @style_value = value
          end

          def speaker_boost(value)
            @speaker_boost_value = value
          end

          def to_h
            {
              stability: stability_value,
              similarity_boost: similarity_boost_value,
              style: style_value,
              use_speaker_boost: speaker_boost_value
            }
          end
        end

        # Configuration class for pronunciation lexicon
        class Lexicon
          attr_reader :pronunciations

          def initialize
            @pronunciations = {}
          end

          def pronounce(word, pronunciation)
            @pronunciations[word] = pronunciation
          end

          def apply(text)
            result = text.dup
            pronunciations.each do |word, pronunciation|
              result.gsub!(/\b#{Regexp.escape(word)}\b/i, pronunciation)
            end
            result
          end

          def to_h
            pronunciations.dup
          end
        end

        # Configuration class for reliability options
        class ReliabilityConfig
          attr_accessor :max_retries, :backoff, :fallback_provider_config, :total_timeout_seconds

          def initialize
            @max_retries = 3
            @backoff = :exponential
            @fallback_provider_config = nil
            @total_timeout_seconds = nil
          end

          def retries(max: 3, backoff: :exponential)
            @max_retries = max
            @backoff = backoff
          end

          def fallback_provider(provider, **options)
            @fallback_provider_config = { provider: provider, **options }
          end

          def total_timeout(seconds)
            @total_timeout_seconds = seconds
          end

          def to_h
            {
              max_retries: max_retries,
              backoff: backoff,
              fallback_provider: fallback_provider_config,
              total_timeout: total_timeout_seconds
            }
          end
        end
      end
    end
  end
end
