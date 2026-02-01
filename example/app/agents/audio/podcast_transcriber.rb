# frozen_string_literal: true

# PodcastTranscriber - Long-form podcast transcription
#
# Specialized for transcribing podcast episodes with high accuracy.
# Uses GPT-4o transcribe model for better quality on conversational
# content and outputs verbose JSON with detailed metadata.
#
# Use cases:
# - Podcast episode transcription
# - Audio show notes generation
# - Interview transcripts
# - Audio content indexing
#
# @example Basic usage
#   result = Audio::PodcastTranscriber.call(audio: "episode_42.mp3")
#   result.text           # => Full episode transcript
#   result.segments       # => Array of timed segments
#   result.duration       # => 3600.5 (1 hour)
#
# @example With detailed segments
#   result = Audio::PodcastTranscriber.call(audio: "interview.mp3")
#   result.segments.each do |segment|
#     puts "[#{segment.start}s] #{segment.text}"
#   end
#
# @example Searchable index
#   result = Audio::PodcastTranscriber.call(audio: "episode.mp3")
#   result.words.each do |word|
#     SearchIndex.add(word.text, timestamp: word.start)
#   end
#
module Audio
  class PodcastTranscriber < ApplicationTranscriber
    description 'Transcribes podcast episodes with detailed timing information'
    version '1.0'

    # GPT-4o for better conversational accuracy
    model 'gpt-4o-transcribe'

    # Verbose JSON for detailed output
    output_format :verbose_json

    # Word-level timestamps for searchability
    include_timestamps :word

    # Long cache for podcast content
    cache_for 60.days

    # Chunking for hour-long episodes
    chunking do
      self.enabled = true
      self.max_duration = 900   # 15 minutes per chunk
      self.overlap = 5          # 5 second overlap
      self.parallel = true      # Process in parallel for speed
    end

    # Reliability for long content
    reliability do
      retries max: 3, backoff: :exponential
      fallback_models 'whisper-1'
      total_timeout 600 # 10 minutes max
    end

    # Context hint for podcast content
    def prompt
      'Podcast conversation with hosts and guests discussing various topics.'
    end
  end
end
