# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Speaker ElevenLabs model validation" do
  let(:models_json) { File.read(Rails.root.join("../../spec/fixtures/elevenlabs_models.json")) }
  let(:models_url) { "https://api.elevenlabs.io/v1/models" }
  let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }
  let(:fake_audio) { "\xFF\xD8fake_audio_data" }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.elevenlabs_api_key = "xi-test-key"
      c.elevenlabs_api_base = "https://api.elevenlabs.io"
      c.default_tts_provider = :elevenlabs
      c.default_tts_model = "eleven_v3"
      c.default_tts_voice = "Rachel"
      c.track_speech = false
    end

    stub_request(:get, models_url)
      .with(headers: {"xi-api-key" => "xi-test-key"})
      .to_return(status: 200, body: models_json)

    # Stub LiteLLM to prevent real HTTP calls from SpeechPricing
    stub_request(:get, RubyLLM::Agents::Audio::SpeechPricing::LITELLM_PRICING_URL)
      .to_return(status: 200, body: {}.to_json)
  end

  after do
    RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
    RubyLLM::Agents::Audio::SpeechPricing.refresh!
  end

  def tts_url(vid = voice_id)
    "https://api.elevenlabs.io/v1/text-to-speech/#{vid}"
  end

  describe "valid TTS model" do
    let(:speaker_class) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_v3"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end
    end

    it "succeeds normally with a valid TTS model" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      result = speaker_class.call(text: "Hello world")
      expect(result).to be_a(RubyLLM::Agents::SpeechResult)
      expect(result.audio).to eq(fake_audio)
    end
  end

  describe "speech-to-speech model (non-TTS)" do
    let(:sts_speaker_class) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_english_sts_v2"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end
    end

    it "raises ConfigurationError for STS model" do
      expect {
        sts_speaker_class.call(text: "Hello world")
      }.to raise_error(
        RubyLLM::Agents::ConfigurationError,
        /does not support text-to-speech/
      )
    end

    it "includes model name in error message" do
      expect {
        sts_speaker_class.call(text: "Hello world")
      }.to raise_error(
        RubyLLM::Agents::ConfigurationError,
        /eleven_english_sts_v2/
      )
    end
  end

  describe "text exceeding max character limit" do
    let(:speaker_class) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_v3"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end
    end

    it "logs a warning but does not raise" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      long_text = "a" * 6000 # eleven_v3 max is 5000

      expect {
        speaker_class.call(text: long_text)
      }.to output(/exceeds.*5000 characters/).to_stderr
    end

    it "does not warn when text is within limit" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      short_text = "a" * 4000

      expect {
        speaker_class.call(text: short_text)
      }.not_to output(/exceeds/).to_stderr
    end
  end

  describe "style voice setting on unsupported model" do
    let(:styled_speaker) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_v3"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"

        voice_settings do
          stability 0.5
          similarity_boost 0.75
          style 0.5
        end
      end
    end

    it "logs a warning about unsupported style setting" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      expect {
        styled_speaker.call(text: "Hello")
      }.to output(/does not support the 'style' voice setting/).to_stderr
    end
  end

  describe "style voice setting on supported model" do
    let(:styled_v2_speaker) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_multilingual_v2"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"

        voice_settings do
          stability 0.5
          similarity_boost 0.75
          style 0.5
        end
      end
    end

    it "does not warn when model supports style" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      expect {
        styled_v2_speaker.call(text: "Hello")
      }.not_to output(/does not support the 'style'/).to_stderr
    end
  end

  describe "models endpoint unreachable" do
    before do
      RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
      stub_request(:get, models_url).to_timeout
    end

    let(:speaker_class) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_v3"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end
    end

    it "skips validation and proceeds with TTS" do
      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      result = speaker_class.call(text: "Hello")
      expect(result.audio).to eq(fake_audio)
    end
  end

  describe "no API key configured" do
    before do
      RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
      RubyLLM::Agents.configure do |c|
        c.elevenlabs_api_key = nil
      end
    end

    let(:speaker_class) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :elevenlabs
        model "eleven_v3"
        voice "Rachel"
        voice_id "21m00Tcm4TlvDq8ikWAM"
      end
    end

    it "skips validation (ModelRegistry returns empty)" do
      # Re-configure API key for the actual TTS call (but not for models endpoint)
      RubyLLM::Agents.configure { |c| c.elevenlabs_api_key = "xi-test-key" }

      stub_request(:post, tts_url)
        .with(query: hash_including("output_format"))
        .to_return(status: 200, body: fake_audio)

      result = speaker_class.call(text: "Hello")
      expect(result.audio).to eq(fake_audio)
    end
  end

  describe "OpenAI provider is unaffected" do
    let(:openai_speaker) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :openai
        model "tts-1"
        voice "nova"
      end
    end

    before do
      allow(RubyLLM.config).to receive(:openai_api_key).and_return("sk-test")
      allow(RubyLLM.config).to receive(:openai_api_base).and_return(nil)
    end

    it "does not run ElevenLabs validation for OpenAI speakers" do
      stub_request(:post, "https://api.openai.com/v1/audio/speech")
        .to_return(status: 200, body: fake_audio)

      # Should not call ModelRegistry at all
      expect(RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry).not_to receive(:find)

      openai_speaker.call(text: "Hello")
    end
  end
end
