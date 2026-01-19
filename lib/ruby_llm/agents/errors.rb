# frozen_string_literal: true

module RubyLLM
  module Agents
    # Base error class for RubyLLM::Agents
    class Error < StandardError; end

    # Raised when content is flagged during moderation
    #
    # Contains the full moderation result and the phase where
    # the content was flagged.
    #
    # @example Handling moderation errors
    #   begin
    #     result = MyAgent.call(message: user_input)
    #   rescue RubyLLM::Agents::ModerationError => e
    #     puts "Content blocked: #{e.flagged_categories.join(', ')}"
    #     puts "Phase: #{e.phase}"
    #     puts "Scores: #{e.category_scores}"
    #   end
    #
    # @api public
    class ModerationError < Error
      # @return [Object] The raw moderation result from RubyLLM
      attr_reader :moderation_result

      # @return [Symbol] The phase where content was flagged (:input or :output)
      attr_reader :phase

      # Creates a new ModerationError
      #
      # @param moderation_result [Object] The moderation result from RubyLLM
      # @param phase [Symbol] The phase where content was flagged
      def initialize(moderation_result, phase)
        @moderation_result = moderation_result
        @phase = phase

        categories = moderation_result.flagged_categories
        category_list = categories.respond_to?(:join) ? categories.join(", ") : categories.to_s

        super("Content flagged during #{phase} moderation: #{category_list}")
      end

      # Returns the flagged categories from the moderation result
      #
      # @return [Array<String, Symbol>] List of flagged categories
      def flagged_categories
        moderation_result.flagged_categories
      end

      # Returns the category scores from the moderation result
      #
      # @return [Hash{String, Symbol => Float}] Category to score mapping
      def category_scores
        moderation_result.category_scores
      end

      # Returns whether the moderation result was flagged
      #
      # @return [Boolean] Always true for ModerationError
      def flagged?
        true
      end
    end
  end
end
