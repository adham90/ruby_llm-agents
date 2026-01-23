# frozen_string_literal: true

# ArticleNarrator - High-quality article narration
#
# Converts written articles into professional audio narration using
# OpenAI's high-definition TTS model. Optimized for long-form content
# like blog posts, news articles, and documentation.
#
# Use cases:
# - Blog post audio versions
# - News article narration
# - Documentation audio guides
# - Educational content
#
# @example Basic usage
#   result = Llm::Audio::ArticleNarrator.call(text: "Welcome to our blog post...")
#   result.audio        # => Binary MP3 data
#   result.duration     # => 45.2 (seconds)
#   result.characters   # => 2500
#   result.save_to("article.mp3")
#
# @example With streaming for real-time playback
#   Llm::Audio::ArticleNarrator.stream(text: long_article) do |chunk|
#     audio_buffer.append(chunk.audio)
#   end
#
# @example With tenant tracking
#   Llm::Audio::ArticleNarrator.call(text: content, tenant: organization)
#
module Llm
  module Audio
    class ArticleNarrator < ApplicationSpeaker
      description "Narrates articles with professional, high-quality voice"
      version "1.0"

      # High-definition model for better quality
      model "tts-1-hd"

      # Nova voice - warm, engaging, good for articles
      voice "nova"

      # Standard speech speed
      speed 1.0

      # MP3 output for compatibility
      output_format :mp3

      # Cache narrations for 30 days
      cache_for 30.days
    end
  end
end
