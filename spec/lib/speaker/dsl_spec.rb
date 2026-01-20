# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker::DSL do
  # Create test speaker classes for each test
  let(:base_speaker) do
    Class.new(RubyLLM::Agents::Speaker)
  end

  describe ".provider" do
    it "sets and returns the provider" do
      base_speaker.provider :elevenlabs
      expect(base_speaker.provider).to eq(:elevenlabs)
    end

    it "returns default when not set" do
      expect(base_speaker.provider).to eq(RubyLLM::Agents.configuration.default_tts_provider)
    end

    it "inherits from parent class" do
      base_speaker.provider :elevenlabs
      child = Class.new(base_speaker)
      expect(child.provider).to eq(:elevenlabs)
    end
  end

  describe ".model" do
    it "sets and returns the model" do
      base_speaker.model "tts-1-hd"
      expect(base_speaker.model).to eq("tts-1-hd")
    end

    it "returns default when not set" do
      expect(base_speaker.model).to eq(RubyLLM::Agents.configuration.default_tts_model)
    end

    it "inherits from parent class" do
      base_speaker.model "tts-1-hd"
      child = Class.new(base_speaker)
      expect(child.model).to eq("tts-1-hd")
    end
  end

  describe ".voice" do
    it "sets and returns voice" do
      base_speaker.voice "alloy"
      expect(base_speaker.voice).to eq("alloy")
    end

    it "returns default when not set" do
      expect(base_speaker.voice).to eq(RubyLLM::Agents.configuration.default_tts_voice)
    end

    it "inherits from parent class" do
      base_speaker.voice "echo"
      child = Class.new(base_speaker)
      expect(child.voice).to eq("echo")
    end
  end

  describe ".voice_id" do
    it "sets and returns voice_id" do
      base_speaker.voice_id "21m00Tcm4TlvDq8ikWAM"
      expect(base_speaker.voice_id).to eq("21m00Tcm4TlvDq8ikWAM")
    end

    it "returns nil when not set" do
      expect(base_speaker.voice_id).to be_nil
    end
  end

  describe ".speed" do
    it "sets and returns speed" do
      base_speaker.speed 1.25
      expect(base_speaker.speed).to eq(1.25)
    end

    it "returns default when not set" do
      expect(base_speaker.speed).to eq(1.0)
    end

    it "inherits from parent class" do
      base_speaker.speed 0.75
      child = Class.new(base_speaker)
      expect(child.speed).to eq(0.75)
    end
  end

  describe ".output_format" do
    it "sets and returns output_format" do
      base_speaker.output_format :wav
      expect(base_speaker.output_format).to eq(:wav)
    end

    it "returns default when not set" do
      expect(base_speaker.output_format).to eq(:mp3)
    end

    it "inherits from parent class" do
      base_speaker.output_format :ogg
      child = Class.new(base_speaker)
      expect(child.output_format).to eq(:ogg)
    end
  end

  describe ".streaming" do
    it "sets and returns streaming" do
      base_speaker.streaming true
      expect(base_speaker.streaming).to be true
    end

    it "returns false when not set" do
      expect(base_speaker.streaming).to be false
    end
  end

  describe ".ssml_enabled" do
    it "sets and returns ssml_enabled" do
      base_speaker.ssml_enabled true
      expect(base_speaker.ssml_enabled).to be true
    end

    it "returns false when not set" do
      expect(base_speaker.ssml_enabled).to be false
    end
  end

  describe ".voice_settings" do
    it "configures ElevenLabs voice settings" do
      base_speaker.voice_settings do
        stability 0.5
        similarity_boost 0.75
        style 0.5
        speaker_boost true
      end

      settings = base_speaker.voice_settings_config.to_h
      expect(settings[:stability]).to eq(0.5)
      expect(settings[:similarity_boost]).to eq(0.75)
      expect(settings[:style]).to eq(0.5)
      expect(settings[:use_speaker_boost]).to be true
    end
  end

  describe ".lexicon" do
    it "configures pronunciation lexicon" do
      base_speaker.lexicon do
        pronounce "RubyLLM", "ruby L L M"
        pronounce "PostgreSQL", "post-gres-Q-L"
      end

      lexicon = base_speaker.lexicon_config.to_h
      expect(lexicon["RubyLLM"]).to eq("ruby L L M")
      expect(lexicon["PostgreSQL"]).to eq("post-gres-Q-L")
    end
  end

  describe ".cache_for" do
    it "enables caching with TTL" do
      base_speaker.cache_for 1.week
      expect(base_speaker.cache_enabled?).to be true
      expect(base_speaker.cache_ttl).to eq(1.week)
    end
  end

  describe ".cache_enabled?" do
    it "returns false by default" do
      expect(base_speaker.cache_enabled?).to be false
    end

    it "returns true after cache_for is called" do
      base_speaker.cache_for 1.hour
      expect(base_speaker.cache_enabled?).to be true
    end
  end

  describe ".cache_ttl" do
    it "returns default TTL when not set" do
      expect(base_speaker.cache_ttl).to eq(1.hour)
    end

    it "returns configured TTL" do
      base_speaker.cache_for 7.days
      expect(base_speaker.cache_ttl).to eq(7.days)
    end
  end

  describe ".version" do
    it "sets and returns version" do
      base_speaker.version "2.0"
      expect(base_speaker.version).to eq("2.0")
    end

    it "returns default when not set" do
      expect(base_speaker.version).to eq("1.0")
    end
  end

  describe ".description" do
    it "sets and returns description" do
      base_speaker.description "Narrates articles with natural voice"
      expect(base_speaker.description).to eq("Narrates articles with natural voice")
    end

    it "returns nil when not set" do
      expect(base_speaker.description).to be_nil
    end
  end

  describe ".reliability" do
    it "configures reliability settings" do
      base_speaker.reliability do
        retries max: 5, backoff: :linear
      end

      config = base_speaker.reliability_config.to_h
      expect(config[:max_retries]).to eq(5)
      expect(config[:backoff]).to eq(:linear)
    end
  end

  describe ".reliability with fallback_provider" do
    it "sets fallback provider" do
      base_speaker.reliability do
        fallback_provider :google, voice: "en-US-Standard-A"
      end

      config = base_speaker.reliability_config.to_h
      expect(config[:fallback_provider][:provider]).to eq(:google)
      expect(config[:fallback_provider][:voice]).to eq("en-US-Standard-A")
    end
  end

  describe "DSL inheritance" do
    it "allows child classes to override parent settings" do
      base_speaker.provider :openai
      base_speaker.voice "nova"
      base_speaker.speed 1.0

      child = Class.new(base_speaker) do
        provider :elevenlabs
        # voice and speed not overridden
      end

      expect(child.provider).to eq(:elevenlabs)
      expect(child.voice).to eq("nova")
      expect(child.speed).to eq(1.0)
    end
  end
end
