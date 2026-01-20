# frozen_string_literal: true

# MultilangSpeaker - Multilingual content narration
#
# Uses ElevenLabs' multilingual model for high-quality
# text-to-speech in multiple languages. Best for content
# that needs to be delivered in various languages.
#
# Use cases:
# - International content delivery
# - Multi-language educational materials
# - Localized product announcements
# - Global customer communications
#
# @example Basic usage
#   result = Llm::Audio::MultilangSpeaker.call(text: "Bonjour, comment allez-vous?")
#   result.audio        # => Binary audio data
#   result.save_to("french_greeting.mp3")
#
# @example Spanish content
#   result = Llm::Audio::MultilangSpeaker.call(text: "Bienvenido a nuestra plataforma")
#   result.save_to("spanish_welcome.mp3")
#
# @example Japanese content
#   result = Llm::Audio::MultilangSpeaker.call(text: "ようこそ")
#   result.save_to("japanese_welcome.mp3")
#
module Llm
  module Audio
    class MultilangSpeaker < ApplicationSpeaker
      description "Generates multilingual audio content with natural pronunciation"
      version "1.0"

      # ElevenLabs for multilingual support
      provider :elevenlabs

      # Multilingual v2 model
      model "eleven_multilingual_v2"

      # Rachel voice - versatile multilingual
      voice "Rachel"

      # Standard speed
      speed 1.0

      # MP3 output
      output_format :mp3

      # Fine-tuned voice settings for clarity
      voice_settings do
        stability 0.5
        similarity_boost 0.75
        style 0.3
        speaker_boost true
      end

      # Cache for 14 days
      cache_for 14.days

      # Fallback to OpenAI if ElevenLabs fails
      reliability do
        retries max: 2, backoff: :exponential
        fallback_provider :openai, voice: "nova"
      end
    end
  end
end
