# frozen_string_literal: true

module RubyLLM
  module Agents
    # Wrapper for moderation results with threshold and category filtering
    #
    # Provides a filtered view of moderation results based on configured
    # thresholds and category filters. The raw result is still accessible
    # for full details.
    #
    # @example Basic usage
    #   result = ModerationResult.new(
    #     result: raw_moderation,
    #     threshold: 0.8,
    #     categories: [:hate, :violence]
    #   )
    #
    #   result.flagged?  # Only true if score >= 0.8 AND category is hate or violence
    #   result.passed?   # Opposite of flagged?
    #
    # @api public
    class ModerationResult
      # @return [Object] The raw moderation result from RubyLLM
      attr_reader :raw_result

      # @return [Float, nil] Configured threshold for flagging
      attr_reader :threshold

      # @return [Array<Symbol>, nil] Categories to filter on
      attr_reader :filter_categories

      # Creates a new ModerationResult
      #
      # @param result [Object] Raw moderation result from RubyLLM
      # @param threshold [Float, nil] Score threshold (0.0-1.0)
      # @param categories [Array<Symbol>, nil] Categories to check
      def initialize(result:, threshold: nil, categories: nil)
        @raw_result = result
        @threshold = threshold
        @filter_categories = categories&.map(&:to_sym)
      end

      # Returns whether the content should be flagged
      #
      # Considers both threshold and category filters if configured.
      # Content is flagged only if:
      # - Raw result is flagged AND
      # - Score meets threshold (if configured) AND
      # - Category matches filter (if configured)
      #
      # @return [Boolean] true if content should be flagged
      def flagged?
        return false unless raw_result.flagged?

        passes_threshold? && passes_category_filter?
      end

      # Returns whether the content passed moderation
      #
      # @return [Boolean] true if content is not flagged
      def passed?
        !flagged?
      end

      # Returns the flagged categories, filtered by configuration
      #
      # @return [Array<String, Symbol>] Categories that triggered flagging
      def flagged_categories
        cats = raw_result.flagged_categories || []
        return cats unless filter_categories&.any?

        cats.select { |c| filter_categories.include?(normalize_category(c)) }
      end

      # Returns all category scores from the raw result
      #
      # @return [Hash{String, Symbol => Float}] Category to score mapping
      def category_scores
        raw_result.category_scores || {}
      end

      # Returns the moderation result ID
      #
      # @return [String, nil] Result identifier
      def id
        raw_result.id
      end

      # Returns the model used for moderation
      #
      # @return [String, nil] Model identifier
      def model
        raw_result.model
      end

      # Returns the maximum score across all categories
      #
      # @return [Float] Highest category score
      def max_score
        scores = category_scores.values
        scores.any? ? scores.max : 0.0
      end

      # Returns whether the raw result was flagged (ignoring filters)
      #
      # @return [Boolean] true if raw result was flagged
      def raw_flagged?
        raw_result.flagged?
      end

      # Converts the result to a hash
      #
      # @return [Hash] Result data as a hash
      def to_h
        {
          flagged: flagged?,
          raw_flagged: raw_flagged?,
          flagged_categories: flagged_categories,
          category_scores: category_scores,
          max_score: max_score,
          threshold: threshold,
          filter_categories: filter_categories,
          model: model,
          id: id
        }
      end

      private

      # Checks if the max score meets the threshold
      #
      # @return [Boolean] true if threshold is met or not configured
      def passes_threshold?
        return true unless threshold

        max_score >= threshold
      end

      # Checks if any flagged categories match the filter
      #
      # @return [Boolean] true if categories match or no filter configured
      def passes_category_filter?
        return true unless filter_categories&.any?

        normalized_flagged = (raw_result.flagged_categories || []).map { |c| normalize_category(c) }
        (normalized_flagged & filter_categories).any?
      end

      # Normalizes category names for comparison
      #
      # @param category [String, Symbol] Category name
      # @return [Symbol] Normalized category symbol
      def normalize_category(category)
        category.to_s.tr("/", "_").tr("-", "_").downcase.to_sym
      end
    end
  end
end
