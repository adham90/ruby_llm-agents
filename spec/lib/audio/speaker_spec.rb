# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker do
  let(:speaker_class) do
    Class.new(described_class) do
      def self.name
        "TestSpeaker"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_tts_provider = :openai
      c.default_tts_model = "tts-1"
      c.default_tts_voice = "nova"
    end
  end

  describe ".agent_type" do
    it "returns :audio" do
      expect(speaker_class.agent_type).to eq(:audio)
    end
  end

  describe ".provider" do
    it "sets and gets the provider" do
      speaker_class.provider :elevenlabs
      expect(speaker_class.provider).to eq(:elevenlabs)
    end

    it "defaults to config default_tts_provider" do
      expect(speaker_class.provider).to eq(:openai)
    end
  end

  describe ".model" do
    it "sets and gets the model" do
      speaker_class.model "tts-1-hd"
      expect(speaker_class.model).to eq("tts-1-hd")
    end

    it "defaults to config default_tts_model" do
      expect(speaker_class.model).to eq("tts-1")
    end
  end

  describe ".voice" do
    it "sets and gets the voice" do
      speaker_class.voice "alloy"
      expect(speaker_class.voice).to eq("alloy")
    end

    it "defaults to config default_tts_voice" do
      expect(speaker_class.voice).to eq("nova")
    end
  end

  describe ".voice_id" do
    it "sets and gets the voice_id" do
      speaker_class.voice_id "custom-voice-123"
      expect(speaker_class.voice_id).to eq("custom-voice-123")
    end

    it "returns nil by default" do
      expect(speaker_class.voice_id).to be_nil
    end
  end

  describe ".speed" do
    it "sets and gets the speed" do
      speaker_class.speed 1.5
      expect(speaker_class.speed).to eq(1.5)
    end

    it "defaults to 1.0" do
      expect(speaker_class.speed).to eq(1.0)
    end
  end

  describe ".output_format" do
    it "sets and gets the output format" do
      speaker_class.output_format :wav
      expect(speaker_class.output_format).to eq(:wav)
    end

    it "defaults to :mp3" do
      expect(speaker_class.output_format).to eq(:mp3)
    end
  end

  describe ".streaming" do
    it "sets and gets streaming mode" do
      speaker_class.streaming true
      expect(speaker_class.streaming).to be true
      expect(speaker_class.streaming?).to be true
    end

    it "defaults to false" do
      expect(speaker_class.streaming).to be false
      expect(speaker_class.streaming?).to be false
    end
  end

  describe ".voice_settings" do
    it "configures voice settings with DSL" do
      speaker_class.voice_settings do
        stability 0.6
        similarity_boost 0.8
        style 0.3
        speaker_boost false
      end

      settings = speaker_class.voice_settings_config
      expect(settings.stability_value).to eq(0.6)
      expect(settings.similarity_boost_value).to eq(0.8)
      expect(settings.style_value).to eq(0.3)
      expect(settings.speaker_boost_value).to be false
    end

    it "provides default voice settings" do
      speaker_class.voice_settings {}
      settings = speaker_class.voice_settings_config

      expect(settings.stability_value).to eq(0.5)
      expect(settings.similarity_boost_value).to eq(0.75)
    end
  end

  describe ".lexicon" do
    it "configures pronunciations" do
      speaker_class.lexicon do
        pronounce "API", "A P I"
        pronounce "SQL", "sequel"
      end

      lexicon = speaker_class.lexicon_config
      expect(lexicon.pronunciations["API"]).to eq("A P I")
      expect(lexicon.pronunciations["SQL"]).to eq("sequel")
    end
  end

  describe "VoiceSettings" do
    let(:settings) { described_class::VoiceSettings.new }

    describe "#to_h" do
      it "returns hash with all settings" do
        settings.stability 0.7
        settings.similarity_boost 0.9

        hash = settings.to_h
        expect(hash[:stability]).to eq(0.7)
        expect(hash[:similarity_boost]).to eq(0.9)
        expect(hash).to have_key(:style)
        expect(hash).to have_key(:use_speaker_boost)
      end
    end
  end

  describe "Lexicon" do
    let(:lexicon) { described_class::Lexicon.new }

    describe "#apply" do
      it "replaces pronunciations in text" do
        lexicon.pronounce "API", "A P I"
        lexicon.pronounce "SQL", "sequel"

        result = lexicon.apply("The API uses SQL for queries")
        expect(result).to eq("The A P I uses sequel for queries")
      end

      it "handles case insensitive replacements" do
        lexicon.pronounce "api", "A P I"

        result = lexicon.apply("The API is great")
        expect(result).to eq("The A P I is great")
      end

      it "only replaces whole words" do
        lexicon.pronounce "cat", "feline"

        result = lexicon.apply("The cat and category")
        expect(result).to eq("The feline and category")
      end
    end

    describe "#to_h" do
      it "returns copy of pronunciations" do
        lexicon.pronounce "test", "replacement"
        hash = lexicon.to_h

        expect(hash["test"]).to eq("replacement")
        expect(hash).not_to equal(lexicon.pronunciations)
      end
    end
  end

  describe "#initialize" do
    it "requires text parameter" do
      expect {
        speaker_class.new(text: "Hello")
      }.not_to raise_error
    end

    it "stores the text" do
      speaker = speaker_class.new(text: "Hello world")
      expect(speaker.text).to eq("Hello world")
    end
  end

  describe "inheritance" do
    let(:parent_speaker) do
      Class.new(described_class) do
        def self.name
          "ParentSpeaker"
        end

        provider :elevenlabs
        model "eleven_multilingual_v2"
        voice "Rachel"
        speed 1.2
      end
    end

    let(:child_speaker) do
      Class.new(parent_speaker) do
        def self.name
          "ChildSpeaker"
        end
      end
    end

    it "inherits settings from parent" do
      expect(child_speaker.provider).to eq(:elevenlabs)
      expect(child_speaker.model).to eq("eleven_multilingual_v2")
      expect(child_speaker.voice).to eq("Rachel")
      expect(child_speaker.speed).to eq(1.2)
    end

    it "allows child to override parent settings" do
      child_speaker.model "tts-1"
      expect(child_speaker.model).to eq("tts-1")
      expect(parent_speaker.model).to eq("eleven_multilingual_v2")
    end
  end
end
