# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker do
  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_tts_provider).and_return(:openai)
    allow(config).to receive(:default_tts_model).and_return("tts-1")
    allow(config).to receive(:default_tts_voice).and_return("nova")
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

  # Mock RubyLLM.speak response
  let(:mock_response) do
    double(
      "SpeechResponse",
      audio: "fake_audio_data",
      duration: 1.5,
      cost: nil
    )
  end

  describe ".agent_type" do
    it "returns :audio" do
      expect(described_class.agent_type).to eq(:audio)
    end
  end

  describe "DSL" do
    let(:base_speaker) do
      Class.new(described_class) do
        def self.name
          "TestSpeaker"
        end
      end
    end

    describe ".provider" do
      it "sets and returns the provider" do
        base_speaker.provider :elevenlabs
        expect(base_speaker.provider).to eq(:elevenlabs)
      end

      it "returns default when not set" do
        expect(base_speaker.provider).to eq(:openai)
      end

      it "inherits from parent class" do
        base_speaker.provider :google
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.provider).to eq(:google)
      end
    end

    describe ".model" do
      it "sets and returns the model" do
        base_speaker.model "tts-1-hd"
        expect(base_speaker.model).to eq("tts-1-hd")
      end

      it "returns default when not set" do
        expect(base_speaker.model).to eq("tts-1")
      end

      it "inherits from parent class" do
        base_speaker.model "tts-1-hd"
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.model).to eq("tts-1-hd")
      end
    end

    describe ".voice" do
      it "sets and returns the voice" do
        base_speaker.voice "alloy"
        expect(base_speaker.voice).to eq("alloy")
      end

      it "returns default when not set" do
        expect(base_speaker.voice).to eq("nova")
      end

      it "inherits from parent class" do
        base_speaker.voice "echo"
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.voice).to eq("echo")
      end
    end

    describe ".voice_id" do
      it "sets and returns the voice_id" do
        base_speaker.voice_id "custom_voice_123"
        expect(base_speaker.voice_id).to eq("custom_voice_123")
      end

      it "returns nil when not set" do
        expect(base_speaker.voice_id).to be_nil
      end
    end

    describe ".speed" do
      it "sets and returns the speed" do
        base_speaker.speed 1.5
        expect(base_speaker.speed).to eq(1.5)
      end

      it "returns default when not set" do
        expect(base_speaker.speed).to eq(1.0)
      end

      it "inherits from parent class" do
        base_speaker.speed 0.75
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.speed).to eq(0.75)
      end
    end

    describe ".output_format" do
      it "sets and returns the output_format" do
        base_speaker.output_format :wav
        expect(base_speaker.output_format).to eq(:wav)
      end

      it "returns default when not set" do
        expect(base_speaker.output_format).to eq(:mp3)
      end

      it "inherits from parent class" do
        base_speaker.output_format :ogg
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.output_format).to eq(:ogg)
      end
    end

    describe ".streaming" do
      it "sets streaming mode" do
        base_speaker.streaming true
        expect(base_speaker.streaming?).to be true
      end

      it "returns false by default" do
        expect(base_speaker.streaming?).to be false
      end
    end

    describe ".voice_settings" do
      it "configures voice settings via block" do
        base_speaker.voice_settings do
          stability 0.6
          similarity_boost 0.8
          style 0.5
          speaker_boost false
        end

        settings = base_speaker.voice_settings_config
        expect(settings.stability_value).to eq(0.6)
        expect(settings.similarity_boost_value).to eq(0.8)
        expect(settings.style_value).to eq(0.5)
        expect(settings.speaker_boost_value).to be false
      end

      it "converts to hash" do
        base_speaker.voice_settings do
          stability 0.7
          similarity_boost 0.9
        end

        hash = base_speaker.voice_settings_config.to_h
        expect(hash[:stability]).to eq(0.7)
        expect(hash[:similarity_boost]).to eq(0.9)
      end
    end

    describe ".lexicon" do
      it "configures pronunciations via block" do
        base_speaker.lexicon do
          pronounce "API", "A P I"
          pronounce "SQL", "sequel"
        end

        lexicon = base_speaker.lexicon_config
        expect(lexicon.pronunciations).to eq({ "API" => "A P I", "SQL" => "sequel" })
      end

      it "applies pronunciations to text" do
        base_speaker.lexicon do
          pronounce "API", "A P I"
        end

        lexicon = base_speaker.lexicon_config
        result = lexicon.apply("The API is great")
        expect(result).to eq("The A P I is great")
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
  end

  describe "#call" do
    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "TestSpeaker"
        end

        provider :openai
        model "tts-1"
        voice "nova"
      end
    end

    before do
      allow(mock_response).to receive(:respond_to?).with(:duration).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:cost).and_return(false)
    end

    context "with valid text" do
      it "returns a SpeechResult" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")

        expect(result).to be_a(RubyLLM::Agents::SpeechResult)
      end

      it "passes text to RubyLLM.speak" do
        expect(RubyLLM).to receive(:speak)
          .with("Hello world", hash_including(model: "tts-1", voice: "nova"))
          .and_return(mock_response)

        test_speaker.call(text: "Hello world")
      end

      it "returns audio data" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello")
        expect(result.audio).to eq("fake_audio_data")
      end

      it "returns correct format" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello")
        expect(result.format).to eq(:mp3)
      end

      it "returns provider info" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello")
        expect(result.provider).to eq(:openai)
        expect(result.model_id).to eq("tts-1")
        expect(result.voice_name).to eq("nova")
      end

      it "tracks character count" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")
        expect(result.characters).to eq(11)
      end
    end

    context "with lexicon" do
      let(:speaker_with_lexicon) do
        Class.new(described_class) do
          def self.name
            "LexiconSpeaker"
          end

          provider :openai
          model "tts-1"

          lexicon do
            pronounce "API", "A P I"
          end
        end
      end

      it "applies lexicon before synthesis" do
        expect(RubyLLM).to receive(:speak)
          .with("The A P I is great", anything)
          .and_return(mock_response)

        speaker_with_lexicon.call(text: "The API is great")
      end
    end

    context "with custom speed" do
      let(:fast_speaker) do
        Class.new(described_class) do
          def self.name
            "FastSpeaker"
          end

          provider :openai
          model "tts-1"
          speed 1.5
        end
      end

      it "passes speed to RubyLLM.speak" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(speed: 1.5))
          .and_return(mock_response)

        fast_speaker.call(text: "Hello")
      end

      it "allows runtime speed override" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(speed: 0.5))
          .and_return(mock_response)

        test_speaker.call(text: "Hello", speed: 0.5)
      end
    end

    context "with voice_id override" do
      let(:custom_voice_speaker) do
        Class.new(described_class) do
          def self.name
            "CustomVoiceSpeaker"
          end

          provider :elevenlabs
          model "eleven_multilingual_v2"
          voice_id "custom_voice_abc123"
        end
      end

      it "uses voice_id when set" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(voice: "custom_voice_abc123"))
          .and_return(mock_response)

        custom_voice_speaker.call(text: "Hello")
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(model: "tts-1-hd"))
          .and_return(mock_response)

        test_speaker.call(text: "Hello", model: "tts-1-hd")
      end
    end

    context "timing" do
      it "tracks duration" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello")

        expect(result.duration_ms).to be >= 0
        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
      end
    end

    context "validation" do
      it "raises error when text is nil" do
        expect {
          test_speaker.call(text: nil)
        }.to raise_error(ArgumentError, /text is required/)
      end

      it "raises error when text is empty" do
        expect {
          test_speaker.call(text: "")
        }.to raise_error(ArgumentError, /text cannot be empty/)
      end

      it "raises error for non-string text" do
        expect {
          test_speaker.call(text: 123)
        }.to raise_error(ArgumentError, /text must be a String/)
      end
    end
  end

  describe "#stream" do
    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "StreamSpeaker"
        end

        provider :openai
        model "tts-1"
      end
    end

    it "raises error without block" do
      expect {
        test_speaker.stream(text: "Hello")
      }.to raise_error(ArgumentError, /A block is required for streaming/)
    end

    it "calls RubyLLM.speak with stream option" do
      chunk = double("chunk", audio: "chunk_data")
      allow(chunk).to receive(:respond_to?).with(:audio).and_return(true)

      expect(RubyLLM).to receive(:speak)
        .with(anything, hash_including(stream: true))
        .and_yield(chunk)

      chunks = []
      test_speaker.stream(text: "Hello") { |c| chunks << c }

      expect(chunks).to include(chunk)
    end
  end

  describe "cost calculation" do
    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "CostSpeaker"
        end

        provider :openai
        model "tts-1"
      end
    end

    before do
      allow(mock_response).to receive(:respond_to?).with(:duration).and_return(true)
      allow(mock_response).to receive(:respond_to?).with(:cost).and_return(false)
    end

    it "calculates cost based on characters for OpenAI" do
      allow(RubyLLM).to receive(:speak).and_return(mock_response)

      # 1000 characters at $0.015/1k = $0.015
      text = "a" * 1000
      result = test_speaker.call(text: text)

      expect(result.total_cost).to eq(0.015)
    end

    it "uses higher rate for HD model" do
      hd_speaker = Class.new(described_class) do
        def self.name
          "HDSpeaker"
        end

        provider :openai
        model "tts-1-hd"
      end

      allow(RubyLLM).to receive(:speak).and_return(mock_response)

      # 1000 characters at $0.030/1k = $0.030
      text = "a" * 1000
      result = hd_speaker.call(text: text)

      expect(result.total_cost).to eq(0.030)
    end

    it "uses response cost if available" do
      response_with_cost = double(
        "SpeechResponse",
        audio: "fake_audio_data",
        duration: 1.5,
        cost: 0.05
      )
      allow(response_with_cost).to receive(:respond_to?).with(:duration).and_return(true)
      allow(response_with_cost).to receive(:respond_to?).with(:cost).and_return(true)
      allow(RubyLLM).to receive(:speak).and_return(response_with_cost)

      result = test_speaker.call(text: "Hello")

      expect(result.total_cost).to eq(0.05)
    end
  end

  describe "#agent_cache_key" do
    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "CacheKeySpeaker"
        end

        provider :openai
        model "tts-1"
        voice "nova"
        version "1.0"
      end
    end

    it "generates unique cache key" do
      speaker = test_speaker.new(text: "Hello world")
      key = speaker.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/speech/CacheKeySpeaker/1.0/")
    end

    it "generates different keys for different texts" do
      speaker1 = test_speaker.new(text: "Hello")
      speaker2 = test_speaker.new(text: "World")

      expect(speaker1.agent_cache_key).not_to eq(speaker2.agent_cache_key)
    end

    it "generates same key for same text" do
      speaker1 = test_speaker.new(text: "Hello")
      speaker2 = test_speaker.new(text: "Hello")

      expect(speaker1.agent_cache_key).to eq(speaker2.agent_cache_key)
    end

    it "includes provider and voice in cache key" do
      speaker = test_speaker.new(text: "Hello")
      key = speaker.agent_cache_key

      expect(key).to include("openai")
      expect(key).to include("tts-1")
      expect(key).to include("nova")
    end
  end

  describe "VoiceSettings" do
    let(:settings) { RubyLLM::Agents::Speaker::VoiceSettings.new }

    it "has default values" do
      expect(settings.stability_value).to eq(0.5)
      expect(settings.similarity_boost_value).to eq(0.75)
      expect(settings.style_value).to eq(0.0)
      expect(settings.speaker_boost_value).to be true
    end

    it "allows setting values" do
      settings.stability(0.8)
      settings.similarity_boost(0.9)
      settings.style(0.3)
      settings.speaker_boost(false)

      expect(settings.stability_value).to eq(0.8)
      expect(settings.similarity_boost_value).to eq(0.9)
      expect(settings.style_value).to eq(0.3)
      expect(settings.speaker_boost_value).to be false
    end

    it "converts to hash" do
      settings.stability(0.6)
      settings.similarity_boost(0.7)

      hash = settings.to_h
      expect(hash).to eq({
        stability: 0.6,
        similarity_boost: 0.7,
        style: 0.0,
        use_speaker_boost: true
      })
    end
  end

  describe "Lexicon" do
    let(:lexicon) { RubyLLM::Agents::Speaker::Lexicon.new }

    it "starts with empty pronunciations" do
      expect(lexicon.pronunciations).to be_empty
    end

    it "adds pronunciations" do
      lexicon.pronounce("API", "A P I")
      lexicon.pronounce("SQL", "sequel")

      expect(lexicon.pronunciations).to eq({
        "API" => "A P I",
        "SQL" => "sequel"
      })
    end

    it "applies pronunciations to text" do
      lexicon.pronounce("API", "A P I")

      result = lexicon.apply("The API is used by the API client")
      expect(result).to eq("The A P I is used by the A P I client")
    end

    it "applies case-insensitive replacement" do
      lexicon.pronounce("api", "A P I")

      result = lexicon.apply("The API and api are the same")
      expect(result).to eq("The A P I and A P I are the same")
    end

    it "only replaces whole words" do
      lexicon.pronounce("SQL", "sequel")

      result = lexicon.apply("SQL and SQLite are different")
      expect(result).to eq("sequel and SQLite are different")
    end

    it "converts to hash" do
      lexicon.pronounce("API", "A P I")

      expect(lexicon.to_h).to eq({ "API" => "A P I" })
    end
  end
end
