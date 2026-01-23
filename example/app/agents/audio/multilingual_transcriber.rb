# frozen_string_literal: true

# MultilingualTranscriber - Auto-detect language transcription
#
# Transcribes audio in any language, automatically detecting
# the spoken language. Ideal for content where the language
# is unknown or for multilingual content.
#
# Use cases:
# - International customer support calls
# - Global webinar recordings
# - Multilingual video content
# - Language-unknown audio files
#
# @example Basic usage
#   result = Audio::MultilingualTranscriber.call(audio: "call_recording.mp3")
#   result.text           # => Transcribed text
#   result.language       # => "es" (detected Spanish)
#
# @example Mixed language content
#   result = Audio::MultilingualTranscriber.call(audio: "multilingual_meeting.mp3")
#   # Handles code-switching between languages
#
# @example With metadata
#   result = Audio::MultilingualTranscriber.call(audio: "unknown_audio.mp3")
#   puts "Detected language: #{result.language}"
#   puts "Confidence: #{result.language_confidence}"
#
module Audio
  class MultilingualTranscriber < ApplicationTranscriber
    description "Transcribes audio with automatic language detection"
    version "1.0"

    # Whisper-1 has strong multilingual support
    model "whisper-1"

    # No language specified - auto-detect
    # language nil

    # JSON output to include language detection
    output_format :json

    # Segment timestamps
    include_timestamps :segment

    # Cache for 14 days
    cache_for 14.days

    # Fallback for reliability
    fallback_models "gpt-4o-transcribe"
  end
end
