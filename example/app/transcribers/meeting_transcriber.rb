# frozen_string_literal: true

# MeetingTranscriber - Business meeting transcription
#
# Optimized for transcribing business meetings, conference calls,
# and professional discussions. Outputs plain text suitable for
# meeting notes and summaries.
#
# Use cases:
# - Team meeting transcriptions
# - Conference call recordings
# - Interview transcriptions
# - Webinar recordings
#
# @example Basic usage
#   result = MeetingTranscriber.call(audio: "standup_meeting.mp3")
#   result.text           # => "Good morning everyone. Let's start with..."
#   result.duration       # => 1800.5 (30 minutes)
#   result.word_count     # => 5432
#
# @example From URL
#   result = MeetingTranscriber.call(audio: "https://zoom.us/recording/abc123.mp4")
#
# @example With tenant tracking
#   result = MeetingTranscriber.call(audio: "meeting.mp3", tenant: organization)
#
class MeetingTranscriber < ApplicationTranscriber
  description "Transcribes business meetings with high accuracy"
  version "1.0"

  # Whisper-1 for reliable meeting transcription
  model "whisper-1"

  # English language (most business meetings)
  language "en"

  # Plain text output for meeting notes
  output_format :text

  # Segment-level timestamps for reference
  include_timestamps :segment

  # Cache meeting transcriptions for 30 days
  cache_for 30.days

  # Context hint for better accuracy
  def prompt
    "Business meeting with multiple speakers discussing projects, deadlines, and action items."
  end
end
