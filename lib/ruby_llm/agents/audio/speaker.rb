# frozen_string_literal: true

require "digest"
require_relative "../results/speech_result"

module RubyLLM
  module Agents
    # Base class for creating text-to-speech speakers using the middleware pipeline
    #
    # Speaker provides a DSL for configuring text-to-audio operations with
    # built-in execution tracking, budget controls, and multi-tenancy support
    # through the middleware pipeline.
    #
    # @example Basic usage
    #   class ArticleNarrator < RubyLLM::Agents::Speaker
    #     provider :openai
    #     model 'tts-1-hd'
    #     voice 'nova'
    #   end
    #
    #   result = ArticleNarrator.call(text: "Hello world")
    #   result.audio       # => Binary audio data
    #   result.save_to("output.mp3")
    #
    # @example With voice settings
    #   class PremiumNarrator < RubyLLM::Agents::Speaker
    #     provider :elevenlabs
    #     model 'eleven_multilingual_v2'
    #     voice 'Rachel'
    #
    #     voice_settings do
    #       stability 0.5
    #       similarity_boost 0.75
    #     end
    #   end
    #
    # @api public
    class Speaker < BaseAgent
      class << self
        # Returns the agent type for speakers
        #
        # @return [Symbol] :audio
        def agent_type
          :audio
        end

        # @!group Speaker-specific DSL

        # Sets or returns the TTS provider
        #
        # @param value [Symbol, nil] The provider (:openai, :elevenlabs, :google, :polly)
        # @return [Symbol] The current provider setting
        def provider(value = nil)
          @provider = value if value
          return @provider if defined?(@provider) && @provider

          if superclass.respond_to?(:agent_type) && superclass.agent_type == :audio
            superclass.provider
          else
            default_tts_provider
          end
        end

        # Sets or returns the TTS model
        #
        # @param value [String, nil] The model identifier
        # @return [String] The current model setting
        def model(value = nil)
          @model = value if value
          return @model if defined?(@model) && @model

          if superclass.respond_to?(:agent_type) && superclass.agent_type == :audio
            superclass.model
          else
            default_tts_model
          end
        end

        # Sets or returns the voice name
        #
        # @param value [String, nil] The voice name
        # @return [String] The current voice setting
        def voice(value = nil)
          @voice = value if value
          @voice || inherited_or_default(:voice, default_tts_voice)
        end

        # Sets or returns the voice ID (for custom/cloned voices)
        #
        # @param value [String, nil] The voice ID
        # @return [String, nil] The current voice ID
        def voice_id(value = nil)
          @voice_id = value if value
          @voice_id || inherited_or_default(:voice_id, nil)
        end

        # Sets or returns the speech speed
        #
        # @param value [Float, nil] Speed multiplier
        # @return [Float] The current speed
        def speed(value = nil)
          @speed = value if value
          @speed || inherited_or_default(:speed, 1.0)
        end

        # Sets or returns the output format
        #
        # @param value [Symbol, nil] Format (:mp3, :wav, :ogg, etc.)
        # @return [Symbol] The current format
        def output_format(value = nil)
          @output_format = value if value
          @output_format || inherited_or_default(:output_format, :mp3)
        end

        # Sets or returns streaming mode
        #
        # @param value [Boolean, nil] Enable streaming
        # @return [Boolean] The current streaming setting
        def streaming(value = nil)
          @streaming = value unless value.nil?
          instance_variable_defined?(:@streaming) ? @streaming : inherited_or_default(:streaming, false)
        end

        def streaming?
          streaming
        end

        # @!endgroup

        # @!group Voice Settings DSL

        # Configures voice settings (ElevenLabs specific)
        #
        # @yield Block for configuring voice settings
        # @return [VoiceSettings] The voice settings configuration
        def voice_settings(&block)
          @voice_settings ||= VoiceSettings.new
          @voice_settings.instance_eval(&block) if block_given?
          @voice_settings
        end

        def voice_settings_config
          @voice_settings || inherited_or_default(:voice_settings_config, nil)
        end

        # @!endgroup

        # @!group Lexicon DSL

        # Configures pronunciation lexicon
        #
        # @yield Block for configuring pronunciations
        # @return [Lexicon] The lexicon configuration
        def lexicon(&block)
          @lexicon ||= Lexicon.new
          @lexicon.instance_eval(&block) if block_given?
          @lexicon
        end

        def lexicon_config
          @lexicon || inherited_or_default(:lexicon_config, nil)
        end

        # @!endgroup

        # Factory method to instantiate and execute speaker
        #
        # @param text [String] Text to convert to speech
        # @param options [Hash] Additional options
        # @yield [audio_chunk] Called for each audio chunk when streaming
        # @return [SpeechResult] The speech result
        def call(text:, **options, &block)
          new(text: text, **options).call(&block)
        end

        # Streams the speaker output
        #
        # @param text [String] Text to convert to speech
        # @param options [Hash] Additional options
        # @yield [audio_chunk] Called for each audio chunk
        # @return [SpeechResult] The speech result
        def stream(text:, **options, &block)
          raise ArgumentError, "A block is required for streaming" unless block_given?

          instance = new(text: text, **options.merge(streaming: true))
          instance.call(&block)
        end

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        def default_tts_provider
          RubyLLM::Agents.configuration.default_tts_provider
        rescue StandardError
          :openai
        end

        def default_tts_model
          RubyLLM::Agents.configuration.default_tts_model
        rescue StandardError
          "tts-1"
        end

        def default_tts_voice
          RubyLLM::Agents.configuration.default_tts_voice
        rescue StandardError
          "nova"
        end
      end

      # Voice settings configuration class
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

      # Pronunciation lexicon class
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

      # @!attribute [r] text
      #   @return [String] Text to convert to speech
      attr_reader :text

      # Creates a new Speaker instance
      #
      # @param text [String] Text to convert to speech
      # @param options [Hash] Configuration options
      def initialize(text:, **options)
        @text = text
        @streaming_block = nil
        @runtime_streaming = options.delete(:streaming)

        # Set model to TTS model if not specified
        options[:model] ||= self.class.model

        super(**options)
      end

      # Executes the speech through the middleware pipeline
      #
      # @yield [audio_chunk] Called for each audio chunk when streaming
      # @return [SpeechResult] The speech result
      def call(&block)
        @streaming_block = block
        context = build_context
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # The input for this speech operation
      #
      # @return [String] The text being converted
      def user_prompt
        text
      end

      # Core speech execution
      #
      # This is called by the Pipeline::Executor after middleware
      # has been applied. Only contains the speech API logic.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the SpeechResult
      def execute(context)
        execution_started_at = Time.current

        validate_text_input!
        processed_text = apply_lexicon(text)

        # Execute speech synthesis
        result = execute_speech(processed_text)

        execution_completed_at = Time.current
        duration_ms = ((execution_completed_at - execution_started_at) * 1000).to_i

        # Update context
        context.input_tokens = 0
        context.output_tokens = 0
        context.total_cost = calculate_cost(result)

        # Build final result
        context.output = build_result(
          result,
          text,
          started_at: context.started_at || execution_started_at,
          completed_at: execution_completed_at,
          duration_ms: duration_ms,
          tenant_id: context.tenant_id
        )
      end

      # Generates the cache key for this speech
      #
      # @return [String] Cache key
      def agent_cache_key
        components = [
          "ruby_llm_agents",
          "speech",
          self.class.name,
          self.class.version,
          resolved_provider,
          resolved_model,
          resolved_voice,
          resolved_voice_id,
          resolved_speed,
          resolved_output_format,
          Digest::SHA256.hexdigest(text)
        ].compact

        components.join("/")
      end

      private

      # Builds context for pipeline execution
      #
      # @return [Pipeline::Context] The context object
      def build_context
        Pipeline::Context.new(
          input: user_prompt,
          agent_class: self.class,
          agent_instance: self,
          model: resolved_model,
          tenant: @options[:tenant],
          skip_cache: @options[:skip_cache] || streaming_enabled?,
          stream_block: (@streaming_block if streaming_enabled?)
        )
      end

      # Validates text input
      def validate_text_input!
        raise ArgumentError, "text is required" if text.nil?
        raise ArgumentError, "text must be a String, got #{text.class}" unless text.is_a?(String)
        raise ArgumentError, "text cannot be empty" if text.empty?
      end

      # Applies lexicon pronunciations
      def apply_lexicon(text)
        lexicon = self.class.lexicon_config
        return text unless lexicon

        lexicon.apply(text)
      end

      # Executes speech synthesis
      def execute_speech(processed_text)
        speak_options = build_speak_options

        if streaming_enabled? && @streaming_block
          execute_streaming_speech(processed_text, speak_options)
        else
          execute_standard_speech(processed_text, speak_options)
        end
      end

      # Executes standard (non-streaming) speech synthesis
      def execute_standard_speech(text, options)
        response = RubyLLM.speak(text, **options)

        {
          audio: response.audio,
          duration: response.respond_to?(:duration) ? response.duration : nil,
          format: resolved_output_format,
          provider: resolved_provider,
          model: resolved_model,
          voice: resolved_voice,
          characters: text.length,
          raw_response: response
        }
      end

      # Executes streaming speech synthesis
      def execute_streaming_speech(text, options)
        audio_chunks = []

        RubyLLM.speak(text, **options.merge(stream: true)) do |chunk|
          audio_chunks << chunk.audio if chunk.respond_to?(:audio)
          @streaming_block.call(chunk) if @streaming_block
        end

        {
          audio: audio_chunks.join,
          duration: nil,
          format: resolved_output_format,
          provider: resolved_provider,
          model: resolved_model,
          voice: resolved_voice,
          characters: text.length,
          streamed: true
        }
      end

      # Builds options for RubyLLM.speak
      def build_speak_options
        options = {
          model: resolved_model,
          voice: resolved_voice_id || resolved_voice
        }

        speed = resolved_speed
        options[:speed] = speed if speed && speed != 1.0
        options[:response_format] = resolved_output_format.to_s

        if resolved_provider == :elevenlabs
          voice_settings = self.class.voice_settings_config
          options[:voice_settings] = voice_settings.to_h if voice_settings
        end

        options
      end

      # Builds the final result object
      def build_result(raw_result, original_text, started_at:, completed_at:, duration_ms:, tenant_id:)
        SpeechResult.new(
          audio: raw_result[:audio],
          duration: raw_result[:duration],
          format: raw_result[:format],
          file_size: raw_result[:audio]&.bytesize,
          characters: raw_result[:characters],
          text_length: original_text.length,
          provider: raw_result[:provider],
          model_id: raw_result[:model],
          voice_id: resolved_voice_id,
          voice_name: raw_result[:voice],
          duration_ms: duration_ms,
          started_at: started_at,
          completed_at: completed_at,
          total_cost: calculate_cost(raw_result),
          status: :success,
          tenant_id: tenant_id
        )
      end

      # Calculates cost for speech synthesis
      def calculate_cost(raw_result)
        characters = raw_result[:characters] || 0

        if raw_result[:raw_response].respond_to?(:cost) && raw_result[:raw_response].cost
          return raw_result[:raw_response].cost
        end

        provider = raw_result[:provider]
        model_name = raw_result[:model].to_s

        price_per_1k_chars = case provider
                            when :openai
                              model_name.include?("hd") ? 0.030 : 0.015
                            when :elevenlabs
                              0.30
                            when :google
                              0.016
                            when :polly
                              0.016
                            else
                              0.015
                            end

        (characters / 1000.0) * price_per_1k_chars
      end

      # Resolves the provider to use
      def resolved_provider
        @options[:provider] || self.class.provider
      end

      # Resolves the model to use
      def resolved_model
        @model || self.class.model
      end

      # Resolves the voice to use
      def resolved_voice
        @options[:voice] || self.class.voice
      end

      # Resolves the voice ID to use
      def resolved_voice_id
        @options[:voice_id] || self.class.voice_id
      end

      # Resolves the speed to use
      def resolved_speed
        @options[:speed] || self.class.speed
      end

      # Resolves the output format to use
      def resolved_output_format
        @options[:format] || self.class.output_format
      end

      # Returns whether streaming is enabled
      def streaming_enabled?
        @runtime_streaming || self.class.streaming?
      end
    end
  end
end
