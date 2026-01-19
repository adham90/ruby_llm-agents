# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Transcriber::DSL do
  # Create test transcriber classes for each test
  let(:base_transcriber) do
    Class.new(RubyLLM::Agents::Transcriber)
  end

  describe ".model" do
    it "sets and returns the model" do
      base_transcriber.model "gpt-4o-transcribe"
      expect(base_transcriber.model).to eq("gpt-4o-transcribe")
    end

    it "returns default when not set" do
      expect(base_transcriber.model).to eq(RubyLLM::Agents.configuration.default_transcription_model)
    end

    it "inherits from parent class" do
      base_transcriber.model "gpt-4o-transcribe"
      child = Class.new(base_transcriber)
      expect(child.model).to eq("gpt-4o-transcribe")
    end
  end

  describe ".language" do
    it "sets and returns language" do
      base_transcriber.language "es"
      expect(base_transcriber.language).to eq("es")
    end

    it "returns nil when not set (auto-detect)" do
      expect(base_transcriber.language).to be_nil
    end

    it "inherits from parent class" do
      base_transcriber.language "fr"
      child = Class.new(base_transcriber)
      expect(child.language).to eq("fr")
    end
  end

  describe ".output_format" do
    it "sets and returns output_format" do
      base_transcriber.output_format :json
      expect(base_transcriber.output_format).to eq(:json)
    end

    it "returns default when not set" do
      expect(base_transcriber.output_format).to eq(:text)
    end

    it "inherits from parent class" do
      base_transcriber.output_format :srt
      child = Class.new(base_transcriber)
      expect(child.output_format).to eq(:srt)
    end
  end

  describe ".include_timestamps" do
    it "sets and returns timestamp granularity" do
      base_transcriber.include_timestamps :word
      expect(base_transcriber.include_timestamps).to eq(:word)
    end

    it "returns default when not set" do
      expect(base_transcriber.include_timestamps).to eq(:none)
    end

    it "inherits from parent class" do
      base_transcriber.include_timestamps :segment
      child = Class.new(base_transcriber)
      expect(child.include_timestamps).to eq(:segment)
    end
  end

  describe ".cache_for" do
    it "enables caching with TTL" do
      base_transcriber.cache_for 1.week
      expect(base_transcriber.cache_enabled?).to be true
      expect(base_transcriber.cache_ttl).to eq(1.week)
    end
  end

  describe ".cache_enabled?" do
    it "returns false by default" do
      expect(base_transcriber.cache_enabled?).to be false
    end

    it "returns true after cache_for is called" do
      base_transcriber.cache_for 1.hour
      expect(base_transcriber.cache_enabled?).to be true
    end
  end

  describe ".cache_ttl" do
    it "returns default TTL when not set" do
      expect(base_transcriber.cache_ttl).to eq(1.hour)
    end

    it "returns configured TTL" do
      base_transcriber.cache_for 1.day
      expect(base_transcriber.cache_ttl).to eq(1.day)
    end
  end

  describe ".version" do
    it "sets and returns version" do
      base_transcriber.version "2.0"
      expect(base_transcriber.version).to eq("2.0")
    end

    it "returns default when not set" do
      expect(base_transcriber.version).to eq("1.0")
    end
  end

  describe ".description" do
    it "sets and returns description" do
      base_transcriber.description "Transcribes meeting recordings"
      expect(base_transcriber.description).to eq("Transcribes meeting recordings")
    end

    it "returns nil when not set" do
      expect(base_transcriber.description).to be_nil
    end
  end

  describe ".chunking" do
    it "configures chunking settings" do
      base_transcriber.chunking do
        max_size "25MB"
        overlap 5.seconds
        strategy :silent_split
      end

      config = base_transcriber.chunking_config
      expect(config[:max_size]).to eq("25MB")
      expect(config[:overlap]).to eq(5.seconds)
      expect(config[:strategy]).to eq(:silent_split)
    end
  end

  describe ".reliability" do
    it "configures reliability settings" do
      base_transcriber.reliability do
        retry_on_failure max_attempts: 3
      end

      config = base_transcriber.reliability_config
      expect(config[:max_attempts]).to eq(3)
    end
  end

  describe ".fallback_models" do
    it "sets fallback models" do
      base_transcriber.fallback_models "gpt-4o-transcribe", "whisper-1"
      expect(base_transcriber.fallback_models).to eq(["gpt-4o-transcribe", "whisper-1"])
    end

    it "returns empty array when not set" do
      expect(base_transcriber.fallback_models).to eq([])
    end
  end

  describe "DSL inheritance" do
    it "allows child classes to override parent settings" do
      base_transcriber.model "whisper-1"
      base_transcriber.language "en"

      child = Class.new(base_transcriber) do
        model "gpt-4o-transcribe"
        # language not overridden
      end

      expect(child.model).to eq("gpt-4o-transcribe")
      expect(child.language).to eq("en")
    end
  end
end
