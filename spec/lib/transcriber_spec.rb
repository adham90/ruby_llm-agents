# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Transcriber do
  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_transcription_model).and_return("whisper-1")
    allow(config).to receive(:default_timeout).and_return(120)
    allow(config).to receive(:default_temperature).and_return(0.7)
    allow(config).to receive(:default_streaming).and_return(false)
    allow(config).to receive(:budgets_enabled?).and_return(false)
    allow(config).to receive(:track_audio).and_return(false)
    allow(config).to receive(:track_embeddings).and_return(false)
    allow(config).to receive(:track_conversations).and_return(false)
    allow(config).to receive(:track_images).and_return(false)
    allow(config).to receive(:track_moderations).and_return(false)
  end

  # Mock RubyLLM.transcribe response
  let(:mock_response) do
    double(
      "TranscriptionResponse",
      text: "Hello, this is a test transcription.",
      language: "en",
      duration: 5.5
    )
  end

  describe ".agent_type" do
    it "returns :audio" do
      expect(described_class.agent_type).to eq(:audio)
    end
  end

  describe "DSL" do
    let(:base_transcriber) do
      Class.new(described_class) do
        def self.name
          "TestTranscriber"
        end
      end
    end

    describe ".model" do
      it "sets and returns the model" do
        base_transcriber.model "gpt-4o-transcribe"
        expect(base_transcriber.model).to eq("gpt-4o-transcribe")
      end

      it "returns default when not set" do
        expect(base_transcriber.model).to eq("whisper-1")
      end

      it "inherits from parent class" do
        base_transcriber.model "gpt-4o-transcribe"
        child = Class.new(base_transcriber) do
          def self.name
            "ChildTranscriber"
          end
        end
        expect(child.model).to eq("gpt-4o-transcribe")
      end
    end

    describe ".language" do
      it "sets and returns language" do
        base_transcriber.language "es"
        expect(base_transcriber.language).to eq("es")
      end

      it "returns nil when not set" do
        expect(base_transcriber.language).to be_nil
      end

      it "inherits from parent class" do
        base_transcriber.language "fr"
        child = Class.new(base_transcriber) do
          def self.name
            "ChildTranscriber"
          end
        end
        expect(child.language).to eq("fr")
      end
    end

    describe ".output_format" do
      it "sets and returns output_format" do
        base_transcriber.output_format :srt
        expect(base_transcriber.output_format).to eq(:srt)
      end

      it "returns default when not set" do
        expect(base_transcriber.output_format).to eq(:text)
      end

      it "inherits from parent class" do
        base_transcriber.output_format :vtt
        child = Class.new(base_transcriber) do
          def self.name
            "ChildTranscriber"
          end
        end
        expect(child.output_format).to eq(:vtt)
      end
    end

    describe ".include_timestamps" do
      it "sets and returns include_timestamps" do
        base_transcriber.include_timestamps :word
        expect(base_transcriber.include_timestamps).to eq(:word)
      end

      it "returns default when not set" do
        expect(base_transcriber.include_timestamps).to eq(:segment)
      end

      it "inherits from parent class" do
        base_transcriber.include_timestamps :none
        child = Class.new(base_transcriber) do
          def self.name
            "ChildTranscriber"
          end
        end
        expect(child.include_timestamps).to eq(:none)
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

    describe ".chunking" do
      it "configures chunking via block" do
        base_transcriber.chunking do
          self.enabled = true
          self.max_duration = 300
          self.overlap = 10
          self.parallel = true
        end

        config = base_transcriber.chunking_config
        expect(config.enabled?).to be true
        expect(config.max_duration).to eq(300)
        expect(config.overlap).to eq(10)
        expect(config.parallel).to be true
      end

      it "has sensible defaults" do
        base_transcriber.chunking {}
        config = base_transcriber.chunking_config
        expect(config.enabled?).to be false
        expect(config.max_duration).to eq(600)
        expect(config.overlap).to eq(5)
        expect(config.parallel).to be false
      end

      it "converts to hash" do
        base_transcriber.chunking do
          self.enabled = true
          self.max_duration = 120
        end

        hash = base_transcriber.chunking_config.to_h
        expect(hash[:enabled]).to be true
        expect(hash[:max_duration]).to eq(120)
      end
    end

    describe ".reliability" do
      it "configures reliability via block" do
        base_transcriber.reliability do
          retries max: 5, backoff: :constant
          fallback_models "whisper-1", "gpt-4o-mini-transcribe"
          total_timeout 300
        end

        config = base_transcriber.reliability_config
        expect(config.max_retries).to eq(5)
        expect(config.backoff).to eq(:constant)
        expect(config.fallback_models_list).to eq(["whisper-1", "gpt-4o-mini-transcribe"])
        expect(config.total_timeout_seconds).to eq(300)
      end

      it "has sensible defaults" do
        base_transcriber.reliability {}
        config = base_transcriber.reliability_config
        expect(config.max_retries).to eq(3)
        expect(config.backoff).to eq(:exponential)
        expect(config.fallback_models_list).to be_empty
      end
    end

    describe ".fallback_models" do
      it "sets fallback models directly" do
        base_transcriber.fallback_models "whisper-1", "gpt-4o-mini-transcribe"
        expect(base_transcriber.fallback_models).to eq(["whisper-1", "gpt-4o-mini-transcribe"])
      end

      it "returns empty array when not set" do
        expect(base_transcriber.fallback_models).to eq([])
      end
    end
  end

  describe "#call" do
    let(:test_transcriber) do
      Class.new(described_class) do
        def self.name
          "TestTranscriber"
        end

        model "whisper-1"
      end
    end

    let(:audio_file_path) { "/tmp/test_audio.mp3" }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_file_path).and_return(true)
      allow(mock_response).to receive(:respond_to?).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:text).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:language).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:duration).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:segments).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:words).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:cost).and_return(false)
    end

    context "with file path" do
      it "returns a TranscriptionResult" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: audio_file_path)

        expect(result).to be_a(RubyLLM::Agents::TranscriptionResult)
      end

      it "passes audio to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(audio_file_path, hash_including(model: "whisper-1"))
          .and_return(mock_response)

        test_transcriber.call(audio: audio_file_path)
      end

      it "returns transcribed text" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: audio_file_path)
        expect(result.text).to eq("Hello, this is a test transcription.")
      end

      it "returns audio duration" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: audio_file_path)
        expect(result.audio_duration).to eq(5.5)
      end

      it "returns detected language" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: audio_file_path)
        expect(result.detected_language).to eq("en")
      end
    end

    context "with URL" do
      let(:audio_url) { "https://example.com/audio.mp3" }

      it "handles URL input" do
        expect(RubyLLM).to receive(:transcribe)
          .with(audio_url, anything)
          .and_return(mock_response)

        test_transcriber.call(audio: audio_url)
      end
    end

    context "with language specification" do
      let(:spanish_transcriber) do
        Class.new(described_class) do
          def self.name
            "SpanishTranscriber"
          end

          model "whisper-1"
          language "es"
        end
      end

      it "passes language to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(language: "es"))
          .and_return(mock_response)

        spanish_transcriber.call(audio: audio_file_path)
      end

      it "allows runtime language override" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(language: "fr"))
          .and_return(mock_response)

        test_transcriber.call(audio: audio_file_path, language: "fr")
      end
    end

    context "with custom prompt" do
      let(:prompted_transcriber) do
        Class.new(described_class) do
          def self.name
            "PromptedTranscriber"
          end

          model "whisper-1"

          def prompt
            "Technical discussion about Ruby programming"
          end
        end
      end

      it "passes prompt to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(prompt: "Technical discussion about Ruby programming"))
          .and_return(mock_response)

        prompted_transcriber.call(audio: audio_file_path)
      end
    end

    context "with postprocessing" do
      let(:postprocess_transcriber) do
        Class.new(described_class) do
          def self.name
            "PostprocessTranscriber"
          end

          model "whisper-1"

          def postprocess_text(text)
            text.gsub(/Ruby L L M/i, "RubyLLM")
          end
        end
      end

      it "applies postprocessing to text" do
        response = double(
          "TranscriptionResponse",
          text: "Using Ruby L L M for AI",
          language: "en",
          duration: 3.0
        )
        allow(response).to receive(:respond_to?).and_return(false)
        allow(response).to receive(:respond_to?).with(:text).and_return(true)
        allow(response).to receive(:respond_to?).with(:language).and_return(true)
        allow(response).to receive(:respond_to?).with(:duration).and_return(true)
        allow(response).to receive(:respond_to?).with(:segments).and_return(false)
        allow(response).to receive(:respond_to?).with(:words).and_return(false)
        allow(response).to receive(:respond_to?).with(:cost).and_return(false)

        allow(RubyLLM).to receive(:transcribe).and_return(response)

        result = postprocess_transcriber.call(audio: audio_file_path)
        expect(result.text).to eq("Using RubyLLM for AI")
      end
    end

    context "with output format" do
      let(:srt_transcriber) do
        Class.new(described_class) do
          def self.name
            "SRTTranscriber"
          end

          model "whisper-1"
          output_format :srt
        end
      end

      it "passes response_format to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(response_format: "srt"))
          .and_return(mock_response)

        srt_transcriber.call(audio: audio_file_path)
      end
    end

    context "with timestamps" do
      let(:word_timestamp_transcriber) do
        Class.new(described_class) do
          def self.name
            "WordTimestampTranscriber"
          end

          model "whisper-1"
          include_timestamps :word
        end
      end

      it "passes timestamp_granularities to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(timestamp_granularities: ["word", "segment"]))
          .and_return(mock_response)

        word_timestamp_transcriber.call(audio: audio_file_path)
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(model: "gpt-4o-transcribe"))
          .and_return(mock_response)

        test_transcriber.call(audio: audio_file_path, model: "gpt-4o-transcribe")
      end
    end

    context "timing" do
      it "tracks duration" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: audio_file_path)

        expect(result.duration_ms).to be >= 0
        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
      end
    end

    context "validation" do
      it "raises error for non-existent file" do
        allow(File).to receive(:exist?).with("/nonexistent/audio.mp3").and_return(false)

        expect {
          test_transcriber.call(audio: "/nonexistent/audio.mp3")
        }.to raise_error(ArgumentError, /Audio file not found/)
      end

      it "raises error for invalid input type" do
        expect {
          test_transcriber.call(audio: 123)
        }.to raise_error(ArgumentError, /audio must be a file path/)
      end

      it "raises error for empty binary data" do
        # String that doesn't start with http and doesn't exist as a file
        allow(File).to receive(:exist?).with("").and_return(false)

        expect {
          test_transcriber.call(audio: "")
        }.to raise_error(ArgumentError, /Binary audio data cannot be empty/)
      end
    end
  end

  describe "cost calculation" do
    let(:test_transcriber) do
      Class.new(described_class) do
        def self.name
          "CostTranscriber"
        end

        model "whisper-1"
      end
    end

    let(:audio_file_path) { "/tmp/test_audio.mp3" }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_file_path).and_return(true)
      allow(mock_response).to receive(:respond_to?).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:text).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:language).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:duration).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:segments).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:words).and_return(false)
      allow(mock_response).to receive(:respond_to?).with(:cost).and_return(false)
    end

    it "calculates cost based on duration for whisper-1" do
      # 5.5 seconds = 0.0917 minutes at $0.006/min = ~$0.00055
      allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

      result = test_transcriber.call(audio: audio_file_path)

      expect(result.total_cost).to be > 0
      expect(result.audio_minutes).to be_within(0.01).of(5.5 / 60.0)
    end

    it "uses response cost if available" do
      response_with_cost = double(
        "TranscriptionResponse",
        text: "Test",
        language: "en",
        duration: 60.0,
        cost: 0.05
      )
      allow(response_with_cost).to receive(:respond_to?).and_return(false)
      allow(response_with_cost).to receive(:respond_to?).with(:text).and_return(true)
      allow(response_with_cost).to receive(:respond_to?).with(:language).and_return(true)
      allow(response_with_cost).to receive(:respond_to?).with(:duration).and_return(true)
      allow(response_with_cost).to receive(:respond_to?).with(:segments).and_return(false)
      allow(response_with_cost).to receive(:respond_to?).with(:words).and_return(false)
      allow(response_with_cost).to receive(:respond_to?).with(:cost).and_return(true)

      allow(RubyLLM).to receive(:transcribe).and_return(response_with_cost)

      result = test_transcriber.call(audio: audio_file_path)

      expect(result.total_cost).to eq(0.05)
    end
  end

  describe "#agent_cache_key" do
    let(:test_transcriber) do
      Class.new(described_class) do
        def self.name
          "CacheKeyTranscriber"
        end

        model "whisper-1"
        version "1.0"
      end
    end

    let(:audio_file_path) { "/tmp/test_audio.mp3" }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_file_path).and_return(true)
      allow(Digest::SHA256).to receive(:file).and_return(double(hexdigest: "abc123"))
    end

    it "generates unique cache key" do
      transcriber = test_transcriber.new(audio: audio_file_path)
      key = transcriber.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/transcription/CacheKeyTranscriber/1.0/")
    end

    it "includes model in cache key" do
      transcriber = test_transcriber.new(audio: audio_file_path)
      key = transcriber.agent_cache_key

      expect(key).to include("whisper-1")
    end

    it "generates different keys for different audio" do
      allow(Digest::SHA256).to receive(:file)
        .with("/tmp/audio1.mp3").and_return(double(hexdigest: "hash1"))
      allow(Digest::SHA256).to receive(:file)
        .with("/tmp/audio2.mp3").and_return(double(hexdigest: "hash2"))
      allow(File).to receive(:exist?).with("/tmp/audio1.mp3").and_return(true)
      allow(File).to receive(:exist?).with("/tmp/audio2.mp3").and_return(true)

      transcriber1 = test_transcriber.new(audio: "/tmp/audio1.mp3")
      transcriber2 = test_transcriber.new(audio: "/tmp/audio2.mp3")

      expect(transcriber1.agent_cache_key).not_to eq(transcriber2.agent_cache_key)
    end

    it "handles URL cache keys" do
      transcriber = test_transcriber.new(audio: "https://example.com/audio.mp3")
      key = transcriber.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/transcription/")
    end
  end

  describe "ChunkingConfig" do
    let(:config) { RubyLLM::Agents::Transcriber::ChunkingConfig.new }

    it "has default values" do
      expect(config.enabled?).to be false
      expect(config.max_duration).to eq(600)
      expect(config.overlap).to eq(5)
      expect(config.parallel).to be false
    end

    it "allows setting values" do
      config.enabled = true
      config.max_duration = 120
      config.overlap = 10
      config.parallel = true

      expect(config.enabled?).to be true
      expect(config.max_duration).to eq(120)
      expect(config.overlap).to eq(10)
      expect(config.parallel).to be true
    end

    it "converts to hash" do
      config.enabled = true
      config.max_duration = 300

      hash = config.to_h
      expect(hash[:enabled]).to be true
      expect(hash[:max_duration]).to eq(300)
      expect(hash[:overlap]).to eq(5)
      expect(hash[:parallel]).to be false
    end
  end

  describe "ReliabilityConfig" do
    let(:config) { RubyLLM::Agents::Transcriber::ReliabilityConfig.new }

    it "has default values" do
      expect(config.max_retries).to eq(3)
      expect(config.backoff).to eq(:exponential)
      expect(config.fallback_models_list).to be_empty
      expect(config.total_timeout_seconds).to be_nil
    end

    it "configures retries" do
      config.retries(max: 5, backoff: :constant)

      expect(config.max_retries).to eq(5)
      expect(config.backoff).to eq(:constant)
    end

    it "configures fallback models" do
      config.fallback_models("whisper-1", "gpt-4o-mini-transcribe")

      expect(config.fallback_models_list).to eq(["whisper-1", "gpt-4o-mini-transcribe"])
    end

    it "configures total timeout" do
      config.total_timeout(300)

      expect(config.total_timeout_seconds).to eq(300)
    end

    it "converts to hash" do
      config.retries(max: 5)
      config.fallback_models("whisper-1")
      config.total_timeout(120)

      hash = config.to_h
      expect(hash[:max_retries]).to eq(5)
      expect(hash[:backoff]).to eq(:exponential)
      expect(hash[:fallback_models]).to eq(["whisper-1"])
      expect(hash[:total_timeout]).to eq(120)
    end
  end
end
