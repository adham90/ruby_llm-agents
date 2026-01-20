# frozen_string_literal: true

# ApplicationSpeaker - Base class for all speakers in this application
#
# All speakers inherit from this class. Configure shared settings here
# that apply to all speakers, or override them per-speaker as needed.
#
# ============================================================================
# SPEAKER DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   provider :openai               # TTS provider (:openai, :elevenlabs, :google, :polly)
#   model "tts-1-hd"               # TTS model identifier
#   voice "nova"                   # Voice name (OpenAI: alloy, echo, fable, onyx, nova, shimmer)
#   voice_id "abc123"              # Custom/cloned voice ID (ElevenLabs)
#   speed 1.0                      # Speech speed (0.25 to 4.0 for OpenAI)
#   output_format :mp3             # Output format (:mp3, :opus, :aac, :flac, :wav, :pcm)
#   version "1.0"                  # Speaker version (affects cache keys)
#   description "..."              # Human-readable speaker description
#
# VOICE SETTINGS (ElevenLabs):
# ----------------------------
#   voice_settings do
#     stability 0.5                # Voice stability (0.0 to 1.0)
#     similarity_boost 0.75        # Similarity boost (0.0 to 1.0)
#     style 0.5                    # Style (0.0 to 1.0)
#     speaker_boost true           # Enable speaker boost
#   end
#
# STREAMING:
# ----------
#   streaming true                 # Enable streaming output
#
# SSML:
# -----
#   ssml_enabled true              # Enable SSML input processing
#
# PRONUNCIATION LEXICON:
# ----------------------
#   lexicon do
#     pronounce 'RubyLLM', 'ruby L L M'
#     pronounce 'PostgreSQL', 'post-gres-Q-L'
#     pronounce 'nginx', 'engine-X'
#   end
#
# CACHING:
# --------
#   cache_for 30.days              # Enable caching with TTL
#   # Same text + settings always produces the same audio
#
# RELIABILITY:
# ------------
#   reliability do
#     retries max: 3, backoff: :exponential
#     fallback_provider :openai, voice: 'nova'
#     total_timeout 120
#   end
#
# ============================================================================
# AVAILABLE PROVIDERS & MODELS
# ============================================================================
#
# OpenAI:
#   - tts-1          # Standard quality, fast
#   - tts-1-hd       # High definition, better for long-form
#   Voices: alloy, echo, fable, onyx, nova, shimmer
#
# ElevenLabs:
#   - eleven_multilingual_v2    # Best for multilingual
#   - eleven_turbo_v2           # Fast, English-optimized
#   - eleven_turbo_v2_5         # Latest turbo model
#   Voices: Many pre-made and custom options
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Single text to speech
#   result = MySpeaker.call(text: "Hello world")
#   result.audio        # => Binary audio data
#   result.duration     # => 1.5 (seconds)
#   result.characters   # => 11
#   result.save_to("output.mp3")
#
#   # With streaming
#   MySpeaker.stream(text: "Long article...") do |chunk|
#     audio_player.play(chunk.audio)
#   end
#
#   # With tenant for budget tracking
#   MySpeaker.call(text: "hello", tenant: organization)
#
# ============================================================================
# OTHER SPEAKER EXAMPLES
# ============================================================================
#
# See these files for specialized speaker implementations:
#   - article_narrator.rb      - High quality article narration
#   - podcast_speaker.rb       - Long-form podcast content
#   - notification_speaker.rb  - Short alert/notification messages
#   - multilang_speaker.rb     - Multi-language content (ElevenLabs)
#   - technical_narrator.rb    - Technical content with pronunciations
#
module Llm
  module Audio
    class ApplicationSpeaker < RubyLLM::Agents::Speaker
      # ============================================
      # Shared Model Configuration
      # ============================================
      # These settings are inherited by all speakers

      provider :openai
      model "tts-1"
      voice "alloy"

      # ============================================
      # Shared Caching
      # ============================================

      # cache_for 1.day  # Enable caching for all speakers

      # ============================================
      # Shared Helper Methods
      # ============================================
      # Define methods here that can be used by all speakers
    end
  end
end
