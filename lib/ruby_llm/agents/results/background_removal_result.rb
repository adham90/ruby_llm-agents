# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for background removal operations
    #
    # Provides a consistent interface for accessing the extracted foreground,
    # segmentation mask, and metadata.
    #
    # @example Accessing removal result
    #   result = BackgroundRemover.call(image: "photo.jpg")
    #   result.url        # => "https://..." (transparent PNG)
    #   result.has_alpha? # => true
    #   result.mask       # => Segmentation mask (if requested)
    #   result.success?   # => true
    #
    class BackgroundRemovalResult
      attr_reader :foreground, :mask, :source_image, :model_id, :output_format,
                  :alpha_matting, :refine_edges,
                  :started_at, :completed_at, :tenant_id, :remover_class,
                  :error_class, :error_message

      # Initialize a new result
      #
      # @param foreground [Object] The extracted foreground image
      # @param mask [Object, nil] The segmentation mask (if requested)
      # @param source_image [String] The original source image
      # @param model_id [String] Model used for removal
      # @param output_format [Symbol] Output format used
      # @param alpha_matting [Boolean] Whether alpha matting was used
      # @param refine_edges [Boolean] Whether edge refinement was used
      # @param started_at [Time] When removal started
      # @param completed_at [Time] When removal completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param remover_class [String] Name of the remover class
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(foreground:, mask:, source_image:, model_id:, output_format:,
                     alpha_matting:, refine_edges:, started_at:, completed_at:,
                     tenant_id:, remover_class:, error_class: nil, error_message: nil)
        @foreground = foreground
        @mask = mask
        @source_image = source_image
        @model_id = model_id
        @output_format = output_format
        @alpha_matting = alpha_matting
        @refine_edges = refine_edges
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @remover_class = remover_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      def success?
        error_class.nil? && !foreground.nil?
      end

      def error?
        !success?
      end

      # Always single for background removal
      def single?
        true
      end

      def batch?
        false
      end

      # Image access (foreground)

      def image
        foreground
      end

      def url
        foreground&.url
      end

      def urls
        success? ? [url].compact : []
      end

      def data
        foreground&.data
      end

      def datas
        success? ? [data].compact : []
      end

      def base64?
        foreground&.base64? || false
      end

      def mime_type
        foreground&.mime_type || "image/#{output_format}"
      end

      # Mask access

      def mask?
        !mask.nil?
      end

      def mask_url
        mask&.url
      end

      def mask_data
        mask&.data
      end

      # Check if result has alpha channel (transparency)
      def has_alpha?
        return false if error?

        # PNG and WebP support alpha
        %i[png webp].include?(output_format)
      end

      # Count (always 1 for removal)

      def count
        success? ? 1 : 0
      end

      # Timing

      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation

      def total_cost
        return 0 if error?

        # Background removal typically has fixed per-image cost
        ImageGenerator::Pricing.calculate_cost(
          model_id: model_id,
          count: 1
        )
      end

      # File operations

      def save(path)
        raise "No foreground image to save" unless foreground
        foreground.save(path)
      end

      def save_mask(path)
        raise "No mask to save" unless mask
        mask.save(path)
      end

      def to_blob
        foreground&.to_blob
      end

      def mask_blob
        mask&.to_blob
      end

      def blobs
        success? ? [to_blob].compact : []
      end

      # Serialization

      def to_h
        {
          success: success?,
          url: url,
          mask_url: mask_url,
          base64: base64?,
          mime_type: mime_type,
          has_alpha: has_alpha?,
          has_mask: mask?,
          source_image: source_image,
          model_id: model_id,
          output_format: output_format,
          alpha_matting: alpha_matting,
          refine_edges: refine_edges,
          total_cost: total_cost,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          remover_class: remover_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      def to_cache
        {
          url: url,
          data: data,
          mask_url: mask_url,
          mask_data: mask_data,
          mime_type: mime_type,
          model_id: model_id,
          output_format: output_format,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      def self.from_cache(data)
        CachedBackgroundRemovalResult.new(data)
      end
    end

    # Lightweight result for cached removals
    class CachedBackgroundRemovalResult
      attr_reader :url, :data, :mask_url, :mask_data, :mime_type, :model_id,
                  :output_format, :total_cost, :cached_at

      def initialize(data)
        @url = data[:url]
        @data = data[:data]
        @mask_url = data[:mask_url]
        @mask_data = data[:mask_data]
        @mime_type = data[:mime_type]
        @model_id = data[:model_id]
        @output_format = data[:output_format]
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

      def mask?
        !mask_url.nil? || !mask_data.nil?
      end

      def has_alpha?
        %i[png webp].include?(output_format&.to_sym)
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
    end
  end
end
