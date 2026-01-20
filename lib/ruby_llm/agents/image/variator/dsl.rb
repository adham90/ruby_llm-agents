# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class ImageVariator
      # DSL for configuring image variators
      #
      # Provides class-level methods to configure model, size,
      # variation strength, and other image variation parameters.
      #
      # @example
      #   class LogoVariator < RubyLLM::Agents::ImageVariator
      #     model "gpt-image-1"
      #     size "1024x1024"
      #     variation_strength 0.3
      #     cache_for 1.hour
      #   end
      #
      module DSL
        include Concerns::ImageOperationDSL

        # Set or get the output image size
        #
        # @param value [String, nil] Size (e.g., "1024x1024")
        # @return [String] The size to use
        def size(value = nil)
          if value
            @size = value
          else
            @size || inherited_or_default(:size, config.default_image_size)
          end
        end

        # Set or get the variation strength
        #
        # Controls how different variations should be from the original.
        # Higher values produce more diverse variations.
        #
        # @param value [Float, nil] Strength (0.0-1.0)
        # @return [Float] The variation strength
        def variation_strength(value = nil)
          if value
            unless value.is_a?(Numeric) && value.between?(0.0, 1.0)
              raise ArgumentError, "Variation strength must be between 0.0 and 1.0"
            end
            @variation_strength = value.to_f
          else
            @variation_strength || inherited_or_default(:variation_strength, 0.5)
          end
        end

        private

        def default_model
          config.default_variator_model || config.default_image_model
        end
      end
    end
  end
end
