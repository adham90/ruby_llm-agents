# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry do
  let(:models_json) { File.read(Rails.root.join("../../spec/fixtures/elevenlabs_models.json")) }
  let(:models_url) { "https://api.elevenlabs.io/v1/models" }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.elevenlabs_api_key = "xi-test-key"
      c.elevenlabs_api_base = "https://api.elevenlabs.io"
    end

    stub_request(:get, models_url)
      .with(headers: {"xi-api-key" => "xi-test-key"})
      .to_return(status: 200, body: models_json, headers: {"Content-Type" => "application/json"})
  end

  after do
    described_class.clear_cache!
  end

  describe ".models" do
    it "returns parsed array of model hashes" do
      models = described_class.models
      expect(models).to be_an(Array)
      expect(models.length).to eq(10)
    end

    it "includes all expected model IDs" do
      model_ids = described_class.models.map { |m| m["model_id"] }
      expect(model_ids).to include(
        "eleven_v3",
        "eleven_multilingual_v2",
        "eleven_flash_v2_5",
        "eleven_turbo_v2_5",
        "eleven_turbo_v2",
        "eleven_flash_v2",
        "eleven_monolingual_v1",
        "eleven_multilingual_v1",
        "eleven_english_sts_v2",
        "eleven_multilingual_sts_v2"
      )
    end
  end

  describe ".find" do
    it "returns the model hash for eleven_v3" do
      model = described_class.find("eleven_v3")
      expect(model).to be_a(Hash)
      expect(model["model_id"]).to eq("eleven_v3")
      expect(model["name"]).to eq("Eleven v3")
      expect(model["can_do_text_to_speech"]).to be true
      expect(model["maximum_text_length_per_request"]).to eq(5000)
    end

    it "returns nil for nonexistent model" do
      expect(described_class.find("nonexistent")).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.find("")).to be_nil
    end
  end

  describe ".tts_model?" do
    it "returns true for eleven_v3 (TTS model)" do
      expect(described_class.tts_model?("eleven_v3")).to be true
    end

    it "returns true for eleven_multilingual_v2" do
      expect(described_class.tts_model?("eleven_multilingual_v2")).to be true
    end

    it "returns true for eleven_flash_v2_5" do
      expect(described_class.tts_model?("eleven_flash_v2_5")).to be true
    end

    it "returns false for eleven_english_sts_v2 (speech-to-speech only)" do
      expect(described_class.tts_model?("eleven_english_sts_v2")).to be false
    end

    it "returns false for eleven_multilingual_sts_v2 (speech-to-speech only)" do
      expect(described_class.tts_model?("eleven_multilingual_sts_v2")).to be false
    end

    it "returns false for nonexistent model" do
      expect(described_class.tts_model?("nonexistent")).to be false
    end
  end

  describe ".cost_multiplier" do
    it "returns 1.0 for eleven_v3 (standard model)" do
      expect(described_class.cost_multiplier("eleven_v3")).to eq(1.0)
    end

    it "returns 1.0 for eleven_multilingual_v2" do
      expect(described_class.cost_multiplier("eleven_multilingual_v2")).to eq(1.0)
    end

    it "returns 0.5 for eleven_flash_v2_5 (flash model)" do
      expect(described_class.cost_multiplier("eleven_flash_v2_5")).to eq(0.5)
    end

    it "returns 0.5 for eleven_turbo_v2_5" do
      expect(described_class.cost_multiplier("eleven_turbo_v2_5")).to eq(0.5)
    end

    it "returns 0.5 for eleven_turbo_v2" do
      expect(described_class.cost_multiplier("eleven_turbo_v2")).to eq(0.5)
    end

    it "returns 0.5 for eleven_flash_v2" do
      expect(described_class.cost_multiplier("eleven_flash_v2")).to eq(0.5)
    end

    it "returns 1.0 for nonexistent model (safe default)" do
      expect(described_class.cost_multiplier("nonexistent")).to eq(1.0)
    end
  end

  describe ".max_characters" do
    it "returns 5000 for eleven_v3" do
      expect(described_class.max_characters("eleven_v3")).to eq(5000)
    end

    it "returns 40000 for eleven_flash_v2_5" do
      expect(described_class.max_characters("eleven_flash_v2_5")).to eq(40000)
    end

    it "returns 10000 for eleven_multilingual_v2" do
      expect(described_class.max_characters("eleven_multilingual_v2")).to eq(10000)
    end

    it "returns 30000 for eleven_turbo_v2" do
      expect(described_class.max_characters("eleven_turbo_v2")).to eq(30000)
    end

    it "returns nil for nonexistent model" do
      expect(described_class.max_characters("nonexistent")).to be_nil
    end
  end

  describe ".languages" do
    it "returns 32 languages for eleven_v3" do
      langs = described_class.languages("eleven_v3")
      expect(langs).to be_an(Array)
      expect(langs.length).to eq(32)
      expect(langs).to include("en", "ar", "ja")
    end

    it "returns only English for eleven_turbo_v2" do
      langs = described_class.languages("eleven_turbo_v2")
      expect(langs).to eq(["en"])
    end

    it "returns 29 languages for eleven_multilingual_v2" do
      langs = described_class.languages("eleven_multilingual_v2")
      expect(langs.length).to eq(29)
    end

    it "returns 9 languages for eleven_multilingual_v1" do
      langs = described_class.languages("eleven_multilingual_v1")
      expect(langs.length).to eq(9)
      expect(langs).to include("en", "de", "fr", "es")
    end

    it "returns empty array for nonexistent model" do
      expect(described_class.languages("nonexistent")).to eq([])
    end
  end

  describe ".supports_style?" do
    it "returns true for eleven_multilingual_v2" do
      expect(described_class.supports_style?("eleven_multilingual_v2")).to be true
    end

    it "returns true for eleven_english_sts_v2" do
      expect(described_class.supports_style?("eleven_english_sts_v2")).to be true
    end

    it "returns false for eleven_v3" do
      expect(described_class.supports_style?("eleven_v3")).to be false
    end

    it "returns false for eleven_flash_v2_5" do
      expect(described_class.supports_style?("eleven_flash_v2_5")).to be false
    end

    it "returns false for nonexistent model" do
      expect(described_class.supports_style?("nonexistent")).to be false
    end
  end

  describe ".supports_speaker_boost?" do
    it "returns true for eleven_multilingual_v2" do
      expect(described_class.supports_speaker_boost?("eleven_multilingual_v2")).to be true
    end

    it "returns true for eleven_multilingual_sts_v2" do
      expect(described_class.supports_speaker_boost?("eleven_multilingual_sts_v2")).to be true
    end

    it "returns false for eleven_v3" do
      expect(described_class.supports_speaker_boost?("eleven_v3")).to be false
    end

    it "returns false for eleven_flash_v2_5" do
      expect(described_class.supports_speaker_boost?("eleven_flash_v2_5")).to be false
    end
  end

  describe ".voice_conversion_model?" do
    it "returns true for eleven_english_sts_v2" do
      expect(described_class.voice_conversion_model?("eleven_english_sts_v2")).to be true
    end

    it "returns true for eleven_multilingual_sts_v2" do
      expect(described_class.voice_conversion_model?("eleven_multilingual_sts_v2")).to be true
    end

    it "returns false for eleven_v3 (TTS only)" do
      expect(described_class.voice_conversion_model?("eleven_v3")).to be false
    end

    it "returns false for eleven_flash_v2_5" do
      expect(described_class.voice_conversion_model?("eleven_flash_v2_5")).to be false
    end

    it "returns false for nonexistent model" do
      expect(described_class.voice_conversion_model?("nonexistent")).to be false
    end
  end

  describe "caching" do
    it "does not make a second HTTP request on repeated calls" do
      described_class.models
      described_class.models
      described_class.find("eleven_v3")
      described_class.cost_multiplier("eleven_v3")

      expect(WebMock).to have_requested(:get, models_url).once
    end

    it "re-fetches after refresh!" do
      described_class.models
      described_class.refresh!

      expect(WebMock).to have_requested(:get, models_url).twice
    end

    it "re-fetches after cache expires" do
      described_class.models

      # Simulate cache expiry by manipulating fetched_at
      described_class.instance_variable_set(:@fetched_at, Time.now - 25_000)
      described_class.models

      expect(WebMock).to have_requested(:get, models_url).twice
    end

    it "respects custom cache TTL" do
      RubyLLM::Agents.configure { |c| c.elevenlabs_models_cache_ttl = 60 }

      described_class.models
      described_class.instance_variable_set(:@fetched_at, Time.now - 61)
      described_class.models

      expect(WebMock).to have_requested(:get, models_url).twice
    end
  end

  describe "error handling" do
    it "returns empty array on HTTP 500" do
      stub_request(:get, models_url)
        .to_return(status: 500, body: "Internal Server Error")

      described_class.clear_cache!
      expect(described_class.models).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, models_url).to_timeout

      described_class.clear_cache!
      expect(described_class.models).to eq([])
    end

    it "returns empty array when API key is not configured" do
      RubyLLM::Agents.configure { |c| c.elevenlabs_api_key = nil }

      described_class.clear_cache!
      expect(described_class.models).to eq([])
    end

    it "returns empty array on invalid JSON response" do
      stub_request(:get, models_url)
        .to_return(status: 200, body: "not json")

      described_class.clear_cache!
      expect(described_class.models).to eq([])
    end

    it "returns empty array when response is not an array" do
      stub_request(:get, models_url)
        .to_return(status: 200, body: '{"error": "unauthorized"}')

      described_class.clear_cache!
      expect(described_class.models).to eq([])
    end

    it "returns stale cache on HTTP failure after successful fetch" do
      # First fetch succeeds
      described_class.models
      expect(described_class.models.length).to eq(10)

      # Expire cache and stub failure
      described_class.instance_variable_set(:@fetched_at, Time.now - 25_000)
      stub_request(:get, models_url)
        .to_return(status: 500, body: "Server Error")

      # Should return stale cached data
      models = described_class.models
      expect(models.length).to eq(10)
    end
  end

  describe "thread safety" do
    it "handles concurrent access without errors" do
      threads = 5.times.map do
        Thread.new do
          10.times do
            described_class.models
            described_class.find("eleven_v3")
            described_class.cost_multiplier("eleven_flash_v2_5")
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
