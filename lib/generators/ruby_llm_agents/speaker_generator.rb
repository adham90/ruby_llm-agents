# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Speaker generator for creating new text-to-speech speakers
  #
  # Usage:
  #   rails generate ruby_llm_agents:speaker Narrator
  #   rails generate ruby_llm_agents:speaker Narrator --provider elevenlabs
  #   rails generate ruby_llm_agents:speaker Narrator --voice alloy --speed 1.25
  #   rails generate ruby_llm_agents:speaker Narrator --root=ai
  #
  # This will create:
  #   - app/{root}/audio/speakers/narrator_speaker.rb
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
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def create_speaker_file
      # Support nested paths: "article/narrator" -> "app/{root}/audio/speakers/article/narrator_speaker.rb"
      @root_namespace = root_namespace
      @audio_namespace = "#{root_namespace}::Audio"
      speaker_path = name.underscore
      template "speaker.rb.tt", "app/#{root_directory}/audio/speakers/#{speaker_path}_speaker.rb"
    end

    def show_usage
      # Build full class name from path
      speaker_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Audio::#{speaker_class_name}Speaker"
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
