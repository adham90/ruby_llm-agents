# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      # Prompt template support for image generators
      #
      # Allows defining reusable prompt templates that wrap user input
      # with consistent styling, quality, or context instructions.
      #
      # @example Using templates in a generator
      #   class ProductPhotoGenerator < RubyLLM::Agents::ImageGenerator
      #     model "gpt-image-1"
      #     template "Professional product photography of {prompt}, " \
      #              "white background, studio lighting, 8k resolution"
      #   end
      #
      #   result = ProductPhotoGenerator.call(prompt: "a red sneaker")
      #   # Actual prompt: "Professional product photography of a red sneaker, ..."
      #
      # @example Template with multiple placeholders
      #   class StyleTransferGenerator < RubyLLM::Agents::ImageGenerator
      #     def build_prompt
      #       Templates.apply(
      #         "{prompt} in the style of {style}, detailed, high quality",
      #         prompt: @prompt,
      #         style: options[:style] || "impressionism"
      #       )
      #     end
      #   end
      #
      module Templates
        # Common prompt templates for different use cases
        PRESETS = {
          # Photography styles
          product: "Professional product photography of {prompt}, " \
                   "white background, studio lighting, high resolution, commercial quality",

          portrait: "Professional portrait of {prompt}, " \
                    "soft lighting, shallow depth of field, 85mm lens, studio quality",

          landscape: "Stunning landscape photograph of {prompt}, " \
                     "golden hour lighting, dramatic sky, high dynamic range",

          # Artistic styles
          watercolor: "Watercolor painting of {prompt}, " \
                      "soft brushstrokes, muted colors, artistic, on textured paper",

          oil_painting: "Oil painting of {prompt}, " \
                        "rich colors, visible brushwork, classical style, museum quality",

          digital_art: "Digital art of {prompt}, " \
                       "vibrant colors, detailed, trending on artstation, 4k",

          anime: "Anime style illustration of {prompt}, " \
                 "detailed, Studio Ghibli inspired, beautiful lighting",

          # Technical styles
          isometric: "Isometric 3D render of {prompt}, " \
                     "clean lines, bright colors, game asset style",

          blueprint: "Technical blueprint of {prompt}, " \
                     "detailed engineering drawing, white lines on blue background",

          wireframe: "3D wireframe render of {prompt}, " \
                     "clean geometric lines, technical visualization",

          # UI/Design
          icon: "App icon design of {prompt}, " \
                "flat design, bold colors, minimal, iOS style, high resolution",

          logo: "Minimalist logo design for {prompt}, " \
                "clean lines, professional, vector style, brand identity",

          ui_mockup: "Modern UI mockup of {prompt}, " \
                     "clean design, shadows, glass morphism, Figma style"
        }.freeze

        class << self
          # Apply a template to a prompt with variable substitution
          #
          # @param template [String] Template string with {placeholder} syntax
          # @param vars [Hash] Variables to substitute
          # @return [String] The rendered template
          def apply(template, **vars)
            result = template.dup
            vars.each do |key, value|
              result.gsub!("{#{key}}", value.to_s)
            end
            result
          end

          # Get a preset template by name
          #
          # @param name [Symbol] Preset name
          # @return [String, nil] The template string or nil
          def preset(name)
            PRESETS[name.to_sym]
          end

          # List all available preset names
          #
          # @return [Array<Symbol>] Preset names
          def preset_names
            PRESETS.keys
          end

          # Apply a preset template to a prompt
          #
          # @param name [Symbol] Preset name
          # @param prompt [String] User prompt
          # @return [String] Rendered template
          # @raise [ArgumentError] If preset not found
          def apply_preset(name, prompt)
            template = preset(name)
            raise ArgumentError, "Unknown template preset: #{name}" unless template

            apply(template, prompt: prompt)
          end
        end
      end
    end
  end
end
