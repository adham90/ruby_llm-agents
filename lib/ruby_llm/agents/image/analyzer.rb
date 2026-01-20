# frozen_string_literal: true

require_relative "analyzer/dsl"
require_relative "analyzer/execution"

module RubyLLM
  module Agents
    # Image analyzer for understanding and captioning images
    #
    # Analyzes images using vision models to extract captions, tags,
    # descriptions, detected objects, and color information.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageAnalyzer.call(image: "path/to/photo.jpg")
    #   result.caption     # => "A sunset over mountains"
    #   result.tags        # => [:nature, :sunset, :mountains]
    #   result.description # => "A detailed description..."
    #
    # @example Custom analyzer class
    #   class ProductAnalyzer < RubyLLM::Agents::ImageAnalyzer
    #     model "gpt-4o"
    #     analysis_type :detailed
    #     extract_colors true
    #     detect_objects true
    #
    #     description "Analyzes product photos"
    #   end
    #
    #   result = ProductAnalyzer.call(image: product_photo)
    #   result.objects  # => [{name: "laptop", confidence: 0.98, bbox: [...]}]
    #   result.colors   # => [{hex: "#C0C0C0", name: "silver", percentage: 45}]
    #
    class ImageAnalyzer
      extend DSL
      include Execution

      class << self
        # Execute image analysis
        #
        # @param image [String, IO] Path, URL, or IO object of the image to analyze
        # @param options [Hash] Additional options (model, analysis_type, etc.)
        # @return [ImageAnalysisResult] The result containing analysis data
        def call(image:, **options)
          new(image: image, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@analysis_type, @analysis_type)
          subclass.instance_variable_set(:@extract_colors, @extract_colors)
          subclass.instance_variable_set(:@detect_objects, @detect_objects)
          subclass.instance_variable_set(:@extract_text, @extract_text)
          subclass.instance_variable_set(:@custom_prompt, @custom_prompt)
          subclass.instance_variable_set(:@max_tags, @max_tags)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
        end
      end

      attr_reader :image, :options, :tenant_id

      # Initialize a new image analyzer instance
      #
      # @param image [String, IO] Image to analyze (path, URL, or IO object)
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [Symbol] :analysis_type Type of analysis (:caption, :detailed, :tags, :objects)
      # @option options [Boolean] :extract_colors Whether to extract color information
      # @option options [Boolean] :detect_objects Whether to detect objects
      # @option options [Boolean] :extract_text Whether to extract text (OCR)
      # @option options [String] :custom_prompt Custom analysis prompt
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      # Execute the image analysis
      #
      # @return [ImageAnalysisResult] The result containing analysis data
      def call
        execute
      end
    end
  end
end
