# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Transcriber do
  let(:transcriber_class) do
    Class.new(described_class) do
      def self.name
        "TestTranscriber"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_transcription_model = "whisper-1"
    end
  end

  describe ".agent_type" do
    it "returns :audio" do
      expect(transcriber_class.agent_type).to eq(:audio)
    end
  end

  describe ".model" do
    it "sets and gets the model" do
      transcriber_class.model "gpt-4o-transcribe"
      expect(transcriber_class.model).to eq("gpt-4o-transcribe")
    end

    it "defaults to config default_transcription_model" do
      expect(transcriber_class.model).to eq("whisper-1")
    end

    it "falls back to 'whisper-1' when not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(transcriber_class.model).to eq("whisper-1")
    end
  end

  describe ".language" do
    it "sets and gets the language" do
      transcriber_class.language "es"
      expect(transcriber_class.language).to eq("es")
    end

    it "returns nil by default" do
      expect(transcriber_class.language).to be_nil
    end
  end

  describe ".output_format" do
    it "sets and gets the output format" do
      transcriber_class.output_format :srt
      expect(transcriber_class.output_format).to eq(:srt)
    end

    it "defaults to :text" do
      expect(transcriber_class.output_format).to eq(:text)
    end

    it "accepts all valid formats" do
      [:text, :json, :srt, :vtt, :verbose_json].each do |format|
        transcriber_class.output_format format
        expect(transcriber_class.output_format).to eq(format)
      end
    end
  end

  describe ".include_timestamps" do
    it "sets and gets the timestamp level" do
      transcriber_class.include_timestamps :word
      expect(transcriber_class.include_timestamps).to eq(:word)
    end

    it "defaults to :segment" do
      expect(transcriber_class.include_timestamps).to eq(:segment)
    end

    it "accepts all valid levels" do
      [:none, :segment, :word].each do |level|
        transcriber_class.include_timestamps level
        expect(transcriber_class.include_timestamps).to eq(level)
      end
    end
  end

  describe ".fallback_models" do
    it "sets and gets fallback models" do
      transcriber_class.fallback_models "gpt-4o-transcribe", "gpt-4o-mini-transcribe"
      expect(transcriber_class.fallback_models).to eq(["gpt-4o-transcribe", "gpt-4o-mini-transcribe"])
    end

    it "accepts array syntax" do
      transcriber_class.fallback_models ["model1", "model2"]
      expect(transcriber_class.fallback_models).to eq(["model1", "model2"])
    end

    it "returns empty array by default" do
      expect(transcriber_class.fallback_models).to eq([])
    end
  end

  describe ".chunking" do
    it "configures chunking with DSL" do
      transcriber_class.chunking do
        self.enabled = true
        self.max_duration = 300
        self.overlap = 10
        self.parallel = true
      end

      config = transcriber_class.chunking_config
      expect(config.enabled?).to be true
      expect(config.max_duration).to eq(300)
      expect(config.overlap).to eq(10)
      expect(config.parallel).to be true
    end

    it "provides default chunking values" do
      transcriber_class.chunking {}
      config = transcriber_class.chunking_config

      expect(config.enabled?).to be false
      expect(config.max_duration).to eq(600)
      expect(config.overlap).to eq(5)
      expect(config.parallel).to be false
    end
  end

  describe ".reliability" do
    it "configures reliability with DSL" do
      transcriber_class.reliability do
        retries max: 5, backoff: :constant
        fallback_models "backup-model"
        total_timeout 120
      end

      config = transcriber_class.reliability_config
      expect(config.max_retries).to eq(5)
      expect(config.backoff).to eq(:constant)
      expect(config.fallback_models_list).to eq(["backup-model"])
      expect(config.total_timeout_seconds).to eq(120)
    end

    it "provides default reliability values" do
      transcriber_class.reliability {}
      config = transcriber_class.reliability_config

      expect(config.max_retries).to eq(3)
      expect(config.backoff).to eq(:exponential)
      expect(config.fallback_models_list).to eq([])
      expect(config.total_timeout_seconds).to be_nil
    end
  end

  describe "ChunkingConfig" do
    let(:config) { described_class::ChunkingConfig.new }

    describe "#to_h" do
      it "returns hash with all settings" do
        config.enabled = true
        config.max_duration = 300

        hash = config.to_h
        expect(hash[:enabled]).to be true
        expect(hash[:max_duration]).to eq(300)
        expect(hash).to have_key(:overlap)
        expect(hash).to have_key(:parallel)
      end
    end

    describe "#enabled?" do
      it "returns enabled status" do
        expect(config.enabled?).to be false
        config.enabled = true
        expect(config.enabled?).to be true
      end
    end
  end

  describe "ReliabilityConfig" do
    let(:config) { described_class::ReliabilityConfig.new }

    describe "#retries" do
      it "sets max retries and backoff" do
        config.retries(max: 10, backoff: :linear)
        expect(config.max_retries).to eq(10)
        expect(config.backoff).to eq(:linear)
      end
    end

    describe "#fallback_models" do
      it "sets fallback models list" do
        config.fallback_models("model1", "model2")
        expect(config.fallback_models_list).to eq(["model1", "model2"])
      end
    end

    describe "#total_timeout" do
      it "sets total timeout" do
        config.total_timeout(60)
        expect(config.total_timeout_seconds).to eq(60)
      end
    end

    describe "#to_h" do
      it "returns hash with all settings" do
        config.retries(max: 5, backoff: :constant)
        config.fallback_models("backup")
        config.total_timeout(120)

        hash = config.to_h
        expect(hash[:max_retries]).to eq(5)
        expect(hash[:backoff]).to eq(:constant)
        expect(hash[:fallback_models]).to eq(["backup"])
        expect(hash[:total_timeout]).to eq(120)
      end
    end
  end

  describe "#initialize" do
    it "accepts audio parameter" do
      transcriber = transcriber_class.new(audio: "test.mp3")
      expect(transcriber.audio).to eq("test.mp3")
    end

    it "accepts format parameter" do
      transcriber = transcriber_class.new(audio: "binary data", format: :mp3)
      expect(transcriber.audio_format).to eq(:mp3)
    end

    it "accepts runtime language override" do
      transcriber_class.language "en"
      transcriber = transcriber_class.new(audio: "test.mp3", language: "fr")

      # Runtime language should override class language
      expect(transcriber.send(:resolved_language)).to eq("fr")
    end
  end

  describe "#user_prompt" do
    it "returns URL description for URLs" do
      transcriber = transcriber_class.new(audio: "https://example.com/audio.mp3")
      expect(transcriber.user_prompt).to eq("Audio URL: https://example.com/audio.mp3")
    end

    it "returns file description for file paths" do
      transcriber = transcriber_class.new(audio: "test.mp3")
      expect(transcriber.user_prompt).to eq("Audio file: test.mp3")
    end

    it "returns data description for other inputs" do
      transcriber = transcriber_class.new(audio: StringIO.new("binary"))
      expect(transcriber.user_prompt).to eq("Audio data")
    end
  end

  describe "#prompt" do
    it "returns nil by default" do
      transcriber = transcriber_class.new(audio: "test.mp3")
      expect(transcriber.prompt).to be_nil
    end

    it "can be overridden in subclasses" do
      custom_class = Class.new(described_class) do
        def self.name
          "CustomTranscriber"
        end

        def prompt
          "Spanish podcast about technology"
        end
      end

      transcriber = custom_class.new(audio: "test.mp3")
      expect(transcriber.prompt).to eq("Spanish podcast about technology")
    end
  end

  describe "#postprocess_text" do
    it "returns text unchanged by default" do
      transcriber = transcriber_class.new(audio: "test.mp3")
      expect(transcriber.postprocess_text("Hello World")).to eq("Hello World")
    end

    it "can be overridden for custom processing" do
      custom_class = Class.new(described_class) do
        def self.name
          "CustomTranscriber"
        end

        def postprocess_text(text)
          text.strip.upcase
        end
      end

      transcriber = custom_class.new(audio: "test.mp3")
      expect(transcriber.postprocess_text("  hello  ")).to eq("HELLO")
    end
  end

  describe "inheritance" do
    let(:parent_transcriber) do
      Class.new(described_class) do
        def self.name
          "ParentTranscriber"
        end

        model "gpt-4o-transcribe"
        language "en"
        output_format :verbose_json
        include_timestamps :word
      end
    end

    let(:child_transcriber) do
      Class.new(parent_transcriber) do
        def self.name
          "ChildTranscriber"
        end
      end
    end

    it "inherits settings from parent" do
      expect(child_transcriber.model).to eq("gpt-4o-transcribe")
      expect(child_transcriber.language).to eq("en")
      expect(child_transcriber.output_format).to eq(:verbose_json)
      expect(child_transcriber.include_timestamps).to eq(:word)
    end

    it "allows child to override parent settings" do
      child_transcriber.language "es"
      expect(child_transcriber.language).to eq("es")
      expect(parent_transcriber.language).to eq("en")
    end
  end

  describe "#agent_cache_key" do
    it "generates unique cache key for different inputs" do
      transcriber1 = transcriber_class.new(audio: "file1.mp3")
      transcriber2 = transcriber_class.new(audio: "file2.mp3")

      expect(transcriber1.agent_cache_key).not_to eq(transcriber2.agent_cache_key)
    end

    it "generates same cache key for same inputs" do
      transcriber1 = transcriber_class.new(audio: "https://example.com/audio.mp3")
      transcriber2 = transcriber_class.new(audio: "https://example.com/audio.mp3")

      expect(transcriber1.agent_cache_key).to eq(transcriber2.agent_cache_key)
    end

    it "includes model in cache key" do
      transcriber_class.model "whisper-1"
      transcriber = transcriber_class.new(audio: "test.mp3")

      expect(transcriber.agent_cache_key).to include("whisper-1")
    end

    it "includes output format in cache key" do
      transcriber_class.output_format :srt
      transcriber = transcriber_class.new(audio: "test.mp3")

      expect(transcriber.agent_cache_key).to include("srt")
    end
  end

  describe "combined configuration" do
    it "allows full configuration" do
      transcriber_class.model "gpt-4o-transcribe"
      transcriber_class.language "es"
      transcriber_class.output_format :vtt
      transcriber_class.include_timestamps :word
      transcriber_class.fallback_models "whisper-1"

      expect(transcriber_class.model).to eq("gpt-4o-transcribe")
      expect(transcriber_class.language).to eq("es")
      expect(transcriber_class.output_format).to eq(:vtt)
      expect(transcriber_class.include_timestamps).to eq(:word)
      expect(transcriber_class.fallback_models).to eq(["whisper-1"])
    end
  end
end
