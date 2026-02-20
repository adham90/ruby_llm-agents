# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker do
  let(:fake_audio_data) { "fake_audio_binary_data" }
  let(:openai_tts_url) { "https://api.openai.com/v1/audio/speech" }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_tts_provider = :openai
      c.default_tts_model = "tts-1"
      c.default_tts_voice = "nova"
      c.track_speech = false
      c.track_executions = false
      c.track_audio = false
      c.track_embeddings = false
      c.track_image_generation = false
      c.elevenlabs_api_key = "xi-test"
      c.elevenlabs_api_base = "https://api.elevenlabs.io"
    end

    # Stub OpenAI API key
    allow(RubyLLM.config).to receive(:openai_api_key).and_return("sk-test-key")
    allow(RubyLLM.config).to receive(:openai_api_base).and_return(nil)

    # Default HTTP stub for OpenAI TTS
    stub_request(:post, openai_tts_url)
      .to_return(status: 200, body: fake_audio_data,
        headers: {"Content-Type" => "audio/mpeg"})

    # Stub LiteLLM pricing to prevent real HTTP calls
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: "{}",
        headers: {"Content-Type" => "application/json"})
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
        base_speaker.provider :elevenlabs
        child = Class.new(base_speaker) do
          def self.name
            "ChildSpeaker"
          end
        end
        expect(child.provider).to eq(:elevenlabs)
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
        expect(lexicon.pronunciations).to eq({"API" => "A P I", "SQL" => "sequel"})
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

    context "with valid text" do
      it "returns a SpeechResult" do
        result = test_speaker.call(text: "Hello world")
        expect(result).to be_a(RubyLLM::Agents::SpeechResult)
      end

      it "sends correct request to OpenAI TTS API" do
        test_speaker.call(text: "Hello world")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with { |req|
            body = JSON.parse(req.body)
            body["model"] == "tts-1" &&
              body["input"] == "Hello world" &&
              body["voice"] == "nova"
          }
      end

      it "returns audio data from API response" do
        result = test_speaker.call(text: "Hello")
        expect(result.audio).to eq(fake_audio_data)
      end

      it "returns correct format" do
        result = test_speaker.call(text: "Hello")
        expect(result.format).to eq(:mp3)
      end

      it "returns provider info" do
        result = test_speaker.call(text: "Hello")
        expect(result.provider).to eq(:openai)
        expect(result.model_id).to eq("tts-1")
        expect(result.voice_name).to eq("nova")
      end

      it "tracks character count" do
        result = test_speaker.call(text: "Hello world")
        expect(result.characters).to eq(11)
      end

      it "tracks file size" do
        result = test_speaker.call(text: "Hello")
        expect(result.file_size).to eq(fake_audio_data.bytesize)
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

      it "applies lexicon before sending to API" do
        speaker_with_lexicon.call(text: "The API is great")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with { |req| JSON.parse(req.body)["input"] == "The A P I is great" }
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

      it "passes speed to API" do
        fast_speaker.call(text: "Hello")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with { |req| (JSON.parse(req.body)["speed"] - 1.5).abs < 0.001 }
      end
    end

    context "with ElevenLabs provider" do
      let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }
      let(:elevenlabs_url) {
        "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"
      }

      let(:elevenlabs_speaker) do
        Class.new(described_class) do
          def self.name
            "ElevenSpeaker"
          end

          provider :elevenlabs
          model "eleven_multilingual_v2"
          voice_id "21m00Tcm4TlvDq8ikWAM"
          voice_settings do
            stability 0.6
            similarity_boost 0.8
          end
        end
      end

      before do
        stub_request(:post, elevenlabs_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio_data)
      end

      it "calls ElevenLabs API with voice_id in URL" do
        elevenlabs_speaker.call(text: "Hello from ElevenLabs")

        expect(WebMock).to have_requested(:post, elevenlabs_url)
          .with(query: hash_including("output_format"))
      end

      it "sends voice_settings in request body" do
        elevenlabs_speaker.call(text: "Hello")

        expect(WebMock).to have_requested(:post, elevenlabs_url)
          .with(query: hash_including("output_format")) { |req|
            body = JSON.parse(req.body)
            (body.dig("voice_settings", "stability") - 0.6).abs < 0.001 &&
              (body.dig("voice_settings", "similarity_boost") - 0.8).abs < 0.001
          }
      end

      it "returns SpeechResult with elevenlabs provider" do
        result = elevenlabs_speaker.call(text: "Hello")
        expect(result.provider).to eq(:elevenlabs)
        expect(result.model_id).to eq("eleven_multilingual_v2")
      end
    end

    context "with Eleven v3 model" do
      let(:voice_id) { "pNInz6obpgDQGcFmaJgB" }
      let(:v3_url) {
        "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"
      }

      let(:v3_speaker) do
        Class.new(described_class) do
          def self.name
            "V3Speaker"
          end

          provider :elevenlabs
          model "eleven_v3"
          voice_id "pNInz6obpgDQGcFmaJgB"
        end
      end

      before do
        stub_request(:post, v3_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio_data)
      end

      it "works with eleven_v3 model" do
        result = v3_speaker.call(text: "Hello from v3")
        expect(result.model_id).to eq("eleven_v3")
        expect(result.audio).to eq(fake_audio_data)
      end
    end

    context "with unsupported provider" do
      it "raises UnsupportedProviderError" do
        google_speaker = Class.new(described_class) do
          def self.name
            "GoogleSpeaker"
          end

          provider :google
          model "some-model"
        end

        expect {
          google_speaker.call(text: "Hello")
        }.to raise_error(RubyLLM::Agents::UnsupportedProviderError, /google/)
      end
    end

    context "API error handling" do
      it "raises SpeechApiError on 400" do
        stub_request(:post, openai_tts_url)
          .to_return(status: 400, body: '{"error":{"message":"Bad request"}}')

        expect {
          test_speaker.call(text: "Hello")
        }.to raise_error(RubyLLM::Agents::SpeechApiError, /400/)
      end
    end

    context "timing" do
      it "tracks duration" do
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

    it "calls OpenAI TTS API" do
      stub_request(:post, openai_tts_url)
        .to_return(status: 200, body: fake_audio_data)

      chunks = []
      test_speaker.stream(text: "Hello") { |c| chunks << c }

      expect(WebMock).to have_requested(:post, openai_tts_url)
    end

    context "ElevenLabs streaming" do
      let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }
      let(:elevenlabs_stream_url) {
        "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}/stream"
      }

      let(:stream_speaker) do
        Class.new(described_class) do
          def self.name
            "ElevenStreamSpeaker"
          end

          provider :elevenlabs
          model "eleven_flash_v2_5"
          voice_id "21m00Tcm4TlvDq8ikWAM"
        end
      end

      it "uses the /stream endpoint" do
        stub_request(:post, elevenlabs_stream_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio_data)

        chunks = []
        stream_speaker.stream(text: "Hello") { |c| chunks << c }

        expect(WebMock).to have_requested(:post, elevenlabs_stream_url)
          .with(query: hash_including("output_format"))
      end
    end
  end

  describe "cost calculation" do
    before do
      # Provide TTS pricing via user config (since LiteLLM is stubbed empty)
      RubyLLM::Agents.configure do |c|
        c.tts_model_pricing = {
          "tts-1" => 0.015,
          "tts-1-hd" => 0.030,
          "eleven_v3" => 0.30,
          "eleven_flash_v2_5" => 0.15
        }
      end
    end

    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "CostSpeaker"
        end

        provider :openai
        model "tts-1"
      end
    end

    it "calculates cost based on characters for OpenAI" do
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

      text = "a" * 1000
      result = hd_speaker.call(text: text)
      expect(result.total_cost).to eq(0.030)
    end

    it "uses ElevenLabs rate" do
      voice_id = "21m00Tcm4TlvDq8ikWAM"
      stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio_data)

      el_speaker = Class.new(described_class) do
        def self.name
          "ELCostSpeaker"
        end

        provider :elevenlabs
        model "eleven_v3"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end

      text = "a" * 1000
      result = el_speaker.call(text: text)
      expect(result.total_cost).to eq(0.30)
    end

    it "uses flash model rate for ElevenLabs" do
      voice_id = "21m00Tcm4TlvDq8ikWAM"
      stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio_data)

      flash_speaker = Class.new(described_class) do
        def self.name
          "FlashCostSpeaker"
        end

        provider :elevenlabs
        model "eleven_flash_v2_5"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end

      text = "a" * 1000
      result = flash_speaker.call(text: text)
      expect(result.total_cost).to eq(0.15)
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
      end
    end

    it "generates unique cache key" do
      speaker = test_speaker.new(text: "Hello world")
      key = speaker.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/speech/CacheKeySpeaker/")
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

  describe "execution metadata tracking" do
    let(:test_speaker) do
      Class.new(described_class) do
        def self.name
          "MetaSpeaker"
        end

        provider :openai
        model "tts-1"
        voice "nova"
      end
    end

    it "stores audio metadata on context for instrumentation" do
      # Capture the context after execution by intercepting Pipeline::Executor
      captured_context = nil
      allow(RubyLLM::Agents::Pipeline::Executor).to receive(:execute).and_wrap_original do |m, ctx|
        result = m.call(ctx)
        captured_context = result
        result
      end

      test_speaker.call(text: "Hello world")

      expect(captured_context[:provider]).to eq("openai")
      expect(captured_context[:voice_id]).to eq("nova")
      expect(captured_context[:characters]).to eq(11)
      expect(captured_context[:output_format]).to eq("mp3")
      expect(captured_context[:file_size]).to eq(fake_audio_data.bytesize)
    end

    context "with ElevenLabs provider" do
      let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }

      let(:el_speaker) do
        Class.new(described_class) do
          def self.name
            "MetaElevenSpeaker"
          end

          provider :elevenlabs
          model "eleven_v3"
          voice "Rachel"
          voice_id "21m00Tcm4TlvDq8ikWAM"
        end
      end

      before do
        stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio_data)
      end

      it "stores provider and voice_id on context" do
        captured_context = nil
        allow(RubyLLM::Agents::Pipeline::Executor).to receive(:execute).and_wrap_original do |m, ctx|
          result = m.call(ctx)
          captured_context = result
          result
        end

        el_speaker.call(text: "Test")

        expect(captured_context[:provider]).to eq("elevenlabs")
        expect(captured_context[:voice_id]).to eq("21m00Tcm4TlvDq8ikWAM")
        expect(captured_context[:characters]).to eq(4)
        expect(captured_context[:output_format]).to eq("mp3")
        expect(captured_context[:file_size]).to be_a(Integer)
      end
    end

    context "with tracking enabled" do
      before do
        RubyLLM::Agents.configure do |c|
          c.track_audio = true
          c.async_logging = false
          c.persist_prompts = true
        end
      end

      it "persists audio metadata in execution record" do
        test_speaker.call(text: "Tracked speech")

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.metadata["provider"]).to eq("openai")
        expect(execution.metadata["voice_id"]).to eq("nova")
        expect(execution.metadata["characters"]).to eq(14)
        expect(execution.metadata["output_format"]).to eq("mp3")
        expect(execution.metadata["file_size"]).to eq(fake_audio_data.bytesize)
      end
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

      expect(lexicon.to_h).to eq({"API" => "A P I"})
    end
  end
end
