# frozen_string_literal: true

module RubyLLM
  module Agents
    # Result wrapper for image analysis operations
    #
    # Provides a consistent interface for accessing analysis data
    # including captions, tags, objects, colors, and extracted text.
    #
    # @example Accessing analysis data
    #   result = ImageAnalyzer.call(image: "photo.jpg")
    #   result.caption      # => "A sunset over mountains"
    #   result.tags         # => ["sunset", "mountains", "nature"]
    #   result.objects      # => [{name: "mountain", location: "center", confidence: "high"}]
    #   result.colors       # => [{hex: "#FF6B35", name: "orange", percentage: 30}]
    #   result.description  # => "A detailed description..."
    #   result.success?     # => true
    #
    class ImageAnalysisResult
      attr_reader :image, :model_id, :analysis_type,
                  :caption, :description, :tags, :objects, :colors, :text,
                  :raw_response, :started_at, :completed_at, :tenant_id, :analyzer_class,
                  :error_class, :error_message

      # Initialize a new result
      #
      # @param image [String] The analyzed image path or URL
      # @param model_id [String] Model used for analysis
      # @param analysis_type [Symbol] Type of analysis performed
      # @param caption [String, nil] Brief caption of the image
      # @param description [String, nil] Detailed description
      # @param tags [Array<String>] Tags/keywords for the image
      # @param objects [Array<Hash>] Detected objects with metadata
      # @param colors [Array<Hash>] Dominant colors with hex, name, percentage
      # @param text [String, nil] Extracted text (OCR)
      # @param raw_response [Hash, String, nil] Raw response from the model
      # @param started_at [Time] When analysis started
      # @param completed_at [Time] When analysis completed
      # @param tenant_id [String, nil] Tenant identifier
      # @param analyzer_class [String] Name of the analyzer class
      # @param error_class [String, nil] Error class name if failed
      # @param error_message [String, nil] Error message if failed
      def initialize(image:, model_id:, analysis_type:, caption:, description:, tags:,
                     objects:, colors:, text:, raw_response:, started_at:, completed_at:,
                     tenant_id:, analyzer_class:, error_class: nil, error_message: nil)
        @image = image
        @model_id = model_id
        @analysis_type = analysis_type
        @caption = caption
        @description = description
        @tags = tags || []
        @objects = objects || []
        @colors = colors || []
        @text = text
        @raw_response = raw_response
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @analyzer_class = analyzer_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers

      def success?
        error_class.nil? && (caption.present? || description.present? || tags.any?)
      end

      def error?
        !success?
      end

      # Analysis is always single
      def single?
        true
      end

      def batch?
        false
      end

      # Count (always 1 for analysis)
      def count
        success? ? 1 : 0
      end

      # Data access helpers

      # Check if the result has a caption
      def caption?
        caption.present?
      end

      # Check if the result has a description
      def description?
        description.present?
      end

      # Check if the result has tags
      def tags?
        tags.any?
      end

      # Check if the result has detected objects
      def objects?
        objects.any?
      end

      # Check if the result has color information
      def colors?
        colors.any?
      end

      # Check if text was extracted
      def text?
        text.present?
      end

      # Get tags as symbols
      #
      # @return [Array<Symbol>] Tags as symbols
      def tag_symbols
        tags.map { |t| t.to_s.downcase.gsub(/\s+/, "_").to_sym }
      end

      # Get the dominant color (highest percentage)
      #
      # @return [Hash, nil] The dominant color or nil
      def dominant_color
        return nil unless colors?

        colors.max_by { |c| c[:percentage] || 0 }
      end

      # Get objects by confidence level
      #
      # @param confidence [String] Confidence level ("high", "medium", "low")
      # @return [Array<Hash>] Objects with matching confidence
      def objects_with_confidence(confidence)
        objects.select { |obj| obj[:confidence]&.downcase == confidence.to_s.downcase }
      end

      # Get high-confidence objects
      #
      # @return [Array<Hash>] High-confidence objects
      def high_confidence_objects
        objects_with_confidence("high")
      end

      # Check if a specific object was detected
      #
      # @param name [String] Object name to search for
      # @return [Boolean] Whether the object was detected
      def has_object?(name)
        objects.any? { |obj| obj[:name]&.downcase&.include?(name.to_s.downcase) }
      end

      # Check if a specific tag is present
      #
      # @param tag [String] Tag to search for
      # @return [Boolean] Whether the tag is present
      def has_tag?(tag)
        tags.any? { |t| t.downcase == tag.to_s.downcase }
      end

      # Timing

      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation

      def total_cost
        return 0 if error?

        # Analysis typically uses vision model pricing
        # Estimate based on model and image size
        ImageGenerator::Pricing.calculate_cost(
          model_id: model_id,
          count: 1
        )
      end

      # Serialization

      def to_h
        {
          success: success?,
          image: image,
          model_id: model_id,
          analysis_type: analysis_type,
          caption: caption,
          description: description,
          tags: tags,
          objects: objects,
          colors: colors,
          text: text,
          total_cost: total_cost,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          analyzer_class: analyzer_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching

      def to_cache
        {
          image: image,
          model_id: model_id,
          analysis_type: analysis_type,
          caption: caption,
          description: description,
          tags: tags,
          objects: objects,
          colors: colors,
          text: text,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      def self.from_cache(data)
        CachedImageAnalysisResult.new(data)
      end
    end

    # Lightweight result for cached analyses
    class CachedImageAnalysisResult
      attr_reader :image, :model_id, :analysis_type,
                  :caption, :description, :tags, :objects, :colors, :text,
                  :total_cost, :cached_at

      def initialize(data)
        @image = data[:image]
        @model_id = data[:model_id]
        @analysis_type = data[:analysis_type]
        @caption = data[:caption]
        @description = data[:description]
        @tags = data[:tags] || []
        @objects = data[:objects] || []
        @colors = data[:colors] || []
        @text = data[:text]
        @total_cost = data[:total_cost]
        @cached_at = data[:cached_at]
      end

      def success?
        caption.present? || description.present? || tags.any?
      end

      def error?
        !success?
      end

      def cached?
        true
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

      def caption?
        caption.present?
      end

      def description?
        description.present?
      end

      def tags?
        tags.any?
      end

      def objects?
        objects.any?
      end

      def colors?
        colors.any?
      end

      def text?
        text.present?
      end

      def tag_symbols
        tags.map { |t| t.to_s.downcase.gsub(/\s+/, "_").to_sym }
      end

      def dominant_color
        return nil unless colors?

        colors.max_by { |c| c[:percentage] || 0 }
      end
    end
  end
end
