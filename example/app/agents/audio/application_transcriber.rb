# frozen_string_literal: true

# ApplicationTranscriber - Base class for all transcribers in this application
#
# All transcribers inherit from this class. Configure shared settings here
# that apply to all transcribers, or override them per-transcriber as needed.
#
# ============================================================================
# TRANSCRIBER DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "whisper-1"              # Transcription model identifier
#   language "en"                  # ISO 639-1 language code (optional)
#   version "1.0"                  # Transcriber version (affects cache keys)
#   description "..."              # Human-readable transcriber description
#
# OUTPUT FORMAT:
# --------------
#   output_format :text            # Output format (:text, :json, :srt, :vtt, :verbose_json)
#   include_timestamps :segment    # Timestamp level (:none, :segment, :word)
#
# CACHING:
# --------
#   cache_for 30.days              # Enable caching with TTL
#   # Same audio always produces the same transcription
#
# CHUNKING (for long audio):
# --------------------------
#   chunking do
#     enabled true
#     max_duration 600             # 10 minutes per chunk
#     overlap 5                    # 5 second overlap
#     parallel true                # Process chunks in parallel
#   end
#
# RELIABILITY:
# ------------
#   reliability do
#     retries max: 3, backoff: :exponential
#     fallback_models 'whisper-1', 'gpt-4o-mini-transcribe'
#     total_timeout 300
#   end
#
#   fallback_models 'whisper-1'    # Shorthand for fallback configuration
#
# CUSTOM METHODS:
# ---------------
#   def prompt
#     "Technical podcast about Ruby programming"  # Context hint for better accuracy
#   end
#
#   def postprocess_text(text)
#     text.gsub(/\bRuby L L M\b/i, 'RubyLLM')     # Post-processing corrections
#   end
#
# ============================================================================
# AVAILABLE MODELS
# ============================================================================
#
# OpenAI Models:
#   - whisper-1              # Standard Whisper model (reliable, cost-effective)
#   - gpt-4o-transcribe      # GPT-4o transcription (higher quality, more expensive)
#   - gpt-4o-mini-transcribe # GPT-4o mini transcription (balanced)
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Basic transcription
#   result = MyTranscriber.call(audio: "meeting.mp3")
#   result.text           # => "Hello everyone, welcome to the meeting..."
#   result.duration       # => 1800.5 (seconds)
#   result.word_count     # => 5432
#
#   # From URL
#   result = MyTranscriber.call(audio: "https://example.com/audio.mp3")
#
#   # With language hint
#   result = MyTranscriber.call(audio: "spanish_podcast.mp3", language: "es")
#
#   # SRT subtitles
#   result = SubtitleGenerator.call(audio: "video.mp4")
#   result.srt            # => "1\n00:00:00,000 --> 00:00:02,500\nHello\n\n..."
#
#   # With tenant for budget tracking
#   result = MyTranscriber.call(audio: "meeting.mp3", tenant: organization)
#
# ============================================================================
# OTHER TRANSCRIBER EXAMPLES
# ============================================================================
#
# See these files for specialized transcriber implementations:
#   - meeting_transcriber.rb      - Business meeting transcription
#   - subtitle_generator.rb       - SRT/VTT subtitle generation
#   - podcast_transcriber.rb      - Long-form podcast transcription
#   - multilingual_transcriber.rb - Auto-detect language transcription
#   - technical_transcriber.rb    - Technical content with postprocessing
#
module Audio
  class ApplicationTranscriber < RubyLLM::Agents::Transcriber
    # ============================================
    # Shared Model Configuration
    # ============================================
    # These settings are inherited by all transcribers

    model "whisper-1"

    # ============================================
    # Shared Caching
    # ============================================

    # cache_for 1.day  # Enable caching for all transcribers

    # ============================================
    # Shared Helper Methods
    # ============================================
    # Define methods here that can be used by all transcribers
  end
end
