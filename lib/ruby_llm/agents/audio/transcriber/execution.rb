# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    class Transcriber
      # Execution logic for transcribers
      #
      # Handles audio input normalization, API calls,
      # execution tracking, and result building.
      module Execution
        # Executes the transcription operation
        #
        # @param audio [String, File, IO] Audio file path, URL, File object, or binary data
        # @param format [Symbol, nil] Audio format hint when passing binary data
        # @return [TranscriptionResult] The transcription result
        def call(audio:, format: nil)
          @execution_started_at = Time.current

          # Resolve tenant context
          resolve_tenant_context!

          # Check budget before execution
          check_budget! if track_transcriptions?

          # Normalize and validate input
          audio_input = normalize_audio_input(audio, format)
          validate_audio_input!(audio_input)

          # Check cache
          if self.class.cache_enabled?
            cache_key = transcription_cache_key(audio_input)
            cached = cache_store.read(cache_key)
            return cached if cached
          end

          # Execute transcription with reliability (retries, fallbacks)
          result = execute_with_reliability(audio_input)

          @execution_completed_at = Time.current

          # Build final result
          final_result = build_result(result)

          # Cache result
          if self.class.cache_enabled?
            cache_key = transcription_cache_key(audio_input)
            cache_store.write(cache_key, final_result, expires_in: self.class.cache_ttl)
          end

          # Record execution
          record_execution(final_result) if track_transcriptions?

          final_result
        rescue StandardError => e
          @execution_completed_at = Time.current
          record_failed_execution(e) if track_transcriptions?
          raise
        end

        # Returns the prompt for transcription context
        #
        # Override this in subclasses to provide context hints that
        # improve transcription accuracy.
        #
        # @return [String, nil] The context prompt
        # @example
        #   def prompt
        #     "Technical discussion about Ruby programming, RubyLLM, API design"
        #   end
        def prompt
          nil
        end

        # Preprocesses text after transcription
        #
        # Override this in subclasses to apply custom post-processing.
        #
        # @param text [String] The transcribed text
        # @return [String] The processed text
        # @example
        #   def postprocess_text(text)
        #     text.gsub(/\bRuby L L M\b/i, 'RubyLLM')
        #   end
        def postprocess_text(text)
          text
        end

        private

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
            elsif File.exist?(audio)
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
          when :file_path
            audio_input[:source]
          when :file_object
            audio_input[:source]
          when :url
            # Download URL to temp file or pass directly if API supports
            audio_input[:source]
          when :binary
            # Create temp file with binary data
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
        #
        # @param raw_result [Hash] Raw transcription result
        # @return [TranscriptionResult] The final result
        def build_result(raw_result)
          # Apply post-processing
          text = postprocess_text(raw_result[:text]) if raw_result[:text]

          TranscriptionResult.new(
            text: text,
            segments: raw_result[:segments],
            words: raw_result[:words],
            language: resolved_language,
            detected_language: raw_result[:language],
            audio_duration: raw_result[:duration],
            model_id: raw_result[:model],
            duration_ms: duration_ms,
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            total_cost: calculate_cost(raw_result),
            audio_minutes: raw_result[:duration] ? raw_result[:duration] / 60.0 : nil,
            status: :success,
            tenant_id: @tenant_id
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

        # Returns the execution duration in milliseconds
        #
        # @return [Integer, nil] Duration in ms
        def duration_ms
          return nil unless @execution_started_at && @execution_completed_at

          ((@execution_completed_at - @execution_started_at) * 1000).to_i
        end

        # Resolves the model to use
        #
        # @return [String] The model identifier
        def resolved_model
          @options[:model] || self.class.model
        end

        # Resolves the language to use
        #
        # @return [String, nil] The language code
        def resolved_language
          @options[:language] || self.class.language
        end

        # Returns max retries from reliability config
        #
        # @return [Integer] Max retry attempts
        def reliability_max_retries
          config = self.class.reliability_config
          config&.max_retries || 3
        end

        # Checks if error is retryable
        #
        # @param error [StandardError] The error
        # @return [Boolean] Whether to retry
        def retryable_error?(error)
          message = error.message.to_s.downcase
          retryable_patterns = ["rate limit", "timeout", "503", "502", "429", "overloaded"]
          retryable_patterns.any? { |pattern| message.include?(pattern) }
        end

        # Calculates exponential backoff delay
        #
        # @param attempt [Integer] Attempt number
        # @return [Float] Delay in seconds
        def calculate_backoff(attempt)
          config = self.class.reliability_config
          base = config&.backoff == :constant ? 1.0 : 0.4
          max_delay = 10.0

          delay = base * (2**(attempt - 1))
          [delay, max_delay].min
        end

        # Resolves tenant context from options
        #
        # @return [void]
        def resolve_tenant_context!
          return if defined?(@tenant_context_resolved) && @tenant_context_resolved

          tenant_value = @options[:tenant]

          if tenant_value.nil?
            @tenant_id = nil
            @tenant_object = nil
            @tenant_config = nil
            @tenant_context_resolved = true
            return
          end

          if tenant_value.is_a?(Hash)
            @tenant_id = tenant_value[:id]&.to_s
            @tenant_object = nil
            @tenant_config = tenant_value.except(:id)
          elsif tenant_value.respond_to?(:llm_tenant_id)
            @tenant_id = tenant_value.llm_tenant_id
            @tenant_object = tenant_value
            @tenant_config = nil
          else
            raise ArgumentError,
                  "tenant must respond to :llm_tenant_id (use llm_tenant DSL), got #{tenant_value.class}"
          end

          @tenant_context_resolved = true
        end

        # Returns the cache store
        #
        # @return [ActiveSupport::Cache::Store] The cache store
        def cache_store
          RubyLLM::Agents.configuration.cache_store
        end

        # Generates a cache key for transcription
        #
        # @param audio_input [Hash] The normalized audio input
        # @return [String] The cache key
        def transcription_cache_key(audio_input)
          # Generate content hash based on input type
          content_hash = case audio_input[:type]
                         when :file_path
                           Digest::SHA256.file(audio_input[:source]).hexdigest
                         when :url
                           Digest::SHA256.hexdigest(audio_input[:source])
                         when :binary
                           Digest::SHA256.hexdigest(audio_input[:source])
                         when :file_object
                           audio_input[:source].rewind if audio_input[:source].respond_to?(:rewind)
                           Digest::SHA256.hexdigest(audio_input[:source].read)
                         end

          components = [
            "ruby_llm_agents",
            "transcription",
            self.class.name,
            self.class.version,
            resolved_model,
            resolved_language,
            content_hash
          ].compact

          components.join("/")
        end

        # Returns whether to track transcriptions
        #
        # @return [Boolean] true if tracking is enabled
        def track_transcriptions?
          RubyLLM::Agents.configuration.track_transcriptions
        end

        # Checks budget before execution
        #
        # @raise [BudgetExceededError] If budget exceeded with hard enforcement
        def check_budget!
          return unless RubyLLM::Agents.configuration.budgets_enabled?

          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "transcription"
          )
        end

        # Records a successful execution
        #
        # @param result [TranscriptionResult] The result to record
        def record_execution(result)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "transcription",
            model_id: result.model_id,
            status: "success",
            input_tokens: 0, # Audio uses duration, not tokens
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            tenant_id: result.tenant_id,
            metadata: {
              audio_duration: result.audio_duration,
              audio_minutes: result.audio_minutes,
              language: result.language || result.detected_language,
              output_format: self.class.output_format
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record transcription execution: #{e.message}") if defined?(Rails)
        end

        # Records a failed execution
        #
        # @param error [StandardError] The error that occurred
        def record_failed_execution(error)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "transcription",
            model_id: resolved_model,
            status: "error",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: 0,
            duration_ms: duration_ms,
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            tenant_id: @tenant_id,
            error_class: error.class.name,
            error_message: error.message.truncate(1000),
            metadata: {
              language: resolved_language,
              output_format: self.class.output_format
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed transcription execution: #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
