# frozen_string_literal: true

# CodeEmbedder - Domain-specific embedder for source code
#
# Optimized for embedding source code with preprocessing that
# preserves code semantics while normalizing formatting differences.
# Useful for code search, duplicate detection, and similarity matching.
#
# Use cases:
# - Code search engines
# - Duplicate code detection
# - Similar code recommendations
# - Code plagiarism detection
#
# @example Basic code embedding
#   code = <<~RUBY
#     def hello(name)
#       puts "Hello, #{name}!"
#     end
#   RUBY
#   result = CodeEmbedder.call(text: code)
#
# @example Code similarity search
#   query_code = "def factorial(n)\n  n <= 1 ? 1 : n * factorial(n-1)\nend"
#   query = CodeEmbedder.call(text: query_code)
#
#   repo_code = CodeSnippet.all.pluck(:content)
#   indexed = CodeEmbedder.call(texts: repo_code)
#
#   similar = query.most_similar(indexed.vectors, limit: 5)
#   # Find similar implementations across the codebase
#
# @example Cross-language similarity
#   # Embeddings can capture semantic similarity across languages
#   ruby_code = "array.map { |x| x * 2 }"
#   js_code = "array.map(x => x * 2)"
#
#   ruby_result = CodeEmbedder.call(text: ruby_code)
#   js_result = CodeEmbedder.call(text: js_code)
#
#   ruby_result.similarity(js_result)  # => ~0.85 (semantically similar)
#
class CodeEmbedder < ApplicationEmbedder
  description "Domain-specific embedder for source code"
  version "1.0"

  # Use larger model for better code understanding
  model "text-embedding-3-large"

  # Higher dimensions for capturing code nuances
  dimensions 1536

  # Cache code embeddings
  cache_for 2.weeks

  # Preprocess code before embedding
  #
  # Normalizes code formatting while preserving semantics:
  # - Normalizes indentation
  # - Removes excessive blank lines
  # - Preserves code structure
  #
  # @param text [String] Source code
  # @return [String] Normalized code
  def preprocess(text)
    return "" if text.nil?

    text.to_s
        .then { |t| normalize_indentation(t) }
        .then { |t| collapse_blank_lines(t) }
        .then { |t| remove_trailing_whitespace(t) }
        .strip
  end

  private

  # Normalize indentation to 2 spaces
  # @param code [String]
  # @return [String]
  def normalize_indentation(code)
    lines = code.lines

    # Find minimum indentation (excluding blank lines)
    min_indent = lines
                 .reject { |l| l.strip.empty? }
                 .map { |l| l[/^\s*/].length }
                 .min || 0

    # Remove common indentation and normalize tabs to spaces
    lines.map do |line|
      # Convert tabs to 2 spaces
      normalized = line.gsub("\t", "  ")

      # Remove common leading indentation
      if normalized.strip.empty?
        ""
      else
        normalized[min_indent..] || ""
      end
    end.join
  end

  # Collapse multiple blank lines to single blank line
  # @param code [String]
  # @return [String]
  def collapse_blank_lines(code)
    code.gsub(/\n{3,}/, "\n\n")
  end

  # Remove trailing whitespace from each line
  # @param code [String]
  # @return [String]
  def remove_trailing_whitespace(code)
    code.lines.map(&:rstrip).join("\n")
  end
end
