# frozen_string_literal: true

require "digest"
require_relative "../results/transcription_result"

module RubyLLM
  module Agents
    # Base class for creating audio transcribers using the middleware pipeline
    #
    # Transcriber provides a DSL for configuring audio-to-text operations with
    # built-in execution tracking, budget controls, and multi-tenancy support
    # through the middleware pipeline.
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
    # @api public
    class Transcriber < BaseAgent
      class << self
        # Returns the agent type for transcribers
        #
        # @return [Symbol] :audio
        def agent_type
          :audio
        end

        # @!group Transcriber-specific DSL

        # Sets or returns the transcription model
        #
        # @param value [String, nil] The model identifier
        # @return [String] The current model setting
        def model(value = nil)
          @model = value if value
          return @model if defined?(@model) && @model

          if superclass.respond_to?(:agent_type) && superclass.agent_type == :audio
            superclass.model
          else
            default_transcription_model
          end
        end

        # Sets or returns the language for transcription
        #
        # @param value [String, nil] ISO 639-1 language code
        # @return [String, nil] The current language setting
        def language(value = nil)
          @language = value if value
          @language || inherited_or_default(:language, nil)
        end

        # Sets or returns the output format for transcription
        #
        # @param value [Symbol, nil] Output format (:text, :json, :srt, :vtt, :verbose_json)
        # @return [Symbol] The current output format
        def output_format(value = nil)
          @output_format = value if value
          @output_format || inherited_or_default(:output_format, :text)
        end

        # Sets or returns whether to include timestamps
        #
        # @param value [Symbol, nil] Timestamp level (:none, :segment, :word)
        # @return [Symbol] The current timestamp setting
        def include_timestamps(value = nil)
          @include_timestamps = value if value
          @include_timestamps || inherited_or_default(:include_timestamps, :segment)
        end

        # @!endgroup

        # @!group Chunking DSL

        # Configures chunking for long audio files
        #
        # @yield Block for configuring chunking options
        # @return [ChunkingConfig] The chunking configuration
        def chunking(&block)
          @chunking_config ||= ChunkingConfig.new
          @chunking_config.instance_eval(&block) if block_given?
          @chunking_config
        end

        # Returns chunking configuration
        #
        # @return [ChunkingConfig, nil] The chunking configuration
        def chunking_config
          @chunking_config || inherited_or_default(:chunking_config, nil)
        end

        # @!endgroup

        # @!group Reliability DSL

        # Configures reliability options (retries, fallbacks)
        #
        # @yield Block for configuring reliability options
        # @return [ReliabilityConfig] The reliability configuration
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

        # Sets fallback models directly (shorthand for reliability block)
        #
        # @param models [Array<String>] Model identifiers to try on failure
        # @return [Array<String>] The fallback models
        def fallback_models(*models)
          if models.any?
            @fallback_models = models.flatten
          end
          @fallback_models || inherited_or_default(:fallback_models, [])
        end

        # @!endgroup

        # Factory method to instantiate and execute transcription
        #
        # @param audio [String, File, IO] Audio file path, URL, File object, or binary data
        # @param format [Symbol, nil] Audio format hint when passing binary data
        # @param options [Hash] Additional options
        # @return [TranscriptionResult] The transcription result
        def call(audio:, format: nil, **options)
          new(audio: audio, format: format, **options).call
        end

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        def default_transcription_model
          RubyLLM::Agents.configuration.default_transcription_model
        rescue StandardError
          "whisper-1"
        end
      end

      # Configuration class for chunking options
      class ChunkingConfig
        attr_accessor :enabled, :max_duration, :overlap, :parallel

        def initialize
          @enabled = false
          @max_duration = 600 # 10 minutes
          @overlap = 5 # 5 seconds
          @parallel = false
        end

        def enabled?
          @enabled
        end

        def to_h
          {
            enabled: enabled,
            max_duration: max_duration,
            overlap: overlap,
            parallel: parallel
          }
        end
      end

      # Configuration class for reliability options
      class ReliabilityConfig
        attr_accessor :max_retries, :backoff, :fallback_models_list, :total_timeout_seconds

        def initialize
          @max_retries = 3
          @backoff = :exponential
          @fallback_models_list = []
          @total_timeout_seconds = nil
        end

        def retries(max: 3, backoff: :exponential)
          @max_retries = max
          @backoff = backoff
        end

        def fallback_models(*models)
          @fallback_models_list = models.flatten
        end

        def total_timeout(seconds)
          @total_timeout_seconds = seconds
        end

        def to_h
          {
            max_retries: max_retries,
            backoff: backoff,
            fallback_models: fallback_models_list,
            total_timeout: total_timeout_seconds
          }
        end
      end

      # @!attribute [r] audio
      #   @return [String, File, IO] Audio input
      # @!attribute [r] audio_format
      #   @return [Symbol, nil] Audio format hint
      attr_reader :audio, :audio_format

      # Creates a new Transcriber instance
      #
      # @param audio [String, File, IO] Audio file path, URL, File object, or binary data
      # @param format [Symbol, nil] Audio format hint when passing binary data
      # @param options [Hash] Configuration options
      def initialize(audio:, format: nil, **options)
        @audio = audio
        @audio_format = format
        @runtime_language = options.delete(:language)

        # Set model to transcription model if not specified
        options[:model] ||= self.class.model

        super(**options)
      end

      # Executes the transcription through the middleware pipeline
      #
      # @return [TranscriptionResult] The transcription result
      def call
        context = build_context
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # The input for this transcription operation
      #
      # @return [String] Description of the audio input
      def user_prompt
        case @audio
        when String
          @audio.start_with?("http") ? "Audio URL: #{@audio}" : "Audio file: #{@audio}"
        else
          "Audio data"
        end
      end

      # Returns the prompt for transcription context
      #
      # Override this in subclasses to provide context hints that
      # improve transcription accuracy.
      #
      # @return [String, nil] The context prompt
      def prompt
        nil
      end

      # Post-processes text after transcription
      #
      # Override this in subclasses to apply custom post-processing.
      #
      # @param text [String] The transcribed text
      # @return [String] The processed text
      def postprocess_text(text)
        text
      end

      # Core transcription execution
      #
      # This is called by the Pipeline::Executor after middleware
      # has been applied. Only contains the transcription API logic.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the TranscriptionResult
      def execute(context)
        execution_started_at = Time.current

        # Normalize and validate input
        audio_input = normalize_audio_input(@audio, @audio_format)
        validate_audio_input!(audio_input)

        # Execute transcription with reliability (retries, fallbacks)
        raw_result = execute_with_reliability(audio_input)

        execution_completed_at = Time.current
        duration_ms = ((execution_completed_at - execution_started_at) * 1000).to_i

        # Update context
        context.input_tokens = 0 # Audio uses duration, not tokens
        context.output_tokens = 0
        context.total_cost = calculate_cost(raw_result)

        # Build final result
        context.output = build_result(
          raw_result,
          started_at: context.started_at || execution_started_at,
          completed_at: execution_completed_at,
          duration_ms: duration_ms,
          tenant_id: context.tenant_id
        )
      end

      # Generates the cache key for this transcription
      #
      # @return [String] Cache key
      def agent_cache_key
        # Generate content hash based on input type
        content_hash = case @audio
                       when String
                         if @audio.start_with?("http://", "https://")
                           Digest::SHA256.hexdigest(@audio)
                         elsif File.exist?(@audio)
                           Digest::SHA256.file(@audio).hexdigest
                         else
                           Digest::SHA256.hexdigest(@audio)
                         end
                       when File, IO
                         @audio.rewind if @audio.respond_to?(:rewind)
                         Digest::SHA256.hexdigest(@audio.read).tap do
                           @audio.rewind if @audio.respond_to?(:rewind)
                         end
                       else
                         Digest::SHA256.hexdigest(@audio.to_s)
                       end

        components = [
          "ruby_llm_agents",
          "transcription",
          self.class.name,
          self.class.version,
          resolved_model,
          resolved_language,
          self.class.output_format,
          content_hash
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
          skip_cache: @options[:skip_cache]
        )
      end

      # Normalizes audio input to a consistent format
      #
      # @param audio [String, File, IO] Audio input
      # @param format [Symbol, nil] Format hint
      # @return [Hash] Normalized audio input with :source and :type
      def normalize_audio_input(audio, format)
        case audio
        when String
          if audio.start_with?("http://", "https://")
            { source: audio, type: :url }
          elsif looks_like_file_path?(audio)
            { source: audio, type: :file_path }
          else
            # Assume it's binary data
            { source: audio, type: :binary, format: format }
          end
        when File, IO
          { source: audio, type: :file_object }
        else
          raise ArgumentError, "audio must be a file path, URL, File object, or binary data"
        end
      end

      # Determines if a string looks like a file path
      #
      # @param str [String] String to check
      # @return [Boolean] True if it looks like a file path
      def looks_like_file_path?(str)
        # Check if it has path separators or common audio extensions
        return true if str.include?("/") || str.include?("\\")
        return true if str.match?(/\.(mp3|wav|ogg|flac|m4a|aac|webm|mp4|mpeg)$/i)

        # Otherwise check if file actually exists
        File.exist?(str)
      end

      # Validates audio input
      #
      # @param audio_input [Hash] Normalized audio input
      # @raise [ArgumentError] If input is invalid
      def validate_audio_input!(audio_input)
        case audio_input[:type]
        when :file_path
          unless File.exist?(audio_input[:source])
            raise ArgumentError, "Audio file not found: #{audio_input[:source]}"
          end
        when :url
          unless audio_input[:source].match?(%r{\Ahttps?://}i)
            raise ArgumentError, "Invalid audio URL: #{audio_input[:source]}"
          end
        when :binary
          if audio_input[:source].nil? || audio_input[:source].empty?
            raise ArgumentError, "Binary audio data cannot be empty"
          end
        end
      end

      # Executes transcription with reliability features
      #
      # @param audio_input [Hash] Normalized audio input
      # @return [Hash] Raw transcription result
      def execute_with_reliability(audio_input)
        models_to_try = [resolved_model] + self.class.fallback_models
        last_error = nil

        models_to_try.each do |model|
          retries = 0
          max_retries = reliability_max_retries

          begin
            return execute_transcription(audio_input, model)
          rescue StandardError => e
            last_error = e
            retries += 1

            if retryable_error?(e) && retries < max_retries
              sleep(calculate_backoff(retries))
              retry
            end

            # Try next model
            next
          end
        end

        raise last_error || StandardError.new("All transcription models exhausted")
      end

      # Executes the actual transcription API call
      #
      # @param audio_input [Hash] Normalized audio input
      # @param model [String] Model to use
      # @return [Hash] Raw transcription result
      def execute_transcription(audio_input, model)
        transcribe_options = build_transcribe_options(model)

        # Get audio source for API call
        audio_source = resolve_audio_source(audio_input)

        # Call RubyLLM's transcribe method
        response = RubyLLM.transcribe(audio_source, **transcribe_options)

        {
          text: response.text,
          segments: extract_segments(response),
          words: extract_words(response),
          language: response.respond_to?(:language) ? response.language : nil,
          duration: response.respond_to?(:duration) ? response.duration : nil,
          model: model,
          raw_response: response
        }
      end

      # Builds options for RubyLLM.transcribe
      #
      # @param model [String] Model to use
      # @return [Hash] Options for transcription
      def build_transcribe_options(model)
        options = { model: model }

        # Add language if specified
        lang = resolved_language
        options[:language] = lang if lang

        # Add prompt if specified
        prompt_text = prompt
        options[:prompt] = prompt_text if prompt_text

        # Add format-specific options
        case self.class.output_format
        when :verbose_json
          options[:response_format] = "verbose_json"
        when :srt
          options[:response_format] = "srt"
        when :vtt
          options[:response_format] = "vtt"
        end

        # Add timestamp granularity
        case self.class.include_timestamps
        when :word
          options[:timestamp_granularities] = ["word", "segment"]
        when :segment
          options[:timestamp_granularities] = ["segment"]
        end

        options
      end

      # Resolves audio source for API call
      #
      # @param audio_input [Hash] Normalized audio input
      # @return [String, File] Audio source for API
      def resolve_audio_source(audio_input)
        case audio_input[:type]
        when :file_path, :file_object, :url, :binary
          audio_input[:source]
        end
      end

      # Extracts segments from transcription response
      #
      # @param response [Object] Transcription response
      # @return [Array<Hash>, nil] Segments array
      def extract_segments(response)
        return nil unless response.respond_to?(:segments)

        segments = response.segments
        return nil unless segments.is_a?(Array)

        segments.map do |seg|
          {
            start: seg[:start] || seg["start"],
            end: seg[:end] || seg["end"],
            text: seg[:text] || seg["text"],
            speaker: seg[:speaker] || seg["speaker"]
          }
        end
      end

      # Extracts words from transcription response
      #
      # @param response [Object] Transcription response
      # @return [Array<Hash>, nil] Words array
      def extract_words(response)
        return nil unless response.respond_to?(:words)

        words = response.words
        return nil unless words.is_a?(Array)

        words.map do |word|
          {
            start: word[:start] || word["start"],
            end: word[:end] || word["end"],
            word: word[:word] || word["word"]
          }
        end
      end

      # Builds the final result object
      def build_result(raw_result, started_at:, completed_at:, duration_ms:, tenant_id:)
        # Apply post-processing
        text = raw_result[:text] ? postprocess_text(raw_result[:text]) : nil

        TranscriptionResult.new(
          text: text,
          segments: raw_result[:segments],
          words: raw_result[:words],
          language: resolved_language,
          detected_language: raw_result[:language],
          audio_duration: raw_result[:duration],
          model_id: raw_result[:model],
          duration_ms: duration_ms,
          started_at: started_at,
          completed_at: completed_at,
          total_cost: calculate_cost(raw_result),
          audio_minutes: raw_result[:duration] ? raw_result[:duration] / 60.0 : nil,
          status: :success,
          tenant_id: tenant_id
        )
      end

      # Calculates cost for transcription
      #
      # @param raw_result [Hash] Raw transcription result
      # @return [Float] Cost in USD
      def calculate_cost(raw_result)
        # Get duration in minutes
        duration_minutes = raw_result[:duration] ? raw_result[:duration] / 60.0 : 0

        # Check if response has cost info
        if raw_result[:raw_response].respond_to?(:cost) && raw_result[:raw_response].cost
          return raw_result[:raw_response].cost
        end

        # Estimate based on model and duration
        model = raw_result[:model].to_s
        price_per_minute = case model
                           when /whisper-1/
                             0.006
                           when /gpt-4o-transcribe/
                             0.01
                           when /gpt-4o-mini-transcribe/
                             0.005
                           else
                             0.006 # Default to whisper pricing
                           end

        duration_minutes * price_per_minute
      end

      # Resolves the model to use
      def resolved_model
        @model || self.class.model
      end

      # Resolves the language to use
      def resolved_language
        @runtime_language || self.class.language
      end

      # Returns max retries from reliability config
      def reliability_max_retries
        config = self.class.reliability_config
        config&.max_retries || 3
      end

      # Checks if error is retryable
      def retryable_error?(error)
        message = error.message.to_s.downcase
        retryable_patterns = ["rate limit", "timeout", "503", "502", "429", "overloaded"]
        retryable_patterns.any? { |pattern| message.include?(pattern) }
      end

      # Calculates exponential backoff delay
      def calculate_backoff(attempt)
        config = self.class.reliability_config
        base = config&.backoff == :constant ? 1.0 : 0.4
        max_delay = 10.0

        delay = base * (2**(attempt - 1))
        [delay, max_delay].min
      end
    end
  end
end
