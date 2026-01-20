# frozen_string_literal: true

require "digest"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class ImageVariator
      # Execution logic for image variators
      #
      # Handles image validation, budget tracking, caching,
      # variation generation, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the image variation pipeline
        #
        # @return [ImageVariationResult] The result containing variation images
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_image!

          # Check cache
          cached = check_cache(ImageVariationResult) if cache_enabled?
          return cached if cached

          # Generate variations
          variations = generate_variations

          # Build result
          result = build_result(
            images: variations,
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
          "image_variation"
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

        def generate_variations
          count = resolve_count

          # Generate variations using the underlying image API
          # Note: The actual implementation depends on the provider
          Array.new(count) do
            generate_single_variation
          end
        end

        def generate_single_variation
          # Use RubyLLM's variation endpoint if available,
          # otherwise use edit with the original image
          if RubyLLM.respond_to?(:create_image_variation)
            RubyLLM.create_image_variation(
              image: image,
              model: resolve_model,
              size: resolve_size,
              **build_variation_options
            )
          else
            # Fallback: Use paint with image reference
            # This approach works for models that support img2img
            RubyLLM.paint(
              "Create a variation of this image",
              model: resolve_model,
              size: resolve_size,
              reference_image: image,
              strength: resolve_variation_strength,
              **build_variation_options
            )
          end
        end

        def build_variation_options
          opts = {}
          opts[:assume_model_exists] = true if options[:assume_model_exists]
          opts
        end

        def build_result(images:, started_at:, completed_at:)
          ImageVariationResult.new(
            images: images,
            source_image: image,
            model_id: resolve_model,
            size: resolve_size,
            variation_strength: resolve_variation_strength,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            variator_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageVariationResult.new(
            images: [],
            source_image: image,
            model_id: resolve_model,
            size: resolve_size,
            variation_strength: resolve_variation_strength,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            variator_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods

        def resolve_size
          options[:size] || self.class.size
        end

        def resolve_variation_strength
          options[:variation_strength] || self.class.variation_strength
        end

        def resolve_count
          options[:count] || 1
        end

        # Cache key components
        def cache_key_components
          [
            "image_variator",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_size,
            resolve_variation_strength.to_s,
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

        def build_execution_metadata(result)
          {
            count: result.count,
            size: result.size,
            variation_strength: result.variation_strength
          }
        end
      end
    end
  end
end
