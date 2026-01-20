# frozen_string_literal: true

# SubtitleGenerator - SRT subtitle generation for videos
#
# Generates SRT subtitle files from audio/video content.
# Perfect for adding subtitles to videos, creating captions
# for accessibility, or generating transcript files.
#
# Use cases:
# - Video subtitle generation
# - Accessibility captions
# - YouTube/Vimeo subtitles
# - Training video transcripts
#
# @example Basic usage
#   result = SubtitleGenerator.call(audio: "training_video.mp4")
#   result.srt            # => "1\n00:00:00,000 --> 00:00:02,500\nHello\n\n..."
#   File.write("subtitles.srt", result.srt)
#
# @example VTT format
#   result = SubtitleGenerator.call(audio: "video.mp4")
#   result.vtt            # => "WEBVTT\n\n00:00:00.000 --> 00:00:02.500\nHello\n\n..."
#
# @example Save directly to file
#   result = SubtitleGenerator.call(audio: "video.mp4")
#   result.save_srt("subtitles.srt")
#   result.save_vtt("subtitles.vtt")
#
class SubtitleGenerator < ApplicationTranscriber
  description "Generates SRT subtitles for video content"
  version "1.0"

  # Whisper-1 for reliable timing
  model "whisper-1"

  # SRT format for video players
  output_format :srt

  # Word-level timestamps for better subtitle sync
  include_timestamps :word

  # Cache subtitles for 14 days
  cache_for 14.days

  # Chunking for long videos
  chunking do
    self.enabled = true
    self.max_duration = 600  # 10 minutes per chunk
    self.overlap = 2         # 2 second overlap for seamless subtitles
    self.parallel = true     # Process chunks in parallel
  end
end
