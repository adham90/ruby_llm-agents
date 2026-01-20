# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for image variation operations
    #
    # Provides a consistent interface for accessing variation images,
    # metadata, timing, and cost information.
    #
    # @example Accessing variations
    #   result = ImageVariator.call(image: "logo.png", count: 4)
    #   result.urls      # => ["https://...", ...]
    #   result.count     # => 4
    #   result.success?  # => true
    #
    class ImageVariationResult
      attr_reader :images, :source_image, :model_id, :size, :variation_strength,
                  :started_at, :completed_at, :tenant_id, :variator_class,
                  :error_class, :error_message

      # Initialize a new result
      #
      # @param images [Array<Object>] Array of variation image objects
      # @param source_image [String] The original source image
      # @param model_id [String] Model used for variation
      # @param size [String] Image size
      # @param variation_strength [Float] Variation strength used
      # @param started_at [Time] When variation started
      # @param completed_at [Time] When variation completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param variator_class [String] Name of the variator class
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(images:, source_image:, model_id:, size:, variation_strength:,
                     started_at:, completed_at:, tenant_id:, variator_class:,
                     error_class: nil, error_message: nil)
        @images = images
        @source_image = source_image
        @model_id = model_id
        @size = size
        @variation_strength = variation_strength
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @variator_class = variator_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      def success?
        error_class.nil? && images.any?
      end

      def error?
        !success?
      end

      def single?
        count == 1
      end

      def batch?
        count > 1
      end

      # Image access

      def image
        images.first
      end

      def url
        image&.url
      end

      def urls
        images.map(&:url).compact
      end

      def data
        image&.data
      end

      def datas
        images.map(&:data).compact
      end

      def base64?
        image&.base64? || false
      end

      def mime_type
        image&.mime_type
      end

      # Count

      def count
        images.size
      end

      # Timing

      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation

      def total_cost
        return 0 if error?

        ImageGenerator::Pricing.calculate_cost(
          model_id: model_id,
          size: size,
          count: count
        )
      end

      # File operations

      def save(path)
        raise "No image to save" unless image
        image.save(path)
      end

      def save_all(directory, prefix: "variation")
        images.each_with_index do |img, idx|
          filename = "#{prefix}_#{idx + 1}.png"
          img.save(File.join(directory, filename))
        end
      end

      def to_blob
        image&.to_blob
      end

      def blobs
        images.map(&:to_blob)
      end

      # Serialization

      def to_h
        {
          success: success?,
          count: count,
          urls: urls,
          base64: base64?,
          mime_type: mime_type,
          source_image: source_image,
          model_id: model_id,
          size: size,
          variation_strength: variation_strength,
          total_cost: total_cost,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          variator_class: variator_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      def to_cache
        {
          urls: urls,
          datas: datas,
          mime_type: mime_type,
          model_id: model_id,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      def self.from_cache(data)
        CachedImageVariationResult.new(data)
      end
    end

    # Lightweight result for cached variations
    class CachedImageVariationResult
      attr_reader :urls, :datas, :mime_type, :model_id, :total_cost, :cached_at

      def initialize(data)
        @urls = data[:urls] || []
        @datas = data[:datas] || []
        @mime_type = data[:mime_type]
        @model_id = data[:model_id]
        @total_cost = data[:total_cost]
        @cached_at = data[:cached_at]
      end

      def success?
        urls.any? || datas.any?
      end

      def error?
        !success?
      end

      def cached?
        true
      end

      def url
        urls.first
      end

      def data
        datas.first
      end

      def base64?
        datas.any?
      end

      def count
        [urls.size, datas.size].max
      end

      def single?
        count == 1
      end

      def batch?
        count > 1
      end
    end
  end
end
