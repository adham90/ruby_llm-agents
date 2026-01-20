# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for image upscaling operations
    #
    # Provides a consistent interface for accessing upscaled images,
    # metadata, timing, and cost information.
    #
    # @example Accessing upscaled image
    #   result = ImageUpscaler.call(image: "low_res.jpg", scale: 4)
    #   result.url          # => "https://..."
    #   result.scale        # => 4
    #   result.output_size  # => "4096x4096"
    #   result.success?     # => true
    #
    class ImageUpscaleResult
      attr_reader :image, :source_image, :model_id, :scale, :output_size, :face_enhance,
                  :started_at, :completed_at, :tenant_id, :upscaler_class,
                  :error_class, :error_message

      # Initialize a new result
      #
      # @param image [Object] The upscaled image object
      # @param source_image [String] The original source image
      # @param model_id [String] Model used for upscaling
      # @param scale [Integer] Upscale factor used
      # @param output_size [String] Output image dimensions
      # @param face_enhance [Boolean] Whether face enhancement was used
      # @param started_at [Time] When upscaling started
      # @param completed_at [Time] When upscaling completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param upscaler_class [String] Name of the upscaler class
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(image:, source_image:, model_id:, scale:, output_size:, face_enhance:,
                     started_at:, completed_at:, tenant_id:, upscaler_class:,
                     error_class: nil, error_message: nil)
        @image = image
        @source_image = source_image
        @model_id = model_id
        @scale = scale
        @output_size = output_size
        @face_enhance = face_enhance
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @upscaler_class = upscaler_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      def success?
        error_class.nil? && !image.nil?
      end

      def error?
        !success?
      end

      # Always single image for upscaling
      def single?
        true
      end

      def batch?
        false
      end

      # Image access

      def url
        image&.url
      end

      def urls
        success? ? [url].compact : []
      end

      def data
        image&.data
      end

      def datas
        success? ? [data].compact : []
      end

      def base64?
        image&.base64? || false
      end

      def mime_type
        image&.mime_type
      end

      # Count (always 1 for upscaling)

      def count
        success? ? 1 : 0
      end

      # Size helpers

      def size
        output_size
      end

      def output_width
        return nil unless output_size
        output_size.split("x").first.to_i
      end

      def output_height
        return nil unless output_size
        output_size.split("x").last.to_i
      end

      # Timing

      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation

      def total_cost
        return 0 if error?

        # Upscaling typically has fixed per-image cost
        ImageGenerator::Pricing.calculate_cost(
          model_id: model_id,
          count: 1
        )
      end

      # File operations

      def save(path)
        raise "No image to save" unless image
        image.save(path)
      end

      def to_blob
        image&.to_blob
      end

      def blobs
        success? ? [to_blob].compact : []
      end

      # Serialization

      def to_h
        {
          success: success?,
          url: url,
          base64: base64?,
          mime_type: mime_type,
          source_image: source_image,
          model_id: model_id,
          scale: scale,
          output_size: output_size,
          face_enhance: face_enhance,
          total_cost: total_cost,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          upscaler_class: upscaler_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      def to_cache
        {
          url: url,
          data: data,
          mime_type: mime_type,
          model_id: model_id,
          scale: scale,
          output_size: output_size,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      def self.from_cache(data)
        CachedImageUpscaleResult.new(data)
      end
    end

    # Lightweight result for cached upscales
    class CachedImageUpscaleResult
      attr_reader :url, :data, :mime_type, :model_id, :scale, :output_size,
                  :total_cost, :cached_at

      def initialize(data)
        @url = data[:url]
        @data = data[:data]
        @mime_type = data[:mime_type]
        @model_id = data[:model_id]
        @scale = data[:scale]
        @output_size = data[:output_size]
        @total_cost = data[:total_cost]
        @cached_at = data[:cached_at]
      end

      def success?
        !url.nil? || !data.nil?
      end

      def error?
        !success?
      end

      def cached?
        true
      end

      def urls
        success? ? [url].compact : []
      end

      def datas
        success? ? [data].compact : []
      end

      def base64?
        !data.nil?
      end

      def count
        success? ? 1 : 0
      end

      def single?
        true
      end

      def batch?
        false
      end

      def size
        output_size
      end
    end
  end
end
