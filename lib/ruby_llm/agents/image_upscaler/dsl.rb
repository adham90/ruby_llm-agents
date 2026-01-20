# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class ImageUpscaler
      # DSL for configuring image upscalers
      #
      # Provides class-level methods to configure model, scale factor,
      # and other upscaling parameters.
      #
      # @example
      #   class PhotoUpscaler < RubyLLM::Agents::ImageUpscaler
      #     model "real-esrgan"
      #     scale 4
      #     face_enhance true
      #   end
      #
      module DSL
        include Concerns::ImageOperationDSL

        VALID_SCALES = [2, 4, 8].freeze

        # Set or get the upscale factor
        #
        # @param value [Integer, nil] Scale factor (2, 4, or 8)
        # @return [Integer] The scale factor
        def scale(value = nil)
          if value
            unless VALID_SCALES.include?(value)
              raise ArgumentError, "Scale must be one of: #{VALID_SCALES.join(', ')}"
            end
            @scale = value
          else
            @scale || inherited_or_default(:scale, 4)
          end
        end

        # Set or get face enhancement
        #
        # When enabled, applies additional enhancement to detected faces.
        # Uses models like GFPGAN for face restoration.
        #
        # @param value [Boolean, nil] Enable face enhancement
        # @return [Boolean] Whether face enhancement is enabled
        def face_enhance(value = nil)
          if value.nil?
            result = @face_enhance
            result = inherited_or_default(:face_enhance, false) if result.nil?
            result
          else
            @face_enhance = value
          end
        end

        # Set or get denoise strength
        #
        # Controls how much noise reduction is applied.
        # Higher values remove more noise but may lose detail.
        #
        # @param value [Float, nil] Denoise strength (0.0-1.0)
        # @return [Float] The denoise strength
        def denoise_strength(value = nil)
          if value
            unless value.is_a?(Numeric) && value.between?(0.0, 1.0)
              raise ArgumentError, "Denoise strength must be between 0.0 and 1.0"
            end
            @denoise_strength = value.to_f
          else
            @denoise_strength || inherited_or_default(:denoise_strength, 0.5)
          end
        end

        private

        def default_model
          config.default_upscaler_model || "real-esrgan"
        end
      end
    end
  end
end
