# frozen_string_literal: true

require_relative "speech_result"
require_relative "speaker/dsl"
require_relative "speaker/execution"

module RubyLLM
  module Agents
    # Base class for creating text-to-speech speakers
    #
    # Speaker provides a DSL for configuring text-to-audio operations with
    # built-in execution tracking, budget controls, and multi-tenancy support.
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
    # @example With ElevenLabs and voice settings
    #   class PremiumNarrator < RubyLLM::Agents::Speaker
    #     provider :elevenlabs
    #     model 'eleven_multilingual_v2'
    #     voice 'Rachel'
    #
    #     voice_settings do
    #       stability 0.5
    #       similarity_boost 0.75
    #       style 0.5
    #       speaker_boost true
    #     end
    #   end
    #
    # @example With pronunciation lexicon
    #   class TechnicalNarrator < RubyLLM::Agents::Speaker
    #     provider :openai
    #     voice 'nova'
    #
    #     lexicon do
    #       pronounce 'RubyLLM', 'ruby L L M'
    #       pronounce 'PostgreSQL', 'post-gres-Q-L'
    #       pronounce 'nginx', 'engine-X'
    #     end
    #   end
    #
    # @example With streaming
    #   class StreamingNarrator < RubyLLM::Agents::Speaker
    #     provider :elevenlabs
    #     voice 'Rachel'
    #     streaming true
    #   end
    #
    #   StreamingNarrator.call(text: "Long article...") do |chunk|
    #     audio_player.play(chunk.audio)
    #   end
    #
    # @api public
    class Speaker
      extend DSL
      include Execution

      # @!attribute [r] options
      #   @return [Hash] The options passed to the speaker
      attr_reader :options

      # Creates a new Speaker instance
      #
      # @param options [Hash] Configuration options
      # @option options [Symbol] :provider Override the class-level provider
      # @option options [String] :model Override the class-level model
      # @option options [String] :voice Override the class-level voice
      # @option options [String] :voice_id Override the class-level voice ID
      # @option options [Float] :speed Override the class-level speed
      # @option options [Symbol] :format Override the class-level output format
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(**options)
        @options = options
        @tenant_id = nil
        @tenant_object = nil
        @tenant_config = nil
      end

      class << self
        # Executes the speaker with the given text
        #
        # @param text [String] Text to convert to speech
        # @param options [Hash] Additional options
        # @option options [Symbol] :provider Override the class-level provider
        # @option options [String] :model Override the class-level model
        # @option options [String] :voice Override the class-level voice
        # @option options [Float] :speed Override the class-level speed
        # @option options [Symbol] :format Override the output format
        # @option options [Object] :tenant Tenant for multi-tenancy
        # @yield [audio_chunk] Called for each audio chunk when streaming
        # @return [SpeechResult] The speech result
        # @raise [ArgumentError] If text is invalid
        #
        # @example Basic usage
        #   ArticleNarrator.call(text: "Hello world")
        #
        # @example With options
        #   ArticleNarrator.call(text: "Hello", voice: "alloy", speed: 1.2)
        #
        # @example Streaming
        #   ArticleNarrator.call(text: "Long article...") do |chunk|
        #     stream.write(chunk.audio)
        #   end
        def call(text:, **options, &block)
          new(**options).call(text: text, &block)
        end

        # Streams the speaker output
        #
        # Forces streaming mode regardless of class configuration.
        #
        # @param text [String] Text to convert to speech
        # @param options [Hash] Additional options
        # @yield [audio_chunk] Called for each audio chunk
        # @return [SpeechResult] The speech result
        def stream(text:, **options, &block)
          raise ArgumentError, "A block is required for streaming" unless block_given?

          instance = new(**options.merge(streaming: true))
          instance.call(text: text, &block)
        end
      end
    end
  end
end
