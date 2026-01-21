# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Transcriber generator for creating new transcribers
  #
  # Usage:
  #   rails generate ruby_llm_agents:transcriber Meeting
  #   rails generate ruby_llm_agents:transcriber Meeting --model gpt-4o-transcribe
  #   rails generate ruby_llm_agents:transcriber Meeting --language es
  #   rails generate ruby_llm_agents:transcriber Meeting --root=ai
  #
  # This will create:
  #   - app/{root}/audio/transcribers/meeting_transcriber.rb
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
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def ensure_base_class_and_skill_file
      @root_namespace = root_namespace
      @audio_namespace = "#{root_namespace}::Audio"
      transcribers_dir = "app/#{root_directory}/audio/transcribers"

      # Create directory if needed
      empty_directory transcribers_dir

      # Create base class if it doesn't exist
      base_class_path = "#{transcribers_dir}/application_transcriber.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_transcriber.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{transcribers_dir}/TRANSCRIBERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/TRANSCRIBERS.md.tt", skill_file_path
      end
    end

    def create_transcriber_file
      # Support nested paths: "interview/meeting" -> "app/{root}/audio/transcribers/interview/meeting_transcriber.rb"
      @root_namespace = root_namespace
      @audio_namespace = "#{root_namespace}::Audio"
      transcriber_path = name.underscore
      template "transcriber.rb.tt", "app/#{root_directory}/audio/transcribers/#{transcriber_path}_transcriber.rb"
    end

    def show_usage
      # Build full class name from path
      transcriber_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Audio::#{transcriber_class_name}Transcriber"
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

    private

    def root_directory
      @root_directory ||= options[:root] || RubyLLM::Agents.configuration.root_directory
    end

    def root_namespace
      @root_namespace ||= options[:namespace] || camelize(root_directory)
    end

    def camelize(str)
      # Handle special cases for common abbreviations
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"

      # Standard camelization
      str.split(/[-_]/).map(&:capitalize).join
    end
  end
end
