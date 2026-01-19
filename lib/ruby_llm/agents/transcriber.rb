# frozen_string_literal: true

require_relative "transcription_result"
require_relative "transcriber/dsl"
require_relative "transcriber/execution"

module RubyLLM
  module Agents
    # Base class for creating audio transcribers
    #
    # Transcriber provides a DSL for configuring audio-to-text operations with
    # built-in execution tracking, budget controls, and multi-tenancy support.
    #
    # @example Basic usage
    #   class MeetingTranscriber < RubyLLM::Agents::Transcriber
    #     model 'whisper-1'
    #   end
    #
    #   result = MeetingTranscriber.call(audio: "meeting.mp3")
    #   result.text  # => "Hello everyone, welcome to the meeting..."
    #
    # @example With language specification
    #   class SpanishTranscriber < RubyLLM::Agents::Transcriber
    #     model 'gpt-4o-transcribe'
    #     language 'es'
    #
    #     def prompt
    #       "Podcast sobre tecnología y programación"
    #     end
    #   end
    #
    # @example With subtitle output
    #   class SubtitleGenerator < RubyLLM::Agents::Transcriber
    #     model 'whisper-1'
    #     output_format :srt
    #     include_timestamps :segment
    #   end
    #
    #   result = SubtitleGenerator.call(audio: "video.mp4")
    #   result.srt  # => "1\n00:00:00,000 --> 00:00:02,500\nHello\n\n..."
    #
    # @example With post-processing
    #   class TechnicalTranscriber < RubyLLM::Agents::Transcriber
    #     model 'gpt-4o-transcribe'
    #
    #     def prompt
    #       "Technical discussion about Ruby, RubyLLM, API design"
    #     end
    #
    #     def postprocess_text(text)
    #       text
    #         .gsub(/\bRuby L L M\b/i, 'RubyLLM')
    #         .gsub(/\bopen A I\b/i, 'OpenAI')
    #     end
    #   end
    #
    # @api public
    class Transcriber
      extend DSL
      include Execution

      # @!attribute [r] options
      #   @return [Hash] The options passed to the transcriber
      attr_reader :options

      # Creates a new Transcriber instance
      #
      # @param options [Hash] Configuration options
      # @option options [String] :model Override the class-level model
      # @option options [String] :language Override the class-level language
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(**options)
        @options = options
        @tenant_id = nil
        @tenant_object = nil
        @tenant_config = nil
      end

      class << self
        # Executes the transcriber with the given audio
        #
        # @param audio [String, File, IO] Audio file path, URL, File object, or binary data
        # @param format [Symbol, nil] Audio format hint when passing binary data (:mp3, :wav, etc.)
        # @param options [Hash] Additional options
        # @option options [String] :model Override the class-level model
        # @option options [String] :language Override the class-level language
        # @option options [Object] :tenant Tenant for multi-tenancy
        # @return [TranscriptionResult] The transcription result
        # @raise [ArgumentError] If audio input is invalid
        #
        # @example From file path
        #   MeetingTranscriber.call(audio: "meeting.mp3")
        #
        # @example From URL
        #   MeetingTranscriber.call(audio: "https://example.com/audio.mp3")
        #
        # @example From File object
        #   MeetingTranscriber.call(audio: File.open("meeting.mp3"))
        #
        # @example With options
        #   MeetingTranscriber.call(audio: "meeting.mp3", language: "es", model: "gpt-4o-transcribe")
        def call(audio:, format: nil, **options)
          new(**options).call(audio: audio, format: format)
        end
      end
    end
  end
end
