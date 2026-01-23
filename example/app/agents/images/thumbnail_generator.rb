# frozen_string_literal: true

# ThumbnailGenerator - Video and article thumbnails
#
# Generates eye-catching thumbnails for videos, articles, and
# social media posts. Uses landscape format optimized for
# video platforms and content previews.
#
# Use cases:
# - YouTube thumbnails
# - Blog post headers
# - Social media preview images
# - Podcast cover art
#
# @example Basic usage
#   result = Llm::Image::ThumbnailGenerator.call(prompt: "Exciting tech review thumbnail for new iPhone")
#   result.url            # => "https://..."
#   result.save_to("iphone_review_thumb.png")
#
# @example Blog header
#   result = Llm::Image::ThumbnailGenerator.call(
#     prompt: "Header image for article about machine learning trends"
#   )
#
# @example YouTube style
#   result = Llm::Image::ThumbnailGenerator.call(
#     prompt: "Dramatic cooking tutorial thumbnail, chef holding flaming pan"
#   )
#
module Llm
  module Images
    class ThumbnailGenerator < ApplicationImageGenerator
      description "Generates eye-catching thumbnails for videos and articles"
      version "1.0"

      # DALL-E 3 for quality
      model "gpt-image-1"

      # Landscape format for video platforms (16:9 aspect)
      size "1792x1024"

      # Standard quality is sufficient for thumbnails
      quality "standard"

      # Vivid style for attention-grabbing thumbnails
      style "vivid"

      # Standard content policy
      content_policy :standard

      # Prompt template for engaging thumbnails
      template "Eye-catching thumbnail: {prompt}. Bold colors, clear focal point, " \
               "high contrast, visually striking composition, " \
               "optimized for small preview sizes, attention-grabbing."

      # Cache thumbnails briefly
      cache_for 30.minutes
    end
  end
end
