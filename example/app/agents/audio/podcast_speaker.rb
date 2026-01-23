# frozen_string_literal: true

# PodcastSpeaker - Long-form podcast content narration
#
# Designed for generating podcast-style audio content. Uses the standard
# TTS model for faster processing of long content, with a deep, authoritative
# voice suitable for podcast narration.
#
# Use cases:
# - Podcast episode generation
# - Audiobook chapters
# - Long-form educational content
# - Interview transcript narration
#
# @example Basic usage
#   result = Audio::PodcastSpeaker.call(text: episode_script)
#   result.audio        # => Binary audio data
#   result.duration     # => 1200.5 (seconds, ~20 minutes)
#   result.save_to("episode_42.mp3")
#
# @example With streaming for progressive download
#   File.open("episode.mp3", "wb") do |file|
#     Audio::PodcastSpeaker.stream(text: long_script) do |chunk|
#       file.write(chunk.audio)
#     end
#   end
#
module Audio
  class PodcastSpeaker < ApplicationSpeaker
    description "Generates podcast-style audio for long-form content"
    version "1.0"

    # Standard model for faster processing of long content
    model "tts-1"

    # Onyx voice - deep, authoritative, podcast-friendly
    voice "onyx"

    # Slightly slower for podcast pacing
    speed 0.95

    # High quality AAC for podcasts
    output_format :aac

    # Enable streaming for long content
    streaming true

    # Longer cache for podcast content
    cache_for 60.days

    # Reliability settings for long content
    reliability do
      retries max: 3, backoff: :exponential
      total_timeout 300  # 5 minutes for long content
    end
  end
end
