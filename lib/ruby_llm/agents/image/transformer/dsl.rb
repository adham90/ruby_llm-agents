# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class ImageTransformer
      # DSL for configuring image transformers
      #
      # Provides class-level methods to configure model, strength,
      # and other image transformation parameters.
      #
      # @example
      #   class AnimeTransformer < RubyLLM::Agents::ImageTransformer
      #     model "sdxl"
      #     strength 0.8
      #     size "1024x1024"
      #     template "anime style, {prompt}"
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

        # Set or get the transformation strength
        #
        # Controls how much the image is transformed (0.0-1.0).
        # Lower values preserve more of the original image.
        # Higher values allow more creative freedom.
        #
        # @param value [Float, nil] Strength (0.0-1.0)
        # @return [Float] The transformation strength
        def strength(value = nil)
          if value
            unless value.is_a?(Numeric) && value.between?(0.0, 1.0)
              raise ArgumentError, "Strength must be between 0.0 and 1.0"
            end
            @strength = value.to_f
          else
            @strength || inherited_or_default(:strength, 0.75)
          end
        end

        # Set or get whether to preserve composition
        #
        # When true, maintains the overall structure and layout
        # of the original image.
        #
        # @param value [Boolean, nil] Preserve composition flag
        # @return [Boolean] Whether to preserve composition
        def preserve_composition(value = nil)
          if value.nil?
            result = @preserve_composition
            result = inherited_or_default(:preserve_composition, true) if result.nil?
            result
          else
            @preserve_composition = value
          end
        end

        # Set a prompt template (use {prompt} as placeholder)
        #
        # @param value [String, nil] Template string
        # @return [String, nil] The template
        def template(value = nil)
          if value
            @template_string = value
          else
            @template_string || inherited_or_default(:template_string, nil)
          end
        end

        # Get the template string
        #
        # @return [String, nil] The template string
        def template_string
          @template_string || inherited_or_default(:template_string, nil)
        end

        # Set or get negative prompt
        #
        # @param value [String, nil] Negative prompt text
        # @return [String, nil] The negative prompt
        def negative_prompt(value = nil)
          if value
            @negative_prompt = value
          else
            @negative_prompt || inherited_or_default(:negative_prompt, nil)
          end
        end

        # Set or get guidance scale (CFG scale)
        #
        # @param value [Float, nil] Guidance scale
        # @return [Float, nil] The guidance scale
        def guidance_scale(value = nil)
          if value
            @guidance_scale = value
          else
            @guidance_scale || inherited_or_default(:guidance_scale, nil)
          end
        end

        # Set or get number of inference steps
        #
        # @param value [Integer, nil] Number of steps
        # @return [Integer, nil] The steps
        def steps(value = nil)
          if value
            @steps = value
          else
            @steps || inherited_or_default(:steps, nil)
          end
        end

        private

        def default_model
          config.default_transformer_model || "sdxl"
        end
      end
    end
  end
end
