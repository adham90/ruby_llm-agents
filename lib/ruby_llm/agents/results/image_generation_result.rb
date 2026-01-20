# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for image generation operations
    #
    # Provides a consistent interface for accessing generated images,
    # metadata, timing, and cost information.
    #
    # @example Accessing a single image
    #   result = ImageGenerator.call(prompt: "A sunset")
    #   result.url       # => "https://..."
    #   result.success?  # => true
    #   result.save("sunset.png")
    #
    # @example Accessing multiple images
    #   result = ImageGenerator.call(prompt: "Logos", count: 4)
    #   result.urls      # => ["https://...", ...]
    #   result.count     # => 4
    #   result.save_all("./logos")
    #
    class ImageGenerationResult
      attr_reader :images, :prompt, :model_id, :size, :quality, :style,
                  :started_at, :completed_at, :tenant_id, :generator_class,
                  :error_class, :error_message

      # Initialize a new result
      #
      # @param images [Array<Object>] Array of image objects from RubyLLM
      # @param prompt [String] The original prompt
      # @param model_id [String] Model used for generation
      # @param size [String] Image size
      # @param quality [String] Quality setting
      # @param style [String] Style setting
      # @param started_at [Time] When generation started
      # @param completed_at [Time] When generation completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param generator_class [String] Name of the generator class
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(images:, prompt:, model_id:, size:, quality:, style:,
                     started_at:, completed_at:, tenant_id:, generator_class:,
                     error_class: nil, error_message: nil)
        @images = images
        @prompt = prompt
        @model_id = model_id
        @size = size
        @quality = quality
        @style = style
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @generator_class = generator_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      # Check if generation was successful
      #
      # @return [Boolean] true if successful
      def success?
        error_class.nil? && images.any?
      end

      # Check if generation failed
      #
      # @return [Boolean] true if failed
      def error?
        !success?
      end

      # Check if this was a single image request
      #
      # @return [Boolean] true if single image
      def single?
        count == 1
      end

      # Check if this was a batch request
      #
      # @return [Boolean] true if multiple images
      def batch?
        count > 1
      end

      # Image access

      # Get the first/only image
      #
      # @return [Object, nil] The first image object
      def image
        images.first
      end

      # Get the URL of the first image
      #
      # @return [String, nil] The image URL
      def url
        image&.url
      end

      # Get all image URLs
      #
      # @return [Array<String>] Array of URLs
      def urls
        images.map(&:url).compact
      end

      # Get the base64 data of the first image
      #
      # @return [String, nil] Base64 encoded image data
      def data
        image&.data
      end

      # Get all base64 data
      #
      # @return [Array<String>] Array of base64 data
      def datas
        images.map(&:data).compact
      end

      # Check if the image is base64 encoded
      #
      # @return [Boolean] true if base64
      def base64?
        image&.base64? || false
      end

      # Get the MIME type
      #
      # @return [String, nil] MIME type
      def mime_type
        image&.mime_type
      end

      # Get the revised prompt (if model modified it)
      #
      # @return [String, nil] The revised prompt
      def revised_prompt
        image&.revised_prompt
      end

      # Get all revised prompts
      #
      # @return [Array<String>] Array of revised prompts
      def revised_prompts
        images.map(&:revised_prompt).compact
      end

      # Count

      # Get the number of generated images
      #
      # @return [Integer] Image count
      def count
        images.size
      end

      # Timing

      # Get the generation duration in milliseconds
      #
      # @return [Integer] Duration in ms
      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation

      # Get the total cost for this generation
      #
      # Uses dynamic pricing from the Pricing module
      #
      # @return [Float] Total cost in USD
      def total_cost
        return 0 if error?

        ImageGenerator::Pricing.calculate_cost(
          model_id: model_id,
          size: size,
          quality: quality,
          count: count
        )
      end

      # Estimate input tokens from prompt
      #
      # @return [Integer] Approximate token count
      def input_tokens
        # Approximate token count for prompt
        (prompt.length / 4.0).ceil
      end

      # File operations

      # Save the first image to a file
      #
      # @param path [String] File path to save to
      # @raise [RuntimeError] If no image to save
      def save(path)
        raise "No image to save" unless image
        image.save(path)
      end

      # Save all images to a directory
      #
      # @param directory [String] Directory path
      # @param prefix [String] Filename prefix
      def save_all(directory, prefix: "image")
        images.each_with_index do |img, idx|
          filename = "#{prefix}_#{idx + 1}.png"
          img.save(File.join(directory, filename))
        end
      end

      # Get the first image as binary data
      #
      # @return [String, nil] Binary image data
      def to_blob
        image&.to_blob
      end

      # Get all images as binary data
      #
      # @return [Array<String>] Array of binary data
      def blobs
        images.map(&:to_blob)
      end

      # Serialization

      # Convert to hash
      #
      # @return [Hash] Hash representation
      def to_h
        {
          success: success?,
          count: count,
          urls: urls,
          base64: base64?,
          mime_type: mime_type,
          prompt: prompt,
          revised_prompts: revised_prompts,
          model_id: model_id,
          size: size,
          quality: quality,
          style: style,
          total_cost: total_cost,
          input_tokens: input_tokens,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          generator_class: generator_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      # Convert to cacheable format
      #
      # @return [Hash] Cache-friendly hash
      def to_cache
        {
          urls: urls,
          datas: datas,
          mime_type: mime_type,
          revised_prompts: revised_prompts,
          model_id: model_id,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      # Create a result from cached data
      #
      # @param data [Hash] Cached data
      # @return [CachedImageGenerationResult] The cached result
      def self.from_cache(data)
        CachedImageGenerationResult.new(data)
      end
    end

    # Lightweight result for cached images
    #
    # Provides a subset of ImageGenerationResult functionality
    # for results loaded from cache.
    #
    class CachedImageGenerationResult
      attr_reader :urls, :datas, :mime_type, :revised_prompts, :model_id,
                  :total_cost, :cached_at

      def initialize(data)
        @urls = data[:urls] || []
        @datas = data[:datas] || []
        @mime_type = data[:mime_type]
        @revised_prompts = data[:revised_prompts] || []
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
