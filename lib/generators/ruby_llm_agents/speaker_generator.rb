# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Speaker generator for creating new text-to-speech speakers
  #
  # Usage:
  #   rails generate ruby_llm_agents:speaker Narrator
  #   rails generate ruby_llm_agents:speaker Narrator --provider elevenlabs
  #   rails generate ruby_llm_agents:speaker Narrator --voice alloy --speed 1.25
  #
  # This will create:
  #   - app/agents/audio/narrator_speaker.rb
  #
  class SpeakerGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :provider, type: :string, default: "openai",
                 desc: "The TTS provider to use (openai, elevenlabs)"
    class_option :model, type: :string, default: nil,
                 desc: "The TTS model to use"
    class_option :voice, type: :string, default: "nova",
                 desc: "The voice to use"
    class_option :speed, type: :numeric, default: 1.0,
                 desc: "Speech speed (0.25-4.0 for OpenAI)"
    class_option :format, type: :string, default: "mp3",
                 desc: "Output format (mp3, wav, ogg, flac)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '7.days')"

    def ensure_base_class_and_skill_file
      audio_dir = "app/agents/audio"

      # Create directory if needed
      empty_directory audio_dir

      # Create base class if it doesn't exist
      base_class_path = "#{audio_dir}/application_speaker.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_speaker.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{audio_dir}/SPEAKERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/SPEAKERS.md.tt", skill_file_path
      end
    end

    def create_speaker_file
      # Support nested paths: "article/narrator" -> "app/agents/audio/article/narrator_speaker.rb"
      speaker_path = name.underscore
      template "speaker.rb.tt", "app/agents/audio/#{speaker_path}_speaker.rb"
    end

    def show_usage
      # Build full class name from path
      speaker_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Audio::#{speaker_class_name}Speaker"
      say ""
      say "Speaker #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Generate speech"
      say "  result = #{full_class_name}.call(text: \"Hello world\")"
      say "  result.audio  # => Binary audio data"
      say ""
      say "  # Save to file"
      say "  result.save_to(\"output.mp3\")"
      say ""
      say "  # Stream audio"
      say "  #{full_class_name}.stream(text: \"Long article...\") do |chunk|"
      say "    audio_player.play(chunk.audio)"
      say "  end"
      say ""
    end

    private

    def default_model
      case options[:provider].to_s
      when "elevenlabs"
        "eleven_monolingual_v1"
      else
        "tts-1"
      end
    end
  end
end
