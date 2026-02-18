# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::SpeechClient do
  let(:fake_audio) { "\xFF\xD8fake_mp3_binary_data" }

  # ============================================================
  # Provider validation
  # ============================================================

  describe "#initialize" do
    it "accepts :openai provider" do
      expect { described_class.new(provider: :openai) }.not_to raise_error
    end

    it "accepts :elevenlabs provider" do
      expect { described_class.new(provider: :elevenlabs) }.not_to raise_error
    end

    it "rejects unsupported providers" do
      expect { described_class.new(provider: :google) }
        .to raise_error(RubyLLM::Agents::UnsupportedProviderError, /google/)
    end

    it "rejects :polly provider" do
      expect { described_class.new(provider: :polly) }
        .to raise_error(RubyLLM::Agents::UnsupportedProviderError, /polly/)
    end
  end

  # ============================================================
  # OpenAI TTS
  # ============================================================

  describe "OpenAI provider" do
    subject(:client) { described_class.new(provider: :openai) }
    let(:openai_tts_url) { "https://api.openai.com/v1/audio/speech" }

    before do
      allow(RubyLLM.config).to receive(:openai_api_key).and_return("sk-test-key")
      allow(RubyLLM.config).to receive(:openai_api_base).and_return(nil)
    end

    describe "#speak" do
      before do
        stub_request(:post, openai_tts_url)
          .to_return(status: 200, body: fake_audio,
            headers: {"Content-Type" => "audio/mpeg"})
      end

      it "returns a Response with audio data" do
        response = client.speak("Hello", model: "tts-1", voice: "nova")
        expect(response.audio).to eq(fake_audio)
        expect(response.format).to eq(:mp3)
        expect(response.model).to eq("tts-1")
      end

      it "sends correct JSON body to OpenAI" do
        client.speak("Hello world", model: "tts-1-hd", voice: "alloy",
          speed: 1.5, response_format: "wav")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with(body: {
            model: "tts-1-hd",
            input: "Hello world",
            voice: "alloy",
            response_format: "wav",
            speed: 1.5
          }.to_json)
      end

      it "omits speed when 1.0" do
        client.speak("Hello", model: "tts-1", voice: "nova", speed: 1.0)

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with { |req| !JSON.parse(req.body).key?("speed") }
      end

      it "sends Authorization header" do
        client.speak("Hello", model: "tts-1", voice: "nova")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with(headers: {"Authorization" => "Bearer sk-test-key"})
      end

      it "raises SpeechApiError on HTTP 400" do
        stub_request(:post, openai_tts_url)
          .to_return(status: 400, body: '{"error":{"message":"Invalid model"}}')

        expect {
          client.speak("Hello", model: "bad", voice: "nova")
        }.to raise_error(RubyLLM::Agents::SpeechApiError, /400/)
      end

      it "raises SpeechApiError on HTTP 500" do
        stub_request(:post, openai_tts_url)
          .to_return(status: 500, body: '{"error":{"message":"Internal error"}}')

        expect {
          client.speak("Hello", model: "tts-1", voice: "nova")
        }.to raise_error(RubyLLM::Agents::SpeechApiError, /500/)
      end

      it "raises ConfigurationError when API key is missing" do
        allow(RubyLLM.config).to receive(:openai_api_key).and_return(nil)

        expect {
          client.speak("Hello", model: "tts-1", voice: "nova")
        }.to raise_error(RubyLLM::Agents::ConfigurationError, /OpenAI API key/)
      end

      it "uses custom openai_api_base" do
        allow(RubyLLM.config).to receive(:openai_api_base)
          .and_return("https://my-proxy.example.com")

        custom_url = "https://my-proxy.example.com/v1/audio/speech"
        stub_request(:post, custom_url)
          .to_return(status: 200, body: fake_audio)

        fresh_client = described_class.new(provider: :openai)
        response = fresh_client.speak("Hello", model: "tts-1", voice: "nova")
        expect(response.audio).to eq(fake_audio)
      end

      it "uses voice_id when provided" do
        client.speak("Hello", model: "tts-1", voice: "nova", voice_id: "custom-id")

        expect(WebMock).to have_requested(:post, openai_tts_url)
          .with { |req| JSON.parse(req.body)["voice"] == "custom-id" }
      end
    end

    describe "#speak_streaming" do
      it "sends request to OpenAI TTS endpoint" do
        stub_request(:post, openai_tts_url)
          .to_return(status: 200, body: fake_audio)

        chunks = []
        client.speak_streaming(
          "Hello", model: "tts-1", voice: "nova"
        ) { |chunk| chunks << chunk }

        expect(WebMock).to have_requested(:post, openai_tts_url)
      end
    end
  end

  # ============================================================
  # ElevenLabs TTS
  # ============================================================

  describe "ElevenLabs provider" do
    subject(:client) { described_class.new(provider: :elevenlabs) }
    let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }
    let(:elevenlabs_tts_url) {
      "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"
    }
    let(:elevenlabs_stream_url) {
      "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}/stream"
    }

    before do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.elevenlabs_api_key = "xi-test-key"
        c.elevenlabs_api_base = "https://api.elevenlabs.io"
        c.default_tts_provider = :elevenlabs
        c.default_tts_model = "eleven_multilingual_v2"
        c.default_tts_voice = "Rachel"
      end
    end

    describe "#speak" do
      before do
        stub_request(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format" => "mp3_44100_128"))
          .to_return(status: 200, body: fake_audio,
            headers: {"Content-Type" => "application/octet-stream"})
      end

      it "returns a Response with audio data" do
        response = client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id)
        expect(response.audio).to eq(fake_audio)
      end

      it "sends voice_id in URL path" do
        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format"))
      end

      it "sends xi-api-key header" do
        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format"),
            headers: {"xi-api-key" => "xi-test-key"})
      end

      it "sends model_id and text in JSON body" do
        client.speak("Hello world", model: "eleven_v3",
          voice: voice_id, voice_id: voice_id)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format")) { |req|
            body = JSON.parse(req.body)
            body["text"] == "Hello world" && body["model_id"] == "eleven_v3"
          }
      end

      it "includes voice_settings in request body" do
        vs = {stability: 0.6, similarity_boost: 0.8,
              style: 0.3, use_speaker_boost: false}

        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id,
          voice_settings: vs)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format")) { |req|
            body = JSON.parse(req.body)
            (body["voice_settings"]["stability"] - 0.6).abs < 0.001
          }
      end

      it "includes speed in voice_settings" do
        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id,
          speed: 1.3)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format")) { |req|
            body = JSON.parse(req.body)
            (body.dig("voice_settings", "speed") - 1.3).abs < 0.001
          }
      end

      it "maps output format to ElevenLabs format string" do
        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id,
          response_format: "mp3")

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format" => "mp3_44100_128"))
      end

      it "maps pcm format" do
        stub_request(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format" => "pcm_24000"))
          .to_return(status: 200, body: fake_audio)

        client.speak("Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id,
          response_format: "pcm")

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format" => "pcm_24000"))
      end

      it "works with Eleven v3 model" do
        response = client.speak("Hello", model: "eleven_v3",
          voice: voice_id, voice_id: voice_id)
        expect(response.audio).to eq(fake_audio)
        expect(response.model).to eq("eleven_v3")
      end

      it "works with deprecated v1 models" do
        response = client.speak("Hello", model: "eleven_monolingual_v1",
          voice: voice_id, voice_id: voice_id)
        expect(response.model).to eq("eleven_monolingual_v1")
      end

      it "works with flash v2.5 model" do
        response = client.speak("Hello", model: "eleven_flash_v2_5",
          voice: voice_id, voice_id: voice_id)
        expect(response.model).to eq("eleven_flash_v2_5")
      end

      it "works with turbo v2 model" do
        response = client.speak("Hello", model: "eleven_turbo_v2",
          voice: voice_id, voice_id: voice_id)
        expect(response.model).to eq("eleven_turbo_v2")
      end

      it "raises ConfigurationError when API key is missing" do
        RubyLLM::Agents.configure { |c| c.elevenlabs_api_key = nil }

        expect {
          client.speak("Hello", model: "eleven_v3",
            voice: voice_id, voice_id: voice_id)
        }.to raise_error(RubyLLM::Agents::ConfigurationError, /ElevenLabs API key/)
      end

      it "raises SpeechApiError on HTTP 422" do
        stub_request(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 422, body: '{"detail":"Validation error"}')

        expect {
          client.speak("Hello", model: "eleven_v3",
            voice: voice_id, voice_id: voice_id)
        }.to raise_error(RubyLLM::Agents::SpeechApiError, /422/)
      end

      it "falls back to voice name when no voice_id" do
        client.speak("Hello", model: "eleven_v3", voice: voice_id)

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format"))
      end
    end

    describe "#speak_streaming" do
      it "uses the /stream endpoint" do
        stub_request(:post, elevenlabs_stream_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio)

        chunks = []
        client.speak_streaming(
          "Hello", model: "eleven_multilingual_v2",
          voice: voice_id, voice_id: voice_id
        ) { |chunk| chunks << chunk }

        expect(WebMock).to have_requested(:post, elevenlabs_stream_url)
          .with(query: hash_including("output_format"))
      end
    end

    describe "output format mapping" do
      # Stub all requests to allow any output_format param
      before do
        stub_request(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format"))
          .to_return(status: 200, body: fake_audio)
      end

      {
        "mp3" => "mp3_44100_128",
        "wav" => "wav_44100",
        "pcm" => "pcm_24000",
        "opus" => "opus_48000_128",
        "alaw" => "alaw_8000",
        "ulaw" => "ulaw_8000",
        "ogg" => "mp3_44100_128",
        "flac" => "mp3_44100_128",
        "aac" => "mp3_44100_128"
      }.each do |simple, native|
        it "maps simple symbol :#{simple} to #{native}" do
          client.speak("Hello", model: "eleven_v3",
            voice: voice_id, voice_id: voice_id,
            response_format: simple)

          expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
            .with(query: hash_including("output_format" => native))
        end
      end

      %w[
        mp3_44100_192 mp3_22050_32 mp3_44100_64
        pcm_16000 pcm_8000 pcm_48000
        wav_22050 wav_44100 wav_48000
        opus_48000_64 opus_48000_32
        alaw_8000 ulaw_8000
      ].each do |native_format|
        it "passes through native format string #{native_format}" do
          client.speak("Hello", model: "eleven_v3",
            voice: voice_id, voice_id: voice_id,
            response_format: native_format)

          expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
            .with(query: hash_including("output_format" => native_format))
        end
      end

      it "falls back to mp3_44100_128 for unknown format" do
        client.speak("Hello", model: "eleven_v3",
          voice: voice_id, voice_id: voice_id,
          response_format: "wma")

        expect(WebMock).to have_requested(:post, elevenlabs_tts_url)
          .with(query: hash_including("output_format" => "mp3_44100_128"))
      end

      it "includes all expected native formats in ELEVENLABS_NATIVE_FORMATS" do
        native_formats = described_class::ELEVENLABS_NATIVE_FORMATS
        expect(native_formats).to include("mp3_44100_128", "mp3_44100_192")
        expect(native_formats).to include("pcm_16000", "pcm_24000", "pcm_44100")
        expect(native_formats).to include("wav_44100", "wav_48000")
        expect(native_formats).to include("opus_48000_64", "opus_48000_128")
        expect(native_formats).to include("alaw_8000", "ulaw_8000")
        expect(native_formats.size).to eq(28)
      end
    end
  end
end
