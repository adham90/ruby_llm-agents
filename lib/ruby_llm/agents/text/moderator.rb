# frozen_string_literal: true

require_relative "../results/moderation_result"

module RubyLLM
  module Agents
    # Standalone moderator for content moderation without an agent
    #
    # Provides a class-based interface for moderating content independently
    # from the agent execution flow. Useful for background jobs, API endpoints,
    # or any scenario where you need to moderate content separately.
    #
    # @example Basic usage
    #   class ContentModerator < RubyLLM::Agents::Moderator
    #     model 'omni-moderation-latest'
    #   end
    #
    #   result = ContentModerator.call(text: "content to check")
    #   result.flagged?  # => true/false
    #
    # @example With configuration
    #   class StrictModerator < RubyLLM::Agents::Moderator
    #     model 'omni-moderation-latest'
    #     threshold 0.7
    #     categories :hate, :violence, :harassment
    #   end
    #
    # @example Runtime override
    #   result = ContentModerator.call(
    #     text: "content",
    #     threshold: 0.9,
    #     categories: [:hate]
    #   )
    #
    # @api public
    class Moderator
      class << self
        # Sets or returns the moderation model
        #
        # @param value [String, nil] Model identifier to set
        # @return [String] Current model setting
        def model(value = nil)
          @model = value if value
          @model || RubyLLM::Agents.configuration.default_moderation_model || "omni-moderation-latest"
        end

        # Sets or returns the score threshold
        #
        # @param value [Float, nil] Threshold value (0.0-1.0)
        # @return [Float, nil] Current threshold
        def threshold(value = nil)
          @threshold = value if value
          @threshold
        end

        # Sets or returns the categories to check
        #
        # @param cats [Array<Symbol>] Category symbols
        # @return [Array<Symbol>, nil] Current categories
        def categories(*cats)
          @categories = cats.flatten.map(&:to_sym) if cats.any?
          @categories
        end

        # Sets or returns the version for cache invalidation
        #
        # @param value [String, nil] Version string
        # @return [String, nil] Current version
        def version(value = nil)
          @version = value if value
          @version
        end

        # Sets or returns the description
        #
        # @param value [String, nil] Description text
        # @return [String, nil] Current description
        def description(value = nil)
          @description = value if value
          @description
        end

        # Factory method to instantiate and execute moderation
        #
        # @param text [String] Text to moderate
        # @param options [Hash] Runtime options
        # @option options [String] :model Override moderation model
        # @option options [Float] :threshold Override threshold
        # @option options [Array<Symbol>] :categories Override categories
        # @return [ModerationResult] The moderation result
        def call(text:, **options)
          new.call(text: text, **options)
        end
      end

      # Executes moderation on the given text
      #
      # @param text [String] Text to moderate
      # @param options [Hash] Runtime options
      # @return [ModerationResult] The moderation result
      def call(text:, **options)
        model_id = options[:model] || self.class.model

        moderation_opts = {}
        moderation_opts[:model] = model_id if model_id

        raw_result = RubyLLM.moderate(text, **moderation_opts)

        ModerationResult.new(
          result: raw_result,
          threshold: options[:threshold] || self.class.threshold,
          categories: options[:categories] || self.class.categories
        )
      end
    end
  end
end
