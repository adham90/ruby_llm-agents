# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for image pipeline operations
    #
    # Provides access to individual step results, aggregated costs,
    # timing information, and the final processed image.
    #
    # @example Accessing pipeline results
    #   result = ProductPipeline.call(prompt: "Laptop photo")
    #   result.success?        # => true
    #   result.final_image     # => The final processed image URL/data
    #   result.total_cost      # => Combined cost of all steps
    #   result.steps           # => Array of step results
    #
    # @example Accessing specific step results
    #   result.step(:generate)   # => ImageGenerationResult
    #   result.step(:upscale)    # => ImageUpscaleResult
    #   result.step(:analyze)    # => ImageAnalysisResult
    #   result.analysis          # => Shortcut to analyzer step result
    #
    class ImagePipelineResult
      attr_reader :step_results, :started_at, :completed_at, :tenant_id,
                  :pipeline_class, :context, :error_class, :error_message

      # Initialize a new pipeline result
      #
      # @param step_results [Array<Hash>] Array of step result hashes
      # @param started_at [Time] When pipeline started
      # @param completed_at [Time] When pipeline completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param pipeline_class [String] Name of the pipeline class
      # @param context [Hash] Pipeline context
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(step_results:, started_at:, completed_at:, tenant_id:,
                     pipeline_class:, context:, error_class: nil, error_message: nil)
        @step_results = step_results
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @pipeline_class = pipeline_class
        @context = context
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      # Check if pipeline completed successfully
      #
      # @return [Boolean] true if all steps succeeded
      def success?
        return false if error_class

        step_results.all? { |s| s[:result]&.success? }
      end

      # Check if pipeline had any errors
      #
      # @return [Boolean] true if any step failed
      def error?
        !success?
      end

      # Check if pipeline completed (with or without errors)
      #
      # @return [Boolean] true if pipeline finished
      def completed?
        !error_class || step_results.any?
      end

      # Check if pipeline was partially successful
      #
      # @return [Boolean] true if some steps succeeded but not all
      def partial?
        return false if error_class && step_results.empty?

        has_success = step_results.any? { |s| s[:result]&.success? }
        has_error = step_results.any? { |s| s[:result]&.error? }
        has_success && has_error
      end

      # Step access

      # Get all steps as array
      #
      # @return [Array<Hash>] Array of step result hashes
      def steps
        step_results
      end

      # Get a specific step result by name
      #
      # @param name [Symbol] Step name
      # @return [Object, nil] The step result or nil
      def step(name)
        step_data = step_results.find { |s| s[:name] == name }
        step_data&.dig(:result)
      end

      alias [] step

      # Get step names
      #
      # @return [Array<Symbol>] Array of step names
      def step_names
        step_results.map { |s| s[:name] }
      end

      # Count helpers

      # Total number of steps in pipeline
      #
      # @return [Integer] Step count
      def step_count
        step_results.size
      end

      # Number of successful steps
      #
      # @return [Integer] Successful step count
      def successful_step_count
        step_results.count { |s| s[:result]&.success? }
      end

      # Number of failed steps
      #
      # @return [Integer] Failed step count
      def failed_step_count
        step_results.count { |s| s[:result]&.error? }
      end

      # Image access

      # Get the final image from the last successful image-producing step
      #
      # @return [String, nil] URL or data of final image
      def final_image
        # Find last successful step that produces an image (not analyzer)
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success?
        end
        return nil unless image_step

        result = image_step[:result]
        result.url || result.data
      end

      # Get the final image URL
      #
      # @return [String, nil] URL of final image
      def url
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success? && s[:result].respond_to?(:url)
        end
        image_step&.dig(:result)&.url
      end

      # Get the final image data
      #
      # @return [String, nil] Base64 data of final image
      def data
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success? && s[:result].respond_to?(:data)
        end
        image_step&.dig(:result)&.data
      end

      # Check if final image is base64 encoded
      #
      # @return [Boolean] true if base64
      def base64?
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success?
        end
        image_step&.dig(:result)&.base64? || false
      end

      # Get the final image as binary blob
      #
      # @return [String, nil] Binary image data
      def to_blob
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success? && s[:result].respond_to?(:to_blob)
        end
        image_step&.dig(:result)&.to_blob
      end

      # Shortcut accessors for common step types

      # Get the analysis result if an analyzer step was run
      #
      # @return [ImageAnalysisResult, nil] Analysis result
      def analysis
        analyzer_step = step_results.find { |s| s[:type] == :analyzer }
        analyzer_step&.dig(:result)
      end

      # Get the generation result if a generator step was run
      #
      # @return [ImageGenerationResult, nil] Generation result
      def generation
        generator_step = step_results.find { |s| s[:type] == :generator }
        generator_step&.dig(:result)
      end

      # Get the upscale result if an upscaler step was run
      #
      # @return [ImageUpscaleResult, nil] Upscale result
      def upscale
        upscaler_step = step_results.find { |s| s[:type] == :upscaler }
        upscaler_step&.dig(:result)
      end

      # Get the transform result if a transformer step was run
      #
      # @return [ImageTransformResult, nil] Transform result
      def transform
        transformer_step = step_results.find { |s| s[:type] == :transformer }
        transformer_step&.dig(:result)
      end

      # Get the background removal result if a remover step was run
      #
      # @return [BackgroundRemovalResult, nil] Removal result
      def background_removal
        remover_step = step_results.find { |s| s[:type] == :remover }
        remover_step&.dig(:result)
      end

      # Timing

      # Pipeline duration in milliseconds
      #
      # @return [Integer] Duration in ms
      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost

      # Total cost of all pipeline steps
      #
      # @return [Float] Combined cost
      def total_cost
        step_results.sum { |s| s[:result]&.total_cost || 0 }
      end

      # Get the primary model ID (from first step)
      #
      # @return [String, nil] Model ID
      def primary_model_id
        first_result = step_results.first&.dig(:result)
        first_result&.model_id
      end

      # File operations

      # Save the final image to a file
      #
      # @param path [String] File path
      # @return [void]
      def save(path)
        image_step = step_results.reverse.find do |s|
          s[:type] != :analyzer && s[:result]&.success? && s[:result].respond_to?(:save)
        end
        raise "No image to save" unless image_step

        image_step[:result].save(path)
      end

      # Save all intermediate images
      #
      # @param directory [String] Directory path
      # @param prefix [String] Filename prefix
      # @return [void]
      def save_all(directory, prefix: "step")
        step_results.each_with_index do |step, idx|
          next if step[:type] == :analyzer
          next unless step[:result]&.success? && step[:result].respond_to?(:save)

          filename = "#{prefix}_#{idx + 1}_#{step[:name]}.png"
          step[:result].save(File.join(directory, filename))
        end
      end

      # Serialization

      # Convert to hash
      #
      # @return [Hash] Hash representation
      def to_h
        {
          success: success?,
          partial: partial?,
          step_count: step_count,
          successful_steps: successful_step_count,
          failed_steps: failed_step_count,
          steps: step_results.map do |s|
            {
              name: s[:name],
              type: s[:type],
              success: s[:result]&.success?,
              cost: s[:result]&.total_cost
            }
          end,
          final_image_url: url,
          total_cost: total_cost,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          pipeline_class: pipeline_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      # Convert to cacheable format
      #
      # @return [Hash] Cacheable hash
      def to_cache
        {
          step_results: step_results.map do |s|
            {
              name: s[:name],
              type: s[:type],
              cached_result: s[:result]&.respond_to?(:to_cache) ? s[:result].to_cache : nil
            }
          end,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      # Restore from cache
      #
      # @param data [Hash] Cached data
      # @return [CachedImagePipelineResult]
      def self.from_cache(data)
        CachedImagePipelineResult.new(data)
      end
    end

    # Lightweight result for cached pipelines
    class CachedImagePipelineResult
      attr_reader :step_results, :total_cost, :cached_at

      def initialize(data)
        @step_results = data[:step_results] || []
        @total_cost = data[:total_cost]
        @cached_at = data[:cached_at]
      end

      def success?
        step_results.any?
      end

      def error?
        !success?
      end

      def cached?
        true
      end

      def step_count
        step_results.size
      end

      def step(name)
        step_data = step_results.find { |s| s[:name] == name }
        step_data&.dig(:cached_result)
      end

      alias [] step

      def final_image
        # Find last non-analyzer step
        image_step = step_results.reverse.find { |s| s[:type] != :analyzer }
        return nil unless image_step

        cached = image_step[:cached_result]
        return nil unless cached

        cached[:urls]&.first || cached[:url] || cached[:datas]&.first || cached[:data]
      end

      def url
        final_image if final_image.is_a?(String) && final_image.start_with?("http")
      end
    end
  end
end
