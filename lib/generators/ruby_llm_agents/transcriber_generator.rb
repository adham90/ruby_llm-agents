# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Transcriber generator for creating new transcribers
  #
  # Usage:
  #   rails generate ruby_llm_agents:transcriber Meeting
  #   rails generate ruby_llm_agents:transcriber Interview --model whisper-1
  #   rails generate ruby_llm_agents:transcriber Podcast --language en
  #
  # This will create:
  #   - app/agents/audio/meeting_transcriber.rb
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

    def ensure_base_class_and_skill_file
      audio_dir = "app/agents/audio"

      # Create directory if needed
      empty_directory audio_dir

      # Create base class if it doesn't exist
      base_class_path = "#{audio_dir}/application_transcriber.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_transcriber.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{audio_dir}/TRANSCRIBERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/TRANSCRIBERS.md.tt", skill_file_path
      end
    end

    def create_transcriber_file
      # Support nested paths: "interview/meeting" -> "app/agents/audio/interview/meeting_transcriber.rb"
      transcriber_path = name.underscore
      template "transcriber.rb.tt", "app/agents/audio/#{transcriber_path}_transcriber.rb"
    end

    def show_usage
      # Build full class name from path
      transcriber_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Audio::#{transcriber_class_name}Transcriber"
      say ""
      say "Transcriber #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # From file path"
      say "  #{full_class_name}.call(audio: \"recording.mp3\")"
      say ""
      say "  # From URL"
      say "  #{full_class_name}.call(audio: \"https://example.com/audio.mp3\")"
      say ""
      say "  # Get subtitles"
      say "  result = #{full_class_name}.call(audio: \"video.mp4\")"
      say "  result.srt  # SRT format"
      say "  result.vtt  # VTT format"
      say ""
    end
  end
end
