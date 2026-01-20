# frozen_string_literal: true

# CleanTextEmbedder - Embedder with text preprocessing
#
# Demonstrates the preprocess(text) method for cleaning and normalizing
# text before embedding. Useful for handling user-generated content,
# scraped web content, or any text that needs cleaning.
#
# Preprocessing benefits:
# - Consistent embeddings for semantically identical text
# - Better cache hit rates (normalized text matches more often)
# - Improved embedding quality by removing noise
#
# @example With HTML content
#   html = "<p>Hello <strong>World</strong>!</p>"
#   result = Llm::Text::CleanTextEmbedder.call(text: html)
#   # Text is cleaned to "hello world!" before embedding
#
# @example With messy whitespace
#   text = "  Multiple   spaces   and\n\nnewlines  "
#   result = Llm::Text::CleanTextEmbedder.call(text: text)
#   # Text is cleaned to "multiple spaces and newlines" before embedding
#
# @example User-generated content
#   comment = user_params[:comment]  # May contain HTML, extra spaces, etc.
#   result = Llm::Text::CleanTextEmbedder.call(text: comment)
#   # Safe to embed after preprocessing
#
# @example Custom preprocessing subclass
#   class MarkdownEmbedder < Llm::Text::CleanTextEmbedder
#     def preprocess(text)
#       # First apply parent preprocessing
#       cleaned = super(text)
#       # Then remove markdown formatting
#       cleaned.gsub(/[*_~`#]/, '')
#     end
#   end
#
module Llm
  module Text
    class CleanTextEmbedder < ApplicationEmbedder
      description "Embedder with text preprocessing"
      version "1.0"

      model "text-embedding-3-small"
      dimensions 512

      # Enable caching - preprocessing makes cache hits more likely
      cache_for 1.week

      # Preprocess text before embedding
      #
      # This method is called automatically for each text before
      # it is sent to the embedding API.
      #
      # @param text [String] Raw input text
      # @return [String] Cleaned text ready for embedding
      def preprocess(text)
        return "" if text.nil?

        text.to_s
            .then { |t| strip_html(t) }           # Remove HTML tags
            .then { |t| normalize_whitespace(t) } # Collapse whitespace
            .then { |t| normalize_unicode(t) }    # Normalize unicode
            .downcase                             # Lowercase for consistency
            .strip                                # Trim leading/trailing whitespace
      end

      private

      # Remove HTML tags from text
      # @param text [String]
      # @return [String]
      def strip_html(text)
        # Simple HTML stripping - use Nokogiri for complex HTML
        text.gsub(/<[^>]*>/, " ")
      end

      # Collapse multiple whitespace characters to single space
      # @param text [String]
      # @return [String]
      def normalize_whitespace(text)
        text.gsub(/\s+/, " ")
      end

      # Normalize unicode characters
      # @param text [String]
      # @return [String]
      def normalize_unicode(text)
        # Convert smart quotes, dashes, etc. to ASCII equivalents
        text.gsub(/[\u2018\u2019]/, "'")     # Smart single quotes
            .gsub(/[\u201C\u201D]/, '"')     # Smart double quotes
            .gsub(/[\u2013\u2014]/, "-")     # En/em dashes
            .gsub(/\u2026/, "...")           # Ellipsis
      end
    end
  end
end
