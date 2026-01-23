# frozen_string_literal: true

# IllustrationGenerator - Blog and article illustrations
#
# Generates artistic illustrations for blog posts, articles, and
# editorial content. Uses portrait format for tall hero images
# and HD quality for detailed artwork.
#
# Use cases:
# - Blog post illustrations
# - Editorial artwork
# - Book chapter headers
# - Newsletter graphics
#
# @example Basic usage
#   result = Llm::Image::IllustrationGenerator.call(prompt: "Developer working on laptop, coffee shop setting")
#   result.url            # => "https://..."
#   result.save_to("dev_life_illustration.png")
#
# @example Abstract concept
#   result = Llm::Image::IllustrationGenerator.call(
#     prompt: "Abstract representation of artificial intelligence and human creativity"
#   )
#
# @example Story illustration
#   result = Llm::Image::IllustrationGenerator.call(
#     prompt: "Whimsical forest scene with a tiny house among giant mushrooms"
#   )
#
module Llm
  module Images
    class IllustrationGenerator < ApplicationImageGenerator
      description "Generates artistic illustrations for blog posts and articles"
      version "1.0"

      # DALL-E 3 for highest quality
      model "gpt-image-1"

      # Portrait format for hero images
      size "1024x1792"

      # HD quality for detailed illustrations
      quality "hd"

      # Vivid for artistic illustrations
      style "vivid"

      # Standard content policy
      content_policy :standard

      # Prompt template for illustration style
      template "Artistic editorial illustration: {prompt}. Rich colors, " \
               "thoughtful composition, editorial quality, suitable for " \
               "blog or article header, visually engaging storytelling."

      # Cache illustrations for 1 hour
      cache_for 1.hour
    end
  end
end
