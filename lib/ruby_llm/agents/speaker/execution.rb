# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    class Speaker
      # Execution logic for speakers
      #
      # Handles text input processing, API calls,
      # execution tracking, and result building.
      module Execution
        # Executes the text-to-speech operation
        #
        # @param text [String] Text to convert to speech
        # @yield [audio_chunk] Called for each audio chunk when streaming
        # @return [SpeechResult] The speech result
        def call(text:, &block)
          @execution_started_at = Time.current
          @streaming_block = block

          # Resolve tenant context
          resolve_tenant_context!

          # Check budget before execution
          check_budget! if track_speech?

          # Validate input
          validate_text_input!(text)

          # Apply lexicon if configured
          processed_text = apply_lexicon(text)

          # Check cache (only for non-streaming)
          if self.class.cache_enabled? && !block_given?
            cache_key = speech_cache_key(processed_text)
            cached = cache_store.read(cache_key)
            return cached if cached
          end

          # Execute speech synthesis with reliability
          result = execute_with_reliability(processed_text, &block)

          @execution_completed_at = Time.current

          # Build final result
          final_result = build_result(result, text)

          # Cache result (only for non-streaming)
          if self.class.cache_enabled? && !block_given?
            cache_key = speech_cache_key(processed_text)
            cache_store.write(cache_key, final_result, expires_in: self.class.cache_ttl)
          end

          # Record execution
          record_execution(final_result) if track_speech?

          final_result
        rescue StandardError => e
          @execution_completed_at = Time.current
          record_failed_execution(e) if track_speech?
          raise
        end

        private

        # Validates text input
        #
        # @param text [String] Text to validate
        # @raise [ArgumentError] If input is invalid
        def validate_text_input!(text)
          raise ArgumentError, "text is required" if text.nil?
          raise ArgumentError, "text cannot be empty" if text.empty?
          raise ArgumentError, "text must be a String, got #{text.class}" unless text.is_a?(String)
        end

        # Applies lexicon pronunciations to text
        #
        # @param text [String] Original text
        # @return [String] Text with pronunciation substitutions
        def apply_lexicon(text)
          lexicon = self.class.lexicon_config
          return text unless lexicon

          lexicon.apply(text)
        end

        # Executes speech synthesis with reliability features
        #
        # @param text [String] Text to synthesize
        # @yield [audio_chunk] For streaming
        # @return [Hash] Raw speech result
        def execute_with_reliability(text, &block)
          last_error = nil
          retries = 0
          max_retries = reliability_max_retries

          begin
            return execute_speech(text, &block)
          rescue StandardError => e
            last_error = e
            retries += 1

            if retryable_error?(e) && retries < max_retries
              sleep(calculate_backoff(retries))
              retry
            end

            # Try fallback provider if configured
            fallback = self.class.reliability_config&.fallback_provider_config
            if fallback && retries == max_retries
              return execute_fallback_speech(text, fallback, &block)
            end

            raise
          end
        end

        # Executes the actual speech synthesis API call
        #
        # @param text [String] Text to synthesize
        # @yield [audio_chunk] For streaming
        # @return [Hash] Raw speech result
        def execute_speech(text, &block)
          speak_options = build_speak_options

          # Handle streaming vs non-streaming
          if block_given? && self.class.streaming?
            execute_streaming_speech(text, speak_options, &block)
          else
            execute_standard_speech(text, speak_options)
          end
        end

        # Executes standard (non-streaming) speech synthesis
        #
        # @param text [String] Text to synthesize
        # @param options [Hash] API options
        # @return [Hash] Raw speech result
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
        #
        # @param text [String] Text to synthesize
        # @param options [Hash] API options
        # @yield [audio_chunk] Called for each chunk
        # @return [Hash] Raw speech result
        def execute_streaming_speech(text, options, &block)
          audio_chunks = []

          RubyLLM.speak(text, **options.merge(stream: true)) do |chunk|
            audio_chunks << chunk.audio if chunk.respond_to?(:audio)
            block.call(chunk) if block
          end

          {
            audio: audio_chunks.join,
            duration: nil, # Duration not available during streaming
            format: resolved_output_format,
            provider: resolved_provider,
            model: resolved_model,
            voice: resolved_voice,
            characters: text.length,
            streamed: true
          }
        end

        # Executes speech with fallback provider
        #
        # @param text [String] Text to synthesize
        # @param fallback_config [Hash] Fallback configuration
        # @yield [audio_chunk] For streaming
        # @return [Hash] Raw speech result
        def execute_fallback_speech(text, fallback_config, &block)
          options = {
            model: model_for_provider(fallback_config[:provider]),
            voice: fallback_config[:voice] || default_voice_for_provider(fallback_config[:provider])
          }

          options[:response_format] = resolved_output_format.to_s

          response = RubyLLM.speak(text, **options)

          {
            audio: response.audio,
            duration: response.respond_to?(:duration) ? response.duration : nil,
            format: resolved_output_format,
            provider: fallback_config[:provider],
            model: options[:model],
            voice: options[:voice],
            characters: text.length,
            fallback: true,
            raw_response: response
          }
        end

        # Builds options for RubyLLM.speak
        #
        # @return [Hash] Options for speech synthesis
        def build_speak_options
          options = {
            model: resolved_model,
            voice: resolved_voice_id || resolved_voice
          }

          # Add speed if not default
          speed = resolved_speed
          options[:speed] = speed if speed && speed != 1.0

          # Add output format
          options[:response_format] = resolved_output_format.to_s

          # Add voice settings for ElevenLabs
          if resolved_provider == :elevenlabs
            voice_settings = self.class.voice_settings_config
            if voice_settings
              options[:voice_settings] = voice_settings.to_h
            end
          end

          options
        end

        # Returns model for a given provider
        #
        # @param provider [Symbol] Provider name
        # @return [String] Model identifier
        def model_for_provider(provider)
          case provider
          when :openai
            "tts-1"
          when :elevenlabs
            "eleven_multilingual_v2"
          when :google
            "standard"
          when :polly
            "neural"
          else
            "tts-1"
          end
        end

        # Returns default voice for a given provider
        #
        # @param provider [Symbol] Provider name
        # @return [String] Voice identifier
        def default_voice_for_provider(provider)
          case provider
          when :openai
            "nova"
          when :elevenlabs
            "Rachel"
          when :google
            "en-US-Standard-A"
          when :polly
            "Joanna"
          else
            "nova"
          end
        end

        # Builds the final result object
        #
        # @param raw_result [Hash] Raw speech result
        # @param original_text [String] Original input text
        # @return [SpeechResult] The final result
        def build_result(raw_result, original_text)
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
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            total_cost: calculate_cost(raw_result),
            status: :success,
            tenant_id: @tenant_id
          )
        end

        # Calculates cost for speech synthesis
        #
        # @param raw_result [Hash] Raw speech result
        # @return [Float] Cost in USD
        def calculate_cost(raw_result)
          characters = raw_result[:characters] || 0

          # Check if response has cost info
          if raw_result[:raw_response].respond_to?(:cost) && raw_result[:raw_response].cost
            return raw_result[:raw_response].cost
          end

          # Estimate based on provider and characters
          provider = raw_result[:provider]
          model = raw_result[:model].to_s

          price_per_1k_chars = case provider
                               when :openai
                                 if model.include?("hd")
                                   0.030 # tts-1-hd
                                 else
                                   0.015 # tts-1
                                 end
                               when :elevenlabs
                                 0.30 # Standard tier
                               when :google
                                 0.016 # WaveNet
                               when :polly
                                 0.016 # Neural
                               else
                                 0.015 # Default to OpenAI standard
                               end

          (characters / 1000.0) * price_per_1k_chars
        end

        # Returns the execution duration in milliseconds
        #
        # @return [Integer, nil] Duration in ms
        def duration_ms
          return nil unless @execution_started_at && @execution_completed_at

          ((@execution_completed_at - @execution_started_at) * 1000).to_i
        end

        # Resolves the provider to use
        #
        # @return [Symbol] The provider
        def resolved_provider
          @options[:provider] || self.class.provider
        end

        # Resolves the model to use
        #
        # @return [String] The model identifier
        def resolved_model
          @options[:model] || self.class.model
        end

        # Resolves the voice to use
        #
        # @return [String] The voice name
        def resolved_voice
          @options[:voice] || self.class.voice
        end

        # Resolves the voice ID to use
        #
        # @return [String, nil] The voice ID
        def resolved_voice_id
          @options[:voice_id] || self.class.voice_id
        end

        # Resolves the speed to use
        #
        # @return [Float] The speed multiplier
        def resolved_speed
          @options[:speed] || self.class.speed
        end

        # Resolves the output format to use
        #
        # @return [Symbol] The output format
        def resolved_output_format
          @options[:format] || self.class.output_format
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

        # Generates a cache key for speech
        #
        # @param text [String] The text to cache
        # @return [String] The cache key
        def speech_cache_key(text)
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

        # Returns whether to track speech executions
        #
        # @return [Boolean] true if tracking is enabled
        def track_speech?
          RubyLLM::Agents.configuration.track_speech
        end

        # Checks budget before execution
        #
        # @raise [BudgetExceededError] If budget exceeded with hard enforcement
        def check_budget!
          return unless RubyLLM::Agents.configuration.budgets_enabled?

          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "speech"
          )
        end

        # Records a successful execution
        #
        # @param result [SpeechResult] The result to record
        def record_execution(result)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "speech",
            model_id: result.model_id,
            status: "success",
            input_tokens: 0, # TTS uses characters, not tokens
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            tenant_id: result.tenant_id,
            metadata: {
              provider: result.provider,
              voice: result.voice_name,
              voice_id: result.voice_id,
              characters: result.characters,
              audio_duration: result.duration,
              format: result.format,
              file_size: result.file_size
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record speech execution: #{e.message}") if defined?(Rails)
        end

        # Records a failed execution
        #
        # @param error [StandardError] The error that occurred
        def record_failed_execution(error)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "speech",
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
              provider: resolved_provider,
              voice: resolved_voice,
              format: resolved_output_format
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed speech execution: #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
