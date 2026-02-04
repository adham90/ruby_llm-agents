# frozen_string_literal: true

require "digest"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class ImageUpscaler
      # Execution logic for image upscalers
      #
      # Handles image validation, budget tracking, caching,
      # upscaling execution, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the image upscaling pipeline
        #
        # @return [ImageUpscaleResult] The result containing upscaled image
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_image!

          # Check cache
          cached = check_cache(ImageUpscaleResult) if cache_enabled?
          return cached if cached

          # Upscale image
          upscaled_image = upscale_image

          # Build result
          result = build_result(
            image: upscaled_image,
            started_at: started_at,
            completed_at: Time.current
          )

          # Cache result
          write_cache(result) if cache_enabled?

          # Track execution
          record_execution(result) if execution_tracking_enabled?

          result
        rescue StandardError => e
          record_failed_execution(e, started_at) if execution_tracking_enabled?
          build_error_result(e, started_at)
        end

        private

        def execution_type
          "image_upscale"
        end

        def validate_image!
          raise ArgumentError, "Image cannot be blank" if image.nil?

          # Validate image exists if it's a path
          if image.is_a?(String) && !image.start_with?("http")
            unless File.exist?(image)
              raise ArgumentError, "Image file does not exist: #{image}"
            end
          end
        end

        def upscale_image
          # Use RubyLLM's upscale endpoint if available
          if RubyLLM.respond_to?(:upscale_image)
            RubyLLM.upscale_image(
              image: image,
              model: resolve_model,
              scale: resolve_scale,
              **build_upscale_options
            )
          else
            # For models that support upscaling through custom endpoints
            # This would typically be handled by a Replicate or custom provider
            upscale_via_provider
          end
        end

        def upscale_via_provider
          # Attempt to use the model through RubyLLM's paint with upscale mode
          # This is a fallback for when direct upscale isn't supported
          RubyLLM.paint(
            "Upscale this image",
            model: resolve_model,
            image: image,
            upscale_factor: resolve_scale,
            face_enhance: resolve_face_enhance,
            denoise_strength: resolve_denoise_strength,
            **build_upscale_options
          )
        end

        def build_upscale_options
          opts = {}
          opts[:face_enhance] = resolve_face_enhance if resolve_face_enhance
          opts[:denoise_strength] = resolve_denoise_strength if resolve_denoise_strength
          opts[:assume_model_exists] = true if options[:assume_model_exists]
          opts
        end

        def build_result(image:, started_at:, completed_at:)
          # Calculate output size based on scale
          output_size = calculate_output_size

          ImageUpscaleResult.new(
            image: image,
            source_image: self.image,
            model_id: resolve_model,
            scale: resolve_scale,
            output_size: output_size,
            face_enhance: resolve_face_enhance,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            upscaler_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageUpscaleResult.new(
            image: nil,
            source_image: self.image,
            model_id: resolve_model,
            scale: resolve_scale,
            output_size: nil,
            face_enhance: resolve_face_enhance,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            upscaler_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        def calculate_output_size
          input_size = get_input_image_size
          return nil unless input_size

          width, height = input_size
          scale = resolve_scale
          "#{width * scale}x#{height * scale}"
        end

        def get_input_image_size
          return nil unless image.is_a?(String) && File.exist?(image)

          # Try to get image dimensions
          # This requires an image processing library like MiniMagick or ImageMagick
          if defined?(MiniMagick)
            img = MiniMagick::Image.open(image)
            [img.width, img.height]
          elsif defined?(Vips)
            img = Vips::Image.new_from_file(image)
            [img.width, img.height]
          else
            nil
          end
        rescue StandardError
          nil
        end

        # Resolution methods

        def resolve_scale
          options[:scale] || self.class.scale
        end

        def resolve_face_enhance
          options.fetch(:face_enhance, self.class.face_enhance)
        end

        def resolve_denoise_strength
          options[:denoise_strength] || self.class.denoise_strength
        end

        # Cache key components
        def cache_key_components
          [
            "image_upscaler",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_scale.to_s,
            resolve_face_enhance.to_s,
            Digest::SHA256.hexdigest(image_digest)
          ]
        end

        def image_digest
          if image.is_a?(String) && File.exist?(image)
            File.read(image)
          elsif image.respond_to?(:read)
            content = image.read
            image.rewind if image.respond_to?(:rewind)
            content
          else
            image.to_s
          end
        end

        def build_metadata(result)
          {
            scale: result.scale,
            output_size: result.output_size,
            face_enhance: result.face_enhance
          }
        end
      end
    end
  end
end
