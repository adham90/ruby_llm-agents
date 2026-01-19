# frozen_string_literal: true

require "base64"

module RubyLLM
  module Agents
    # Result object for text-to-speech operations
    #
    # Wraps audio output with metadata about the operation including
    # duration, format, cost, and utility methods for saving audio.
    #
    # @example Basic usage
    #   result = ArticleNarrator.call(text: "Hello world")
    #   result.audio       # => Binary audio data
    #   result.duration    # => 1.5 (seconds)
    #   result.total_cost  # => 0.0003
    #
    # @example Saving audio
    #   result.save_to("/path/to/output.mp3")
    #
    # @example Base64 encoding
    #   result.to_base64   # => "//uQx..."
    #
    # @api public
    class SpeechResult
      # @!group Audio Content

      # @!attribute [r] audio
      #   @return [String, nil] Binary audio data
      attr_reader :audio

      # @!attribute [r] audio_url
      #   @return [String, nil] URL if audio was stored remotely
      attr_reader :audio_url

      # @!attribute [r] audio_key
      #   @return [String, nil] Storage key if stored
      attr_reader :audio_key

      # @!attribute [r] audio_path
      #   @return [String, nil] Local file path if saved
      attr_reader :audio_path

      # @!endgroup

      # @!group Audio Metadata

      # @!attribute [r] duration
      #   @return [Float, nil] Duration in seconds
      attr_reader :duration

      # @!attribute [r] format
      #   @return [Symbol, nil] Audio format (:mp3, :wav, :ogg, etc.)
      attr_reader :format

      # @!attribute [r] sample_rate
      #   @return [Integer, nil] Sample rate in Hz
      attr_reader :sample_rate

      # @!attribute [r] bitrate
      #   @return [Integer, nil] Bitrate in kbps
      attr_reader :bitrate

      # @!attribute [r] file_size
      #   @return [Integer, nil] Size in bytes
      attr_reader :file_size

      # @!endgroup

      # @!group Input Metadata

      # @!attribute [r] characters
      #   @return [Integer, nil] Character count (for billing)
      attr_reader :characters

      # @!attribute [r] text_length
      #   @return [Integer, nil] Original text length
      attr_reader :text_length

      # @!endgroup

      # @!group Voice Info

      # @!attribute [r] provider
      #   @return [Symbol, nil] Provider (:openai, :elevenlabs, :google, :polly)
      attr_reader :provider

      # @!attribute [r] model_id
      #   @return [String, nil] Model identifier
      attr_reader :model_id

      # @!attribute [r] voice_id
      #   @return [String, nil] Voice identifier
      attr_reader :voice_id

      # @!attribute [r] voice_name
      #   @return [String, nil] Voice display name
      attr_reader :voice_name

      # @!endgroup

      # @!group Timing

      # @!attribute [r] duration_ms
      #   @return [Integer, nil] Execution duration in milliseconds
      attr_reader :duration_ms

      # @!attribute [r] started_at
      #   @return [Time, nil] When execution started
      attr_reader :started_at

      # @!attribute [r] completed_at
      #   @return [Time, nil] When execution completed
      attr_reader :completed_at

      # @!endgroup

      # @!group Cost & Usage

      # @!attribute [r] total_cost
      #   @return [Float, nil] Total cost in USD
      attr_reader :total_cost

      # @!endgroup

      # @!group Status

      # @!attribute [r] status
      #   @return [Symbol] Status (:success, :partial, :failed)
      attr_reader :status

      # @!endgroup

      # @!group Multi-tenancy

      # @!attribute [r] tenant_id
      #   @return [String, nil] Tenant identifier if multi-tenancy enabled
      attr_reader :tenant_id

      # @!endgroup

      # @!group Error

      # @!attribute [r] error_class
      #   @return [String, nil] Exception class name if failed
      attr_reader :error_class

      # @!attribute [r] error_message
      #   @return [String, nil] Exception message if failed
      attr_reader :error_message

      # @!endgroup

      # Creates a new SpeechResult instance
      #
      # @param attributes [Hash] Result attributes
      # @option attributes [String] :audio Binary audio data
      # @option attributes [String] :audio_url URL if stored remotely
      # @option attributes [String] :audio_key Storage key
      # @option attributes [String] :audio_path Local file path
      # @option attributes [Float] :duration Duration in seconds
      # @option attributes [Symbol] :format Audio format
      # @option attributes [Integer] :sample_rate Sample rate in Hz
      # @option attributes [Integer] :bitrate Bitrate in kbps
      # @option attributes [Integer] :file_size Size in bytes
      # @option attributes [Integer] :characters Character count
      # @option attributes [Integer] :text_length Original text length
      # @option attributes [Symbol] :provider Provider name
      # @option attributes [String] :model_id Model identifier
      # @option attributes [String] :voice_id Voice identifier
      # @option attributes [String] :voice_name Voice display name
      # @option attributes [Integer] :duration_ms Execution duration
      # @option attributes [Time] :started_at Start time
      # @option attributes [Time] :completed_at Completion time
      # @option attributes [Float] :total_cost Cost in USD
      # @option attributes [Symbol] :status Status
      # @option attributes [String] :tenant_id Tenant identifier
      # @option attributes [String] :error_class Error class
      # @option attributes [String] :error_message Error message
      def initialize(attributes = {})
        # Audio content
        @audio = attributes[:audio]
        @audio_url = attributes[:audio_url]
        @audio_key = attributes[:audio_key]
        @audio_path = attributes[:audio_path]

        # Audio metadata
        @duration = attributes[:duration]
        @format = attributes[:format]
        @sample_rate = attributes[:sample_rate]
        @bitrate = attributes[:bitrate]
        @file_size = attributes[:file_size] || @audio&.bytesize

        # Input metadata
        @characters = attributes[:characters]
        @text_length = attributes[:text_length]

        # Voice info
        @provider = attributes[:provider]
        @model_id = attributes[:model_id]
        @voice_id = attributes[:voice_id]
        @voice_name = attributes[:voice_name]

        # Timing
        @duration_ms = attributes[:duration_ms]
        @started_at = attributes[:started_at]
        @completed_at = attributes[:completed_at]

        # Cost & usage
        @total_cost = attributes[:total_cost]

        # Status
        @status = attributes[:status] || :success

        # Multi-tenancy
        @tenant_id = attributes[:tenant_id]

        # Error
        @error_class = attributes[:error_class]
        @error_message = attributes[:error_message]
      end

      # Returns whether the speech generation succeeded
      #
      # @return [Boolean] true if no error occurred
      def success?
        error_class.nil? && status == :success
      end

      # Returns whether the speech generation failed
      #
      # @return [Boolean] true if an error occurred
      def error?
        !success?
      end

      # Saves the audio to a file
      #
      # @param path [String] File path to save to
      # @return [String] The path where audio was saved
      # @raise [StandardError] If audio data is not available
      def save_to(path)
        raise StandardError, "No audio data available" unless audio

        File.binwrite(path, audio)
        @audio_path = path
        path
      end

      # Returns the audio as a Base64-encoded string
      #
      # @return [String, nil] Base64-encoded audio or nil if no audio
      def to_base64
        return nil unless audio

        Base64.strict_encode64(audio)
      end

      # Returns the audio as a data URI
      #
      # @return [String, nil] Data URI or nil if no audio
      def to_data_uri
        return nil unless audio

        mime_type = mime_type_for_format
        "data:#{mime_type};base64,#{to_base64}"
      end

      # Returns words per second of generated audio
      #
      # @return [Float, nil] Words per second or nil if not calculable
      def words_per_second
        return nil unless text_length && duration && duration > 0

        # Rough estimate: average word length is 5 characters
        word_count = text_length / 5.0
        word_count / duration
      end

      # Converts the result to a hash
      #
      # @return [Hash] All result data as a hash
      def to_h
        {
          audio_url: audio_url,
          audio_key: audio_key,
          audio_path: audio_path,
          duration: duration,
          format: format,
          sample_rate: sample_rate,
          bitrate: bitrate,
          file_size: file_size,
          characters: characters,
          text_length: text_length,
          provider: provider,
          model_id: model_id,
          voice_id: voice_id,
          voice_name: voice_name,
          duration_ms: duration_ms,
          started_at: started_at,
          completed_at: completed_at,
          total_cost: total_cost,
          status: status,
          tenant_id: tenant_id,
          error_class: error_class,
          error_message: error_message
          # Note: audio binary data excluded for serialization safety
        }
      end

      private

      # Returns MIME type for the audio format
      #
      # @return [String] MIME type
      def mime_type_for_format
        case format
        when :mp3
          "audio/mpeg"
        when :wav
          "audio/wav"
        when :ogg
          "audio/ogg"
        when :flac
          "audio/flac"
        when :aac
          "audio/aac"
        when :opus
          "audio/opus"
        when :pcm
          "audio/pcm"
        else
          "audio/mpeg" # Default to mp3
        end
      end
    end
  end
end
