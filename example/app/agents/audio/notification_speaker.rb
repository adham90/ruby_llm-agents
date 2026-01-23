# frozen_string_literal: true

# NotificationSpeaker - Short alert and notification messages
#
# Optimized for short, quick audio notifications and alerts.
# Uses the standard TTS model with a neutral voice for clear,
# quick message delivery.
#
# Use cases:
# - System notifications
# - Alert messages
# - Status updates
# - Quick confirmations
# - Accessibility announcements
#
# @example Basic usage
#   result = Llm::Audio::NotificationSpeaker.call(text: "Your file has been uploaded")
#   result.audio        # => Binary audio data
#   result.duration     # => 1.8 (seconds)
#   result.save_to("notification.mp3")
#
# @example Quick notification
#   audio = Llm::Audio::NotificationSpeaker.call(text: "Task complete!").audio
#   play_sound(audio)
#
module Llm
  module Audio
    class NotificationSpeaker < ApplicationSpeaker
      description "Generates quick audio notifications and alerts"
      version "1.0"

      # Standard model for speed
      model "tts-1"

      # Alloy voice - neutral, clear, professional
      voice "alloy"

      # Slightly faster for notifications
      speed 1.1

      # MP3 for compatibility
      output_format :mp3

      # Short cache for notifications
      cache_for 7.days
    end
  end
end
