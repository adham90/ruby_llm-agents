# frozen_string_literal: true

require_relative "transformer/dsl"
require_relative "transformer/execution"

module RubyLLM
  module Agents
    # Image transformer for style transfer and image-to-image generation
    #
    # Transforms an existing image based on a text prompt while
    # maintaining the overall structure. The strength parameter
    # controls how much the image is transformed.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageTransformer.call(
    #     image: "path/to/photo.jpg",
    #     prompt: "Convert to watercolor painting style"
    #   )
    #   result.url # => "https://..."
    #
    # @example Custom transformer class
    #   class AnimeTransformer < RubyLLM::Agents::ImageTransformer
    #     model "sdxl"
    #     strength 0.8
    #     template "anime style, studio ghibli, {prompt}"
    #
    #     description "Transforms photos into anime style"
    #   end
    #
    #   result = AnimeTransformer.call(
    #     image: user_photo,
    #     prompt: "portrait of a person"
    #   )
    #
    class ImageTransformer
      extend DSL
      include Execution

      class << self
        # Execute image transformation
        #
        # @param image [String, IO] Path, URL, or IO object of the source image
        # @param prompt [String] Description of the desired transformation
        # @param options [Hash] Additional options (model, strength, size, etc.)
        # @return [ImageTransformResult] The result containing transformed image
        def call(image:, prompt:, **options)
          new(image: image, prompt: prompt, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@size, @size)
          subclass.instance_variable_set(:@strength, @strength)
          subclass.instance_variable_set(:@preserve_composition, @preserve_composition)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
          subclass.instance_variable_set(:@template_string, @template_string)
          subclass.instance_variable_set(:@negative_prompt, @negative_prompt)
          subclass.instance_variable_set(:@guidance_scale, @guidance_scale)
          subclass.instance_variable_set(:@steps, @steps)
        end
      end

      attr_reader :image, :prompt, :options, :tenant_id

      # Initialize a new image transformer instance
      #
      # @param image [String, IO] Source image (path, URL, or IO object)
      # @param prompt [String] Description of the desired transformation
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [String] :size Output image size
      # @option options [Float] :strength Transformation strength (0.0-1.0)
      # @option options [Integer] :count Number of transformations to generate
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, prompt:, **options)
        @image = image
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      # Execute the image transformation
      #
      # @return [ImageTransformResult] The result containing transformed image
      def call
        execute
      end
    end
  end
end
