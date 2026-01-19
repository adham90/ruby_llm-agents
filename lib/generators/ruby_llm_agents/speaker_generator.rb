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
  #   - app/speakers/narrator_speaker.rb
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

    def create_speaker_directory
      empty_directory "app/speakers" unless File.directory?("app/speakers")
    end

    def create_application_speaker
      unless File.exist?("app/speakers/application_speaker.rb")
        template "application_speaker.rb.tt", "app/speakers/application_speaker.rb"
      end
    end

    def create_speaker_file
      # Support nested paths: "article/narrator" -> "app/speakers/article/narrator_speaker.rb"
      speaker_path = name.underscore
      template "speaker.rb.tt", "app/speakers/#{speaker_path}_speaker.rb"
    end

    def show_usage
      # Build full class name from path
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Speaker #{full_class_name}Speaker created!", :green
      say ""
      say "Usage:"
      say "  # Generate speech"
      say "  result = #{full_class_name}Speaker.call(text: \"Hello world\")"
      say "  result.audio  # => Binary audio data"
      say ""
      say "  # Save to file"
      say "  result.save_to(\"output.mp3\")"
      say ""
      say "  # Stream audio"
      say "  #{full_class_name}Speaker.stream(text: \"Long article...\") do |chunk|"
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
