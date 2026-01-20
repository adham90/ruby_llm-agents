# frozen_string_literal: true

require_relative "image_editor/dsl"
require_relative "image_editor/execution"

module RubyLLM
  module Agents
    # Image editor for inpainting and image editing
    #
    # Allows editing specific regions of an image using a mask.
    # The mask indicates which parts of the image should be modified.
    # White areas in the mask are edited, black areas are preserved.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageEditor.call(
    #     image: "path/to/image.png",
    #     mask: "path/to/mask.png",
    #     prompt: "Replace with a red car"
    #   )
    #   result.url # => "https://..."
    #
    # @example Custom editor class
    #   class ProductEditor < RubyLLM::Agents::ImageEditor
    #     model "gpt-image-1"
    #     size "1024x1024"
    #
    #     description "Edits product images"
    #   end
    #
    #   result = ProductEditor.call(
    #     image: product_photo,
    #     mask: background_mask,
    #     prompt: "Professional studio background"
    #   )
    #
    class ImageEditor
      extend DSL
      include Execution

      class << self
        # Execute image editing with the given source image, mask, and prompt
        #
        # @param image [String, IO] Path, URL, or IO object of the source image
        # @param mask [String, IO] Path, URL, or IO object of the mask image
        # @param prompt [String] Description of the desired edit
        # @param options [Hash] Additional options (model, size, etc.)
        # @return [ImageEditResult] The result containing edited image
        def call(image:, mask:, prompt:, **options)
          new(image: image, mask: mask, prompt: prompt, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@size, @size)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
          subclass.instance_variable_set(:@content_policy, @content_policy)
        end
      end

      attr_reader :image, :mask, :prompt, :options, :tenant_id

      # Initialize a new image editor instance
      #
      # @param image [String, IO] Source image (path, URL, or IO object)
      # @param mask [String, IO] Mask image (path, URL, or IO object)
      # @param prompt [String] Description of the desired edit
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [String] :size Output image size
      # @option options [Integer] :count Number of edits to generate
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, mask:, prompt:, **options)
        @image = image
        @mask = mask
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      # Execute the image edit
      #
      # @return [ImageEditResult] The result containing edited image
      def call
        execute
      end
    end
  end
end
