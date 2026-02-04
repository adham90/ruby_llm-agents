# frozen_string_literal: true

require "digest"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class ImageEditor
      # Execution logic for image editors
      #
      # Handles image/mask validation, content policy checks,
      # budget tracking, caching, image editing, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the image editing pipeline
        #
        # @return [ImageEditResult] The result containing edited image
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_inputs!

          # Check cache
          cached = check_cache(ImageEditResult) if cache_enabled?
          return cached if cached

          # Edit image(s)
          edited_images = edit_images

          # Build result
          result = build_result(
            images: edited_images,
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
          "image_edit"
        end

        def validate_inputs!
          raise ArgumentError, "Image cannot be blank" if image.nil?
          raise ArgumentError, "Mask cannot be blank" if mask.nil?
          raise ArgumentError, "Prompt cannot be blank" if prompt.nil? || prompt.strip.empty?

          # Validate image exists if it's a path
          validate_file_exists!(image, "Image")
          validate_file_exists!(mask, "Mask")

          # Validate prompt length
          max_length = config.max_image_prompt_length || 4000
          if prompt.length > max_length
            raise ArgumentError, "Prompt exceeds maximum length of #{max_length} characters"
          end
        end

        def validate_file_exists!(file, name)
          return unless file.is_a?(String) && !file.start_with?("http")

          unless File.exist?(file)
            raise ArgumentError, "#{name} file does not exist: #{file}"
          end
        end

        def edit_images
          count = resolve_count

          Array.new(count) do
            edit_single_image
          end
        end

        def edit_single_image
          # Use RubyLLM's edit endpoint if available
          if RubyLLM.respond_to?(:edit_image)
            RubyLLM.edit_image(
              image: image,
              mask: mask,
              prompt: prompt,
              model: resolve_model,
              size: resolve_size,
              **build_edit_options
            )
          else
            # Fallback: Some providers may use paint with mask support
            RubyLLM.paint(
              prompt,
              model: resolve_model,
              size: resolve_size,
              image: image,
              mask: mask,
              **build_edit_options
            )
          end
        end

        def build_edit_options
          opts = {}
          opts[:assume_model_exists] = true if options[:assume_model_exists]
          opts
        end

        def build_result(images:, started_at:, completed_at:)
          ImageEditResult.new(
            images: images,
            source_image: image,
            mask: mask,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            editor_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageEditResult.new(
            images: [],
            source_image: image,
            mask: mask,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            editor_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods

        def resolve_size
          options[:size] || self.class.size
        end

        def resolve_count
          options[:count] || 1
        end

        # Cache key components
        def cache_key_components
          [
            "image_editor",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_size,
            Digest::SHA256.hexdigest(prompt),
            Digest::SHA256.hexdigest(image_digest(image)),
            Digest::SHA256.hexdigest(image_digest(mask))
          ]
        end

        def image_digest(file)
          if file.is_a?(String) && File.exist?(file)
            File.read(file)
          elsif file.respond_to?(:read)
            content = file.read
            file.rewind if file.respond_to?(:rewind)
            content
          else
            file.to_s
          end
        end

        def build_metadata(result)
          {
            count: result.count,
            size: result.size,
            prompt_length: prompt.length
          }
        end
      end
    end
  end
end
