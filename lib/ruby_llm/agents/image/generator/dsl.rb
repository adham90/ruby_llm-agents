# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      # DSL for configuring image generators
      #
      # Provides class-level methods to configure model, size, quality,
      # style, and other image generation parameters.
      #
      # @example
      #   class ProductImageGenerator < RubyLLM::Agents::ImageGenerator
      #     model "gpt-image-1"
      #     size "1024x1024"
      #     quality "hd"
      #     style "vivid"
      #     content_policy :strict
      #     cache_for 1.hour
      #   end
      #
      module DSL
        # Set or get the model
        #
        # @param value [String, nil] Model identifier
        # @return [String] The model to use
        def model(value = nil)
          if value
            @model = value
          else
            @model || inherited_or_default(:model, config.default_image_model)
          end
        end

        # Set or get the image size
        #
        # @param value [String, nil] Size (e.g., "1024x1024", "1792x1024")
        # @return [String] The size to use
        def size(value = nil)
          if value
            @size = value
          else
            @size || inherited_or_default(:size, config.default_image_size)
          end
        end

        # Set or get the quality level
        #
        # @param value [String, nil] Quality ("standard", "hd")
        # @return [String] The quality to use
        def quality(value = nil)
          if value
            @quality = value
          else
            @quality || inherited_or_default(:quality, config.default_image_quality)
          end
        end

        # Set or get the style preset
        #
        # @param value [String, nil] Style ("vivid", "natural")
        # @return [String] The style to use
        def style(value = nil)
          if value
            @style = value
          else
            @style || inherited_or_default(:style, config.default_image_style)
          end
        end

        # Set or get the version
        #
        # @param value [String, nil] Version identifier
        # @return [String] The version
        def version(value = nil)
          if value
            @version = value
          else
            @version || inherited_or_default(:version, "v1")
          end
        end

        # Set or get the description
        #
        # @param value [String, nil] Description of this generator
        # @return [String, nil] The description
        def description(value = nil)
          if value
            @description = value
          else
            @description || inherited_or_default(:description, nil)
          end
        end

        # Enable caching with the given TTL
        #
        # @param ttl [ActiveSupport::Duration, Integer] Cache duration
        def cache_for(ttl)
          @cache_ttl = ttl
        end

        # Get the cache TTL
        #
        # @return [ActiveSupport::Duration, Integer, nil] The cache TTL
        def cache_ttl
          @cache_ttl || inherited_or_default(:cache_ttl, nil)
        end

        # Check if caching is enabled
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          !cache_ttl.nil?
        end

        # Set or get the content policy level
        #
        # @param level [Symbol, nil] Policy level (:none, :standard, :moderate, :strict)
        # @return [Symbol] The content policy level
        def content_policy(level = nil)
          if level
            @content_policy = level
          else
            @content_policy || inherited_or_default(:content_policy, :standard)
          end
        end

        # Provider-specific options

        # Set or get negative prompt (things to avoid in generation)
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

        # Set or get the seed for reproducible generation
        #
        # @param value [Integer, nil] Seed value
        # @return [Integer, nil] The seed
        def seed(value = nil)
          if value
            @seed = value
          else
            @seed || inherited_or_default(:seed, nil)
          end
        end

        # Set or get guidance scale (CFG scale)
        #
        # @param value [Float, nil] Guidance scale (typically 1.0-20.0)
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

        private

        def config
          RubyLLM::Agents.configuration
        end

        def inherited_or_default(attribute, default)
          if superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end
      end
    end
  end
end
