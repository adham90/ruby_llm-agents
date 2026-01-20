# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result object for transcription operations
    #
    # Wraps transcription output with metadata about the operation including
    # audio duration, timing, cost, and utility methods for output formatting.
    #
    # @example Basic transcription
    #   result = MeetingTranscriber.call(audio: "meeting.mp3")
    #   result.text           # => "Hello everyone..."
    #   result.audio_duration # => 60.5
    #   result.total_cost     # => 0.006
    #
    # @example With segments
    #   result = SubtitleTranscriber.call(audio: "video.mp4")
    #   result.segments       # => [{ start: 0.0, end: 2.5, text: "Hello" }, ...]
    #   result.srt            # => "1\n00:00:00,000 --> 00:00:02,500\nHello\n\n..."
    #   result.vtt            # => "WEBVTT\n\n00:00:00.000 --> 00:00:02.500\nHello\n\n..."
    #
    # @example Speaker diarization
    #   result = InterviewTranscriber.call(audio: "interview.mp3")
    #   result.speakers          # => ["Interviewer", "Guest"]
    #   result.speaker_segments  # => { "Interviewer" => [...], "Guest" => [...] }
    #
    # @api public
    class TranscriptionResult
      # @!group Content

      # @!attribute [r] text
      #   @return [String, nil] The full transcription text
      attr_reader :text

      # @!attribute [r] segments
      #   @return [Array<Hash>, nil] Array of timed segments with :start, :end, :text keys
      attr_reader :segments

      # @!attribute [r] words
      #   @return [Array<Hash>, nil] Array of timed words (if word-level timestamps available)
      attr_reader :words

      # @!endgroup

      # @!group Speaker Diarization

      # @!attribute [r] speakers
      #   @return [Array<String>, nil] Identified speaker names/labels
      attr_reader :speakers

      # @!attribute [r] speaker_segments
      #   @return [Hash<String, Array>, nil] Segments grouped by speaker
      attr_reader :speaker_segments

      # @!endgroup

      # @!group Audio Metadata

      # @!attribute [r] audio_duration
      #   @return [Float, nil] Duration of audio in seconds
      attr_reader :audio_duration

      # @!attribute [r] audio_format
      #   @return [String, nil] Detected audio format (mp3, wav, etc.)
      attr_reader :audio_format

      # @!attribute [r] audio_channels
      #   @return [Integer, nil] Number of audio channels (1=mono, 2=stereo)
      attr_reader :audio_channels

      # @!attribute [r] audio_sample_rate
      #   @return [Integer, nil] Sample rate in Hz
      attr_reader :audio_sample_rate

      # @!endgroup

      # @!group Language

      # @!attribute [r] language
      #   @return [String, nil] Language code (ISO 639-1) that was requested
      attr_reader :language

      # @!attribute [r] detected_language
      #   @return [String, nil] Auto-detected language code
      attr_reader :detected_language

      # @!attribute [r] language_confidence
      #   @return [Float, nil] Confidence score for language detection (0.0-1.0)
      attr_reader :language_confidence

      # @!endgroup

      # @!group Model Info

      # @!attribute [r] model_id
      #   @return [String, nil] The transcription model used
      attr_reader :model_id

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

      # @!attribute [r] audio_minutes
      #   @return [Float, nil] Billable audio minutes
      attr_reader :audio_minutes

      # @!endgroup

      # @!group Quality

      # @!attribute [r] confidence
      #   @return [Float, nil] Overall confidence score (0.0-1.0)
      attr_reader :confidence

      # @!endgroup

      # @!group Status

      # @!attribute [r] status
      #   @return [Symbol] Status (:success, :partial, :failed)
      attr_reader :status

      # @!attribute [r] chunks
      #   @return [Array<TranscriptionResult>, nil] Individual chunk results for long audio
      attr_reader :chunks

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

      # Creates a new TranscriptionResult instance
      #
      # @param attributes [Hash] Result attributes
      # @option attributes [String] :text The transcription text
      # @option attributes [Array<Hash>] :segments Timed segments
      # @option attributes [Array<Hash>] :words Timed words
      # @option attributes [Array<String>] :speakers Speaker names
      # @option attributes [Hash] :speaker_segments Segments by speaker
      # @option attributes [Float] :audio_duration Audio duration in seconds
      # @option attributes [String] :audio_format Audio format
      # @option attributes [Integer] :audio_channels Number of channels
      # @option attributes [Integer] :audio_sample_rate Sample rate in Hz
      # @option attributes [String] :language Requested language
      # @option attributes [String] :detected_language Detected language
      # @option attributes [Float] :language_confidence Language confidence
      # @option attributes [String] :model_id Model used
      # @option attributes [Integer] :duration_ms Execution duration
      # @option attributes [Time] :started_at Start time
      # @option attributes [Time] :completed_at Completion time
      # @option attributes [Float] :total_cost Cost in USD
      # @option attributes [Float] :audio_minutes Billable minutes
      # @option attributes [Float] :confidence Overall confidence
      # @option attributes [Symbol] :status Status
      # @option attributes [Array] :chunks Chunk results
      # @option attributes [String] :tenant_id Tenant identifier
      # @option attributes [String] :error_class Error class
      # @option attributes [String] :error_message Error message
      def initialize(attributes = {})
        # Content
        @text = attributes[:text]
        @segments = attributes[:segments]
        @words = attributes[:words]

        # Speaker diarization
        @speakers = attributes[:speakers]
        @speaker_segments = attributes[:speaker_segments]

        # Audio metadata
        @audio_duration = attributes[:audio_duration]
        @audio_format = attributes[:audio_format]
        @audio_channels = attributes[:audio_channels]
        @audio_sample_rate = attributes[:audio_sample_rate]

        # Language
        @language = attributes[:language]
        @detected_language = attributes[:detected_language]
        @language_confidence = attributes[:language_confidence]

        # Model info
        @model_id = attributes[:model_id]

        # Timing
        @duration_ms = attributes[:duration_ms]
        @started_at = attributes[:started_at]
        @completed_at = attributes[:completed_at]

        # Cost & usage
        @total_cost = attributes[:total_cost]
        @audio_minutes = attributes[:audio_minutes] || (audio_duration ? audio_duration / 60.0 : nil)

        # Quality
        @confidence = attributes[:confidence]

        # Status
        @status = attributes[:status] || :success
        @chunks = attributes[:chunks]

        # Multi-tenancy
        @tenant_id = attributes[:tenant_id]

        # Error
        @error_class = attributes[:error_class]
        @error_message = attributes[:error_message]
      end

      # Returns whether the transcription succeeded
      #
      # @return [Boolean] true if no error occurred
      def success?
        error_class.nil? && status == :success
      end

      # Returns whether the transcription failed
      #
      # @return [Boolean] true if an error occurred
      def error?
        !success?
      end

      # Returns whether partial results are available
      #
      # @return [Boolean] true if status is :partial
      def partial?
        status == :partial
      end

      # Returns whether speaker diarization data is available
      #
      # @return [Boolean] true if speakers were identified
      def diarized?
        speakers.present? && speakers.any?
      end

      # Returns the transcription as SRT subtitle format
      #
      # @return [String, nil] SRT formatted subtitles
      def srt
        return nil unless segments.present?

        segments.each_with_index.map do |segment, index|
          start_time = format_srt_time(segment[:start])
          end_time = format_srt_time(segment[:end])
          text_content = segment[:text]&.strip

          "#{index + 1}\n#{start_time} --> #{end_time}\n#{text_content}\n"
        end.join("\n")
      end

      # Returns the transcription as WebVTT subtitle format
      #
      # @return [String, nil] VTT formatted subtitles
      def vtt
        return nil unless segments.present?

        lines = ["WEBVTT", ""]
        segments.each do |segment|
          start_time = format_vtt_time(segment[:start])
          end_time = format_vtt_time(segment[:end])
          text_content = segment[:text]&.strip

          lines << "#{start_time} --> #{end_time}"
          lines << text_content
          lines << ""
        end

        lines.join("\n")
      end

      # Returns calculated words per minute
      #
      # @return [Float, nil] Words per minute or nil if not calculable
      def words_per_minute
        return nil unless text.present? && audio_duration.present? && audio_duration > 0

        word_count = text.split(/\s+/).count
        (word_count / (audio_duration / 60.0)).round(1)
      end

      # Returns the segment at a specific timestamp
      #
      # @param timestamp [Float] Time in seconds
      # @return [Hash, nil] The segment containing the timestamp
      def segment_at(timestamp)
        return nil unless segments.present?

        segments.find do |segment|
          timestamp >= segment[:start] && timestamp <= segment[:end]
        end
      end

      # Returns text between two timestamps
      #
      # @param start_time [Float] Start time in seconds
      # @param end_time [Float] End time in seconds
      # @return [String, nil] Concatenated text from segments in range
      def text_between(start_time, end_time)
        return nil unless segments.present?

        matching = segments.select do |segment|
          segment[:start] >= start_time && segment[:end] <= end_time
        end

        matching.map { |s| s[:text] }.join(" ")
      end

      # Converts the result to a hash
      #
      # @return [Hash] All result data as a hash
      def to_h
        {
          text: text,
          segments: segments,
          words: words,
          speakers: speakers,
          speaker_segments: speaker_segments,
          audio_duration: audio_duration,
          audio_format: audio_format,
          audio_channels: audio_channels,
          audio_sample_rate: audio_sample_rate,
          language: language,
          detected_language: detected_language,
          language_confidence: language_confidence,
          model_id: model_id,
          duration_ms: duration_ms,
          started_at: started_at,
          completed_at: completed_at,
          total_cost: total_cost,
          audio_minutes: audio_minutes,
          confidence: confidence,
          status: status,
          tenant_id: tenant_id,
          error_class: error_class,
          error_message: error_message
        }
      end

      private

      # Formats time for SRT format (HH:MM:SS,mmm)
      #
      # @param seconds [Float] Time in seconds
      # @return [String] SRT formatted time
      def format_srt_time(seconds)
        return "00:00:00,000" unless seconds

        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        secs = (seconds % 60).to_i
        millis = ((seconds % 1) * 1000).to_i

        format("%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
      end

      # Formats time for VTT format (HH:MM:SS.mmm)
      #
      # @param seconds [Float] Time in seconds
      # @return [String] VTT formatted time
      def format_vtt_time(seconds)
        return "00:00:00.000" unless seconds

        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        secs = (seconds % 60).to_i
        millis = ((seconds % 1) * 1000).to_i

        format("%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
      end
    end
  end
end
