# frozen_string_literal: true

# TechnicalTranscriber - Technical content with postprocessing
#
# Specialized for transcribing technical content like developer
# talks, programming tutorials, and technical documentation.
# Includes postprocessing to correct common technical term
# transcription errors.
#
# Use cases:
# - Developer conference talks
# - Technical tutorials
# - Code review recordings
# - Technical documentation audio
#
# @example Basic usage
#   result = TechnicalTranscriber.call(audio: "rails_conf_talk.mp3")
#   result.text           # => "RubyLLM is a powerful framework..."
#   # Technical terms are properly formatted
#
# @example Programming tutorial
#   result = TechnicalTranscriber.call(audio: "ruby_tutorial.mp3")
#   # "open A I" -> "OpenAI"
#   # "post gres Q L" -> "PostgreSQL"
#
class TechnicalTranscriber < ApplicationTranscriber
  description "Transcribes technical content with terminology corrections"
  version "1.0"

  # GPT-4o for better technical accuracy
  model "gpt-4o-transcribe"

  # English (most technical content)
  language "en"

  # Plain text output
  output_format :text

  # Segment timestamps for reference
  include_timestamps :segment

  # Cache for 30 days
  cache_for 30.days

  # Context hint for technical accuracy
  def prompt
    "Technical discussion about software development, Ruby programming, APIs, " \
    "databases, and cloud infrastructure. Speakers mention RubyLLM, PostgreSQL, " \
    "Redis, Kubernetes, Docker, OpenAI, and other technical terms."
  end

  # Postprocess to fix common technical term transcription errors
  def postprocess_text(text)
    result = text
    # Ruby ecosystem
    result = result.gsub(/\bRuby L L M\b/i, "RubyLLM")
    result = result.gsub(/\bruby llm\b/i, "RubyLLM")
    # Databases
    result = result.gsub(/\bpost gres Q L\b/i, "PostgreSQL")
    result = result.gsub(/\bpostgres q l\b/i, "PostgreSQL")
    result = result.gsub(/\bmy S Q L\b/i, "MySQL")
    result = result.gsub(/\bS Q Lite\b/i, "SQLite")
    # Infrastructure
    result = result.gsub(/\bengine X\b/i, "nginx")
    result = result.gsub(/\bkuber net ease\b/i, "Kubernetes")
    result = result.gsub(/\bkube control\b/i, "kubectl")
    # Protocols
    result = result.gsub(/\boh auth\b/i, "OAuth")
    result = result.gsub(/\bJ W T\b/i, "JWT")
    result = result.gsub(/\bJ son\b/i, "JSON")
    result = result.gsub(/\bgraph Q L\b/i, "GraphQL")
    result = result.gsub(/\bG R P C\b/i, "gRPC")
    # Companies
    result = result.gsub(/\bopen A I\b/i, "OpenAI")
    result = result.gsub(/\bgit hub\b/i, "GitHub")
    result = result.gsub(/\bgit lab\b/i, "GitLab")
    # Technical terms
    result = result.gsub(/\bA P I\b/i, "API")
    result = result.gsub(/\bS D K\b/i, "SDK")
    result = result.gsub(/\bC L I\b/i, "CLI")
    result = result.gsub(/\brep ul\b/i, "REPL")
    result = result.gsub(/\bsue doe\b/i, "sudo")
    result
  end
end
