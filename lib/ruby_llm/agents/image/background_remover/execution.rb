# frozen_string_literal: true

require "digest"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class BackgroundRemover
      # Execution logic for background removers
      #
      # Handles image validation, budget tracking, caching,
      # background removal execution, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the background removal pipeline
        #
        # @return [BackgroundRemovalResult] The result containing extracted subject
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_image!

          # Check cache
          cached = check_cache(BackgroundRemovalResult) if cache_enabled?
          return cached if cached

          # Remove background
          removal_result = remove_background

          # Build result
          result = build_result(
            foreground: removal_result[:foreground],
            mask: removal_result[:mask],
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
          "background_removal"
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

        def remove_background
          # Try different approaches based on available capabilities
          if RubyLLM.respond_to?(:remove_background)
            remove_via_ruby_llm
          else
            remove_via_provider
          end
        end

        def remove_via_ruby_llm
          result = RubyLLM.remove_background(
            image: image,
            model: resolve_model,
            **build_removal_options
          )

          {
            foreground: result,
            mask: result.respond_to?(:mask) ? result.mask : nil
          }
        end

        def remove_via_provider
          # Use the model through RubyLLM's paint with segmentation/removal mode
          # This handles models like segment-anything, rembg, etc.
          foreground = RubyLLM.paint(
            "Remove background from this image",
            model: resolve_model,
            image: image,
            mode: "background_removal",
            **build_removal_options
          )

          mask = nil
          if resolve_return_mask
            # Request mask separately if needed
            begin
              mask = RubyLLM.paint(
                "Generate segmentation mask for this image",
                model: resolve_model,
                image: image,
                mode: "segmentation_mask",
                **build_removal_options
              )
            rescue StandardError
              # Mask generation failed, continue without it
              mask = nil
            end
          end

          { foreground: foreground, mask: mask }
        end

        def build_removal_options
          opts = {}
          opts[:output_format] = resolve_output_format
          opts[:refine_edges] = resolve_refine_edges if resolve_refine_edges
          opts[:alpha_matting] = resolve_alpha_matting if resolve_alpha_matting
          opts[:foreground_threshold] = resolve_foreground_threshold
          opts[:background_threshold] = resolve_background_threshold
          opts[:erode_size] = resolve_erode_size if resolve_erode_size > 0
          opts[:return_mask] = resolve_return_mask if resolve_return_mask
          opts[:assume_model_exists] = true if options[:assume_model_exists]
          opts
        end

        def build_result(foreground:, mask:, started_at:, completed_at:)
          BackgroundRemovalResult.new(
            foreground: foreground,
            mask: mask,
            source_image: image,
            model_id: resolve_model,
            output_format: resolve_output_format,
            alpha_matting: resolve_alpha_matting,
            refine_edges: resolve_refine_edges,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            remover_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          BackgroundRemovalResult.new(
            foreground: nil,
            mask: nil,
            source_image: image,
            model_id: resolve_model,
            output_format: resolve_output_format,
            alpha_matting: resolve_alpha_matting,
            refine_edges: resolve_refine_edges,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            remover_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods

        def resolve_output_format
          options[:output_format] || self.class.output_format
        end

        def resolve_refine_edges
          options.fetch(:refine_edges, self.class.refine_edges)
        end

        def resolve_alpha_matting
          options.fetch(:alpha_matting, self.class.alpha_matting)
        end

        def resolve_foreground_threshold
          options[:foreground_threshold] || self.class.foreground_threshold
        end

        def resolve_background_threshold
          options[:background_threshold] || self.class.background_threshold
        end

        def resolve_erode_size
          options[:erode_size] || self.class.erode_size
        end

        def resolve_return_mask
          options.fetch(:return_mask, self.class.return_mask)
        end

        # Cache key components
        def cache_key_components
          [
            "background_remover",
            self.class.name,
            resolve_model,
            resolve_output_format.to_s,
            resolve_alpha_matting.to_s,
            resolve_refine_edges.to_s,
            resolve_foreground_threshold.to_s,
            resolve_background_threshold.to_s,
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
            output_format: result.output_format,
            alpha_matting: result.alpha_matting,
            refine_edges: result.refine_edges,
            has_mask: result.mask?
          }
        end
      end
    end
  end
end
