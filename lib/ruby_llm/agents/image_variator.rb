# frozen_string_literal: true

require_relative "image_variator/dsl"
require_relative "image_variator/execution"

module RubyLLM
  module Agents
    # Image variator for generating variations of existing images
    #
    # Creates variations of an input image while maintaining the overall
    # composition and style. Useful for exploring design alternatives
    # or generating A/B test variants.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageVariator.call(image: "path/to/image.png")
    #   result.urls # => ["https://...", ...]
    #
    # @example Custom variator class
    #   class LogoVariator < RubyLLM::Agents::ImageVariator
    #     model "gpt-image-1"
    #     variation_strength 0.3
    #     size "1024x1024"
    #
    #     description "Creates variations of logos"
    #   end
    #
    #   result = LogoVariator.call(image: original_logo, count: 4)
    #
    class ImageVariator
      extend DSL
      include Execution

      class << self
        # Execute image variation with the given source image
        #
        # @param image [String, IO] Path, URL, or IO object of the source image
        # @param options [Hash] Additional options (model, count, size, etc.)
        # @return [ImageVariationResult] The result containing variation images
        def call(image:, **options)
          new(image: image, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@size, @size)
          subclass.instance_variable_set(:@variation_strength, @variation_strength)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
        end
      end

      attr_reader :image, :options, :tenant_id

      # Initialize a new image variator instance
      #
      # @param image [String, IO] Source image (path, URL, or IO object)
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [Integer] :count Number of variations to generate
      # @option options [String] :size Output image size
      # @option options [Float] :variation_strength How different variations should be (0.0-1.0)
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      # Execute the image variation
      #
      # @return [ImageVariationResult] The result containing variation images
      def call
        execute
      end
    end
  end
end
