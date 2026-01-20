# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class ImageAnalyzer
      # DSL for configuring image analyzers
      #
      # Provides class-level methods to configure model, analysis type,
      # and feature extraction options.
      #
      # @example
      #   class ProductAnalyzer < RubyLLM::Agents::ImageAnalyzer
      #     model "gpt-4o"
      #     analysis_type :detailed
      #     extract_colors true
      #     detect_objects true
      #     max_tags 20
      #   end
      #
      module DSL
        include Concerns::ImageOperationDSL

        VALID_ANALYSIS_TYPES = %i[caption detailed tags objects colors all].freeze

        # Set or get the analysis type
        #
        # @param value [Symbol, nil] Analysis type (:caption, :detailed, :tags, :objects, :colors, :all)
        # @return [Symbol] The analysis type
        def analysis_type(value = nil)
          if value
            unless VALID_ANALYSIS_TYPES.include?(value)
              raise ArgumentError, "Analysis type must be one of: #{VALID_ANALYSIS_TYPES.join(', ')}"
            end
            @analysis_type = value
          else
            @analysis_type || inherited_or_default(:analysis_type, :detailed)
          end
        end

        # Set or get whether to extract colors
        #
        # When enabled, extracts dominant colors from the image with
        # hex values, names, and percentages.
        #
        # @param value [Boolean, nil] Enable color extraction
        # @return [Boolean] Whether color extraction is enabled
        def extract_colors(value = nil)
          if value.nil?
            result = @extract_colors
            result = inherited_or_default(:extract_colors, false) if result.nil?
            result
          else
            @extract_colors = value
          end
        end

        # Set or get whether to detect objects
        #
        # When enabled, detects and identifies objects in the image
        # with bounding boxes and confidence scores.
        #
        # @param value [Boolean, nil] Enable object detection
        # @return [Boolean] Whether object detection is enabled
        def detect_objects(value = nil)
          if value.nil?
            result = @detect_objects
            result = inherited_or_default(:detect_objects, false) if result.nil?
            result
          else
            @detect_objects = value
          end
        end

        # Set or get whether to extract text (OCR)
        #
        # When enabled, extracts text visible in the image using OCR.
        #
        # @param value [Boolean, nil] Enable text extraction
        # @return [Boolean] Whether text extraction is enabled
        def extract_text(value = nil)
          if value.nil?
            result = @extract_text
            result = inherited_or_default(:extract_text, false) if result.nil?
            result
          else
            @extract_text = value
          end
        end

        # Set or get a custom analysis prompt
        #
        # Allows specifying a custom prompt for the vision model
        # to customize what information is extracted.
        #
        # @param value [String, nil] Custom prompt
        # @return [String, nil] The custom prompt
        def custom_prompt(value = nil)
          if value
            @custom_prompt = value
          else
            @custom_prompt || inherited_or_default(:custom_prompt, nil)
          end
        end

        # Set or get maximum number of tags
        #
        # @param value [Integer, nil] Maximum tags to return
        # @return [Integer] The maximum number of tags
        def max_tags(value = nil)
          if value
            unless value.is_a?(Integer) && value > 0
              raise ArgumentError, "Max tags must be a positive integer"
            end
            @max_tags = value
          else
            @max_tags || inherited_or_default(:max_tags, 10)
          end
        end

        private

        def default_model
          config.default_analyzer_model || "gpt-4o"
        end
      end
    end
  end
end
