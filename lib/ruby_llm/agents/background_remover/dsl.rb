# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class BackgroundRemover
      # DSL for configuring background removers
      #
      # Provides class-level methods to configure model, output format,
      # and edge refinement options.
      #
      # @example
      #   class ProductBackgroundRemover < RubyLLM::Agents::BackgroundRemover
      #     model "rembg"
      #     output_format :png
      #     refine_edges true
      #     alpha_matting true
      #   end
      #
      module DSL
        include Concerns::ImageOperationDSL

        VALID_OUTPUT_FORMATS = %i[png webp].freeze

        # Set or get the output format
        #
        # @param value [Symbol, nil] Output format (:png, :webp)
        # @return [Symbol] The output format
        def output_format(value = nil)
          if value
            unless VALID_OUTPUT_FORMATS.include?(value)
              raise ArgumentError, "Output format must be one of: #{VALID_OUTPUT_FORMATS.join(', ')}"
            end
            @output_format = value
          else
            @output_format || inherited_or_default(:output_format, :png)
          end
        end

        # Set or get whether to refine edges
        #
        # When enabled, applies additional processing to smooth
        # and refine the edges of the extracted subject.
        #
        # @param value [Boolean, nil] Enable edge refinement
        # @return [Boolean] Whether edge refinement is enabled
        def refine_edges(value = nil)
          if value.nil?
            result = @refine_edges
            result = inherited_or_default(:refine_edges, false) if result.nil?
            result
          else
            @refine_edges = value
          end
        end

        # Set or get whether to use alpha matting
        #
        # Alpha matting produces better results for hair, fur,
        # and semi-transparent elements but is slower.
        #
        # @param value [Boolean, nil] Enable alpha matting
        # @return [Boolean] Whether alpha matting is enabled
        def alpha_matting(value = nil)
          if value.nil?
            result = @alpha_matting
            result = inherited_or_default(:alpha_matting, false) if result.nil?
            result
          else
            @alpha_matting = value
          end
        end

        # Set or get the foreground threshold
        #
        # Pixels with confidence above this threshold are considered
        # foreground. Lower values include more pixels.
        #
        # @param value [Float, nil] Threshold (0.0-1.0)
        # @return [Float] The foreground threshold
        def foreground_threshold(value = nil)
          if value
            unless value.is_a?(Numeric) && value.between?(0.0, 1.0)
              raise ArgumentError, "Foreground threshold must be between 0.0 and 1.0"
            end
            @foreground_threshold = value.to_f
          else
            @foreground_threshold || inherited_or_default(:foreground_threshold, 0.5)
          end
        end

        # Set or get the background threshold
        #
        # Pixels with confidence below this threshold are considered
        # background. Higher values exclude more pixels.
        #
        # @param value [Float, nil] Threshold (0.0-1.0)
        # @return [Float] The background threshold
        def background_threshold(value = nil)
          if value
            unless value.is_a?(Numeric) && value.between?(0.0, 1.0)
              raise ArgumentError, "Background threshold must be between 0.0 and 1.0"
            end
            @background_threshold = value.to_f
          else
            @background_threshold || inherited_or_default(:background_threshold, 0.5)
          end
        end

        # Set or get the erode size
        #
        # Size of morphological erosion applied to shrink the mask
        # slightly to avoid edge artifacts.
        #
        # @param value [Integer, nil] Erode size in pixels
        # @return [Integer] The erode size
        def erode_size(value = nil)
          if value
            unless value.is_a?(Integer) && value >= 0
              raise ArgumentError, "Erode size must be a non-negative integer"
            end
            @erode_size = value
          else
            @erode_size || inherited_or_default(:erode_size, 0)
          end
        end

        # Set or get whether to return the mask
        #
        # When enabled, the result will include the segmentation mask
        # in addition to the extracted foreground.
        #
        # @param value [Boolean, nil] Return segmentation mask
        # @return [Boolean] Whether to return the mask
        def return_mask(value = nil)
          if value.nil?
            result = @return_mask
            result = inherited_or_default(:return_mask, false) if result.nil?
            result
          else
            @return_mask = value
          end
        end

        private

        def default_model
          config.default_background_remover_model || "rembg"
        end
      end
    end
  end
end
