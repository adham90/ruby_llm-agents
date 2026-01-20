# frozen_string_literal: true

require_relative "upscaler/dsl"
require_relative "upscaler/execution"

module RubyLLM
  module Agents
    # Image upscaler for resolution enhancement
    #
    # Increases the resolution of images using AI upscaling models.
    # Supports 2x, 4x, and 8x upscaling with optional face enhancement.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageUpscaler.call(image: "path/to/low_res.jpg")
    #   result.url # => "https://..." (high resolution version)
    #
    # @example Custom upscaler class
    #   class PhotoUpscaler < RubyLLM::Agents::ImageUpscaler
    #     model "real-esrgan"
    #     scale 4
    #     face_enhance true
    #
    #     description "Upscales photos with face enhancement"
    #   end
    #
    #   result = PhotoUpscaler.call(image: portrait_photo)
    #   result.size # => "4096x4096" (if input was 1024x1024)
    #
    class ImageUpscaler
      extend DSL
      include Execution

      class << self
        # Execute image upscaling
        #
        # @param image [String, IO] Path, URL, or IO object of the source image
        # @param options [Hash] Additional options (model, scale, etc.)
        # @return [ImageUpscaleResult] The result containing upscaled image
        def call(image:, **options)
          new(image: image, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@scale, @scale)
          subclass.instance_variable_set(:@face_enhance, @face_enhance)
          subclass.instance_variable_set(:@denoise_strength, @denoise_strength)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
        end
      end

      attr_reader :image, :options, :tenant_id

      # Initialize a new image upscaler instance
      #
      # @param image [String, IO] Source image (path, URL, or IO object)
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [Integer] :scale Upscale factor (2, 4, or 8)
      # @option options [Boolean] :face_enhance Enable face enhancement
      # @option options [Float] :denoise_strength Denoising strength (0.0-1.0)
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      # Execute the image upscaling
      #
      # @return [ImageUpscaleResult] The result containing upscaled image
      def call
        execute
      end
    end
  end
end
