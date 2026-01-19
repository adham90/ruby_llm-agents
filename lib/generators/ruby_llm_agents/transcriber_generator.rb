# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Transcriber generator for creating new transcribers
  #
  # Usage:
  #   rails generate ruby_llm_agents:transcriber Meeting
  #   rails generate ruby_llm_agents:transcriber Meeting --model gpt-4o-transcribe
  #   rails generate ruby_llm_agents:transcriber Meeting --language es
  #
  # This will create:
  #   - app/transcribers/meeting_transcriber.rb
  #
  class TranscriberGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "whisper-1",
                 desc: "The transcription model to use"
    class_option :language, type: :string, default: nil,
                 desc: "Language code (e.g., 'en', 'es')"
    class_option :output_format, type: :string, default: "text",
                 desc: "Output format (text, srt, vtt, json)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '30.days')"

    def create_transcriber_directory
      empty_directory "app/transcribers" unless File.directory?("app/transcribers")
    end

    def create_application_transcriber
      unless File.exist?("app/transcribers/application_transcriber.rb")
        template "application_transcriber.rb.tt", "app/transcribers/application_transcriber.rb"
      end
    end

    def create_transcriber_file
      # Support nested paths: "interview/meeting" -> "app/transcribers/interview/meeting_transcriber.rb"
      transcriber_path = name.underscore
      template "transcriber.rb.tt", "app/transcribers/#{transcriber_path}_transcriber.rb"
    end

    def show_usage
      # Build full class name from path
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Transcriber #{full_class_name}Transcriber created!", :green
      say ""
      say "Usage:"
      say "  # From file path"
      say "  #{full_class_name}Transcriber.call(audio: \"recording.mp3\")"
      say ""
      say "  # From URL"
      say "  #{full_class_name}Transcriber.call(audio: \"https://example.com/audio.mp3\")"
      say ""
      say "  # Get subtitles"
      say "  result = #{full_class_name}Transcriber.call(audio: \"video.mp4\")"
      say "  result.srt  # SRT format"
      say "  result.vtt  # VTT format"
      say ""
    end
  end
end
