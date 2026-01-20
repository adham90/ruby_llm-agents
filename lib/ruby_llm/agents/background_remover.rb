# frozen_string_literal: true

require_relative "background_remover/dsl"
require_relative "background_remover/execution"

module RubyLLM
  module Agents
    # Background remover for subject extraction
    #
    # Removes backgrounds from images using segmentation models,
    # producing transparent PNGs or masked outputs.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::BackgroundRemover.call(image: "path/to/photo.jpg")
    #   result.url       # => "https://..." (transparent PNG)
    #   result.has_alpha? # => true
    #
    # @example Custom remover class
    #   class ProductBackgroundRemover < RubyLLM::Agents::BackgroundRemover
    #     model "segment-anything"
    #     output_format :png
    #     refine_edges true
    #     alpha_matting true
    #
    #     description "Removes backgrounds from product photos"
    #   end
    #
    #   result = ProductBackgroundRemover.call(image: product_photo)
    #   result.foreground # => The extracted subject
    #   result.mask       # => Segmentation mask
    #
    class BackgroundRemover
      extend DSL
      include Execution

      class << self
        # Execute background removal
        #
        # @param image [String, IO] Path, URL, or IO object of the source image
        # @param options [Hash] Additional options (model, output_format, etc.)
        # @return [BackgroundRemovalResult] The result containing extracted subject
        def call(image:, **options)
          new(image: image, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@output_format, @output_format)
          subclass.instance_variable_set(:@refine_edges, @refine_edges)
          subclass.instance_variable_set(:@alpha_matting, @alpha_matting)
          subclass.instance_variable_set(:@foreground_threshold, @foreground_threshold)
          subclass.instance_variable_set(:@background_threshold, @background_threshold)
          subclass.instance_variable_set(:@erode_size, @erode_size)
          subclass.instance_variable_set(:@return_mask, @return_mask)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
        end
      end

      attr_reader :image, :options, :tenant_id

      # Initialize a new background remover instance
      #
      # @param image [String, IO] Source image (path, URL, or IO object)
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [Symbol] :output_format Output format (:png, :webp)
      # @option options [Boolean] :refine_edges Enable edge refinement
      # @option options [Boolean] :alpha_matting Enable alpha matting for better edges
      # @option options [Boolean] :return_mask Also return the segmentation mask
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      # Execute the background removal
      #
      # @return [BackgroundRemovalResult] The result containing extracted subject
      def call
        execute
      end
    end
  end
end
