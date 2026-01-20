# frozen_string_literal: true

module RubyLLM
  module Agents
    class Transcriber
      # Class-level DSL for configuring transcribers
      #
      # Provides methods for setting model, language, output format,
      # and other transcription-specific options.
      module DSL
        # @!group Configuration DSL

        # Sets or returns the transcription model for this transcriber class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "whisper-1"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_transcription_model)
        end

        # Sets or returns the language for transcription
        #
        # @param value [String, nil] ISO 639-1 language code
        # @return [String, nil] The current language setting
        # @example
        #   language "en"
        #   language "es"
        def language(value = nil)
          @language = value if value
          @language || inherited_or_default(:language, nil)
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

        # Sets or returns the description for this transcriber class
        #
        # @param value [String, nil] The description text
        # @return [String, nil] The current description
        # @example
        #   description "Transcribes meeting recordings"
        def description(value = nil)
          @description = value if value
          @description || inherited_or_default(:description, nil)
        end

        # @!endgroup

        # @!group Output Format DSL

        # Sets or returns the output format for transcription
        #
        # @param value [Symbol, nil] Output format (:text, :json, :srt, :vtt, :verbose_json)
        # @return [Symbol] The current output format
        # @example
        #   output_format :srt
        def output_format(value = nil)
          @output_format = value if value
          @output_format || inherited_or_default(:output_format, :text)
        end

        # Sets or returns whether to include timestamps
        #
        # @param value [Symbol, nil] Timestamp level (:none, :segment, :word)
        # @return [Symbol] The current timestamp setting
        # @example
        #   include_timestamps :segment
        #   include_timestamps :word
        def include_timestamps(value = nil)
          @include_timestamps = value if value
          @include_timestamps || inherited_or_default(:include_timestamps, :segment)
        end

        # @!endgroup

        # @!group Caching DSL

        # Enables caching for this transcriber with explicit TTL
        #
        # Since the same audio always produces the same transcription,
        # caching can significantly reduce API costs.
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache_for 30.days
        def cache_for(ttl)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this transcriber
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          @cache_enabled || false
        end

        # Returns the cache TTL for this transcriber
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || 1.hour
        end

        # @!endgroup

        # @!group Chunking DSL

        # Configures chunking for long audio files
        #
        # @yield Block for configuring chunking options
        # @return [void]
        # @example
        #   chunking do
        #     enabled true
        #     max_duration 600        # 10 minutes per chunk
        #     overlap 5               # 5 second overlap
        #     parallel true           # Process chunks in parallel
        #   end
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
        # @return [void]
        # @example
        #   reliability do
        #     retries max: 3, backoff: :exponential
        #     fallback_models 'whisper-1', 'gpt-4o-mini-transcribe'
        #     total_timeout 300
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

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
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
      end
    end
  end
end
