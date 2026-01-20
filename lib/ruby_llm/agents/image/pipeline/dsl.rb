# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImagePipeline
      # DSL for defining image pipeline steps and configuration
      #
      # Provides methods for configuring pipeline steps, callbacks,
      # caching, and error handling behavior.
      #
      # @example Defining pipeline steps
      #   class MyPipeline < ImagePipeline
      #     step :generate, generator: LogoGenerator
      #     step :upscale, upscaler: PhotoUpscaler, scale: 4
      #     step :analyze, analyzer: ProductAnalyzer
      #
      #     version "1.0"
      #     description "Complete product image pipeline"
      #     stop_on_error true
      #   end
      #
      module DSL
        # Define a pipeline step
        #
        # @param name [Symbol] Step name (must be unique)
        # @param config [Hash] Step configuration
        # @option config [Class] :generator ImageGenerator class for generation steps
        # @option config [Class] :variator ImageVariator class for variation steps
        # @option config [Class] :editor ImageEditor class for editing steps
        # @option config [Class] :transformer ImageTransformer class for transformation steps
        # @option config [Class] :upscaler ImageUpscaler class for upscaling steps
        # @option config [Class] :analyzer ImageAnalyzer class for analysis steps
        # @option config [Class] :remover BackgroundRemover class for background removal steps
        # @option config [Proc] :if Conditional proc that receives context and returns boolean
        # @option config [Proc] :unless Conditional proc that receives context and returns boolean
        # @return [void]
        #
        # @example Different step types
        #   step :generate, generator: MyGenerator
        #   step :upscale, upscaler: MyUpscaler, scale: 2
        #   step :transform, transformer: StyleTransformer, strength: 0.7
        #   step :analyze, analyzer: ContentAnalyzer
        #   step :remove_bg, remover: BackgroundRemover
        #
        # @example Conditional steps
        #   step :upscale, upscaler: PhotoUpscaler, if: ->(ctx) { ctx[:high_quality] }
        #   step :remove_bg, remover: BackgroundRemover, unless: ->(ctx) { ctx[:keep_background] }
        #
        def step(name, **config)
          @steps ||= []

          # Validate step configuration
          validate_step_config!(name, config)

          @steps << {
            name: name,
            config: config,
            type: determine_step_type(config)
          }
        end

        # Get all defined steps
        #
        # @return [Array<Hash>] Array of step definitions
        def steps
          @steps ||= []
        end

        # Add a callback to run before the pipeline
        #
        # @param method_name [Symbol] Method to call
        # @yield Block to execute
        # @return [void]
        #
        # @example
        #   before_pipeline :validate_inputs
        #   before_pipeline { |ctx| ctx[:started_at] = Time.current }
        #
        def before_pipeline(method_name = nil, &block)
          @callbacks ||= { before: [], after: [] }
          @callbacks[:before] << (block || method_name)
        end

        # Add a callback to run after the pipeline
        #
        # @param method_name [Symbol] Method to call
        # @yield Block to execute
        # @return [void]
        #
        # @example
        #   after_pipeline :add_watermark
        #   after_pipeline { |result| notify_completion(result) }
        #
        def after_pipeline(method_name = nil, &block)
          @callbacks ||= { before: [], after: [] }
          @callbacks[:after] << (block || method_name)
        end

        # Get callbacks
        #
        # @return [Hash] Hash with :before and :after arrays
        def callbacks
          @callbacks ||= { before: [], after: [] }
        end

        # Set or get the version
        #
        # @param value [String, nil] Version identifier
        # @return [String] The version
        def version(value = nil)
          if value
            @version = value
          else
            @version || inherited_or_default(:version, "v1")
          end
        end

        # Set or get the description
        #
        # @param value [String, nil] Description
        # @return [String, nil] The description
        def description(value = nil)
          if value
            @description = value
          else
            @description || inherited_or_default(:description, nil)
          end
        end

        # Enable caching with the given TTL
        #
        # @param ttl [ActiveSupport::Duration, Integer] Cache duration
        def cache_for(ttl)
          @cache_ttl = ttl
        end

        # Get the cache TTL
        #
        # @return [ActiveSupport::Duration, Integer, nil] The cache TTL
        def cache_ttl
          @cache_ttl || inherited_or_default(:cache_ttl, nil)
        end

        # Check if caching is enabled
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          !cache_ttl.nil?
        end

        # Set whether to stop on error (default: true)
        #
        # @param value [Boolean, nil] Whether to stop on first error
        # @return [Boolean] Current setting
        def stop_on_error(value = nil)
          if value.nil?
            return @stop_on_error if defined?(@stop_on_error) && !@stop_on_error.nil?
            inherited_or_default(:stop_on_error, true)
          else
            @stop_on_error = value
          end
        end

        alias stop_on_error? stop_on_error

        private

        def validate_step_config!(name, config)
          # Check for duplicate step names
          if @steps&.any? { |s| s[:name] == name }
            raise ArgumentError, "Step :#{name} is already defined"
          end

          # Check for valid step type
          valid_keys = %i[generator variator editor transformer upscaler analyzer remover]
          step_keys = config.keys & valid_keys

          if step_keys.empty?
            raise ArgumentError, "Step :#{name} must specify one of: #{valid_keys.join(', ')}"
          end

          if step_keys.size > 1
            raise ArgumentError, "Step :#{name} can only specify one step type, got: #{step_keys.join(', ')}"
          end

          # Validate the class responds to call
          step_class = config[step_keys.first]
          unless step_class.respond_to?(:call)
            raise ArgumentError, "#{step_class} must respond to .call"
          end
        end

        def determine_step_type(config)
          %i[generator variator editor transformer upscaler analyzer remover].find do |type|
            config.key?(type)
          end
        end

        def inherited_or_default(attribute, default)
          if superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
