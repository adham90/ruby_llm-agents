# frozen_string_literal: true

# TechnicalNarrator - Technical content with proper pronunciations
#
# Specialized for technical documentation and content with
# custom pronunciations for technical terms, acronyms, and
# product names that standard TTS might mispronounce.
#
# Use cases:
# - Technical documentation narration
# - API documentation audio
# - Developer tutorial audio
# - Technical blog post narration
#
# @example Basic usage
#   result = Audio::TechnicalNarrator.call(text: "RubyLLM uses PostgreSQL for data storage")
#   # "RubyLLM" pronounced as "ruby L L M"
#   # "PostgreSQL" pronounced as "post-gres-Q-L"
#
# @example Technical documentation
#   result = Audio::TechnicalNarrator.call(text: <<~TEXT)
#     Configure nginx as a reverse proxy for your RubyLLM application.
#     The API endpoints support OAuth2 authentication via JWT tokens.
#   TEXT
#   result.save_to("setup_guide.mp3")
#
module Audio
  class TechnicalNarrator < ApplicationSpeaker
    description 'Narrates technical content with proper terminology pronunciations'
    version '1.0'

    # High-definition for documentation quality
    model 'tts-1-hd'

    # Fable voice - clear, educational tone
    voice 'fable'

    # Normal speed for technical content
    speed 1.0

    # High quality WAV for production
    output_format :mp3

    # Technical pronunciation lexicon
    lexicon do
      # Ruby ecosystem
      pronounce 'RubyLLM', 'ruby L L M'
      pronounce 'PostgreSQL', 'post-gres-Q-L'
      pronounce 'MySQL', 'my-S-Q-L'
      pronounce 'SQLite', 'S-Q-Lite'

      # Infrastructure
      pronounce 'nginx', 'engine-X'
      pronounce 'Redis', 'RED-iss'
      pronounce 'Kubernetes', 'koo-ber-NET-eez'
      pronounce 'kubectl', 'koob-control'

      # Protocols & Standards
      pronounce 'OAuth', 'oh-auth'
      pronounce 'OAuth2', 'oh-auth-two'
      pronounce 'JWT', 'J-W-T'
      pronounce 'JSON', 'JAY-son'
      pronounce 'YAML', 'YAM-ul'
      pronounce 'TOML', 'TOM-ul'
      pronounce 'GraphQL', 'graph-Q-L'
      pronounce 'REST', 'rest'
      pronounce 'gRPC', 'G-R-P-C'

      # Companies & Products
      pronounce 'OpenAI', 'open-A-I'
      pronounce 'GitHub', 'git-hub'
      pronounce 'GitLab', 'git-lab'
      pronounce 'AWS', 'A-W-S'
      pronounce 'GCP', 'G-C-P'

      # Technical terms
      pronounce 'API', 'A-P-I'
      pronounce 'SDK', 'S-D-K'
      pronounce 'CLI', 'C-L-I'
      pronounce 'REPL', 'rep-ul'
      pronounce 'regex', 'REG-ex'
      pronounce 'sudo', 'sue-doe'
      pronounce 'chmod', 'ch-mod'
    end

    # Long cache for documentation
    cache_for 30.days
  end
end
