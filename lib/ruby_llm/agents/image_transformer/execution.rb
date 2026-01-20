# frozen_string_literal: true

require "digest"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class ImageTransformer
      # Execution logic for image transformers
      #
      # Handles image validation, content policy checks, budget tracking,
      # caching, image transformation, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the image transformation pipeline
        #
        # @return [ImageTransformResult] The result containing transformed image
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_inputs!
          validate_content_policy!

          # Check cache
          cached = check_cache(ImageTransformResult) if cache_enabled?
          return cached if cached

          # Transform image(s)
          transformed_images = transform_images

          # Build result
          result = build_result(
            images: transformed_images,
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
          "image_transform"
        end

        def validate_inputs!
          raise ArgumentError, "Image cannot be blank" if image.nil?
          raise ArgumentError, "Prompt cannot be blank" if prompt.nil? || prompt.strip.empty?

          # Validate image exists if it's a path
          if image.is_a?(String) && !image.start_with?("http")
            unless File.exist?(image)
              raise ArgumentError, "Image file does not exist: #{image}"
            end
          end

          # Validate prompt length
          max_length = config.max_image_prompt_length || 4000
          if prompt.length > max_length
            raise ArgumentError, "Prompt exceeds maximum length of #{max_length} characters"
          end
        end

        def validate_content_policy!
          policy = self.class.content_policy
          return if policy == :none || policy == :standard

          ImageGenerator::ContentPolicy.validate!(prompt, policy)
        end

        def transform_images
          count = resolve_count

          Array.new(count) do
            transform_single_image
          end
        end

        def transform_single_image
          final_prompt = apply_template(prompt)

          # Use img2img/transformation API
          RubyLLM.paint(
            final_prompt,
            model: resolve_model,
            size: resolve_size,
            image: image,
            strength: resolve_strength,
            **build_transform_options
          )
        end

        def apply_template(text)
          template = self.class.template_string
          return text unless template

          template.gsub("{prompt}", text)
        end

        def build_transform_options
          opts = {}
          opts[:negative_prompt] = resolve_negative_prompt if resolve_negative_prompt
          opts[:guidance_scale] = resolve_guidance_scale if resolve_guidance_scale
          opts[:steps] = resolve_steps if resolve_steps
          opts[:preserve_composition] = resolve_preserve_composition
          opts[:assume_model_exists] = true if options[:assume_model_exists]
          opts
        end

        def build_result(images:, started_at:, completed_at:)
          ImageTransformResult.new(
            images: images,
            source_image: image,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            strength: resolve_strength,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            transformer_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageTransformResult.new(
            images: [],
            source_image: image,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            strength: resolve_strength,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            transformer_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods

        def resolve_size
          options[:size] || self.class.size
        end

        def resolve_strength
          options[:strength] || self.class.strength
        end

        def resolve_preserve_composition
          options.fetch(:preserve_composition, self.class.preserve_composition)
        end

        def resolve_negative_prompt
          options[:negative_prompt] || self.class.negative_prompt
        end

        def resolve_guidance_scale
          options[:guidance_scale] || self.class.guidance_scale
        end

        def resolve_steps
          options[:steps] || self.class.steps
        end

        def resolve_count
          options[:count] || 1
        end

        # Cache key components
        def cache_key_components
          [
            "image_transformer",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_size,
            resolve_strength.to_s,
            Digest::SHA256.hexdigest(prompt),
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
            strength: result.strength,
            prompt_length: prompt.length
          }
        end
      end
    end
  end
end
