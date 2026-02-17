# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::SpeechPricing do
  before do
    RubyLLM::Agents.reset_configuration!
    # Stub LiteLLM URL to prevent real HTTP calls
    stub_request(:get, described_class::LITELLM_PRICING_URL)
      .to_return(status: 200, body: litellm_response.to_json)
  end

  # Simulate LiteLLM having no TTS entries (current reality)
  let(:litellm_response) { {"gpt-4o" => {"input_cost_per_token" => 0.0025}} }

  after do
    described_class.refresh!
    RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
  end

  describe ".calculate_cost" do
    context "OpenAI models (hardcoded fallback)" do
      it "prices tts-1 at $0.015 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.015)
      end

      it "prices tts-1-hd at $0.030 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1-hd", characters: 1000
        )
        expect(cost).to eq(0.030)
      end

      it "scales linearly with character count" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 5000
        )
        expect(cost).to eq(0.075)
      end

      it "handles zero characters" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 0
        )
        expect(cost).to eq(0.0)
      end
    end

    context "ElevenLabs models (hardcoded fallback)" do
      it "prices eleven_v3 at $0.30 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.30)
      end

      it "prices eleven_multilingual_v2 at $0.30 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_multilingual_v2", characters: 1000
        )
        expect(cost).to eq(0.30)
      end

      it "prices flash models at $0.15 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_flash_v2_5", characters: 1000
        )
        expect(cost).to eq(0.15)
      end

      it "prices turbo models at $0.15 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_turbo_v2", characters: 1000
        )
        expect(cost).to eq(0.15)
      end

      it "prices deprecated v1 models at $0.30 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_monolingual_v1", characters: 1000
        )
        expect(cost).to eq(0.30)
      end

      it "prices eleven_flash_v2 at $0.15 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_flash_v2", characters: 1000
        )
        expect(cost).to eq(0.15)
      end

      it "prices eleven_turbo_v2_5 at $0.15 per 1K characters" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_turbo_v2_5", characters: 1000
        )
        expect(cost).to eq(0.15)
      end

      it "defaults unknown ElevenLabs models to $0.30" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_future_v4", characters: 1000
        )
        expect(cost).to eq(0.30)
      end
    end

    context "unknown provider" do
      it "uses default_tts_cost from config" do
        cost = described_class.calculate_cost(
          provider: :unknown, model_id: "some-model", characters: 1000
        )
        expect(cost).to eq(0.015) # default
      end
    end
  end

  describe "Tier 2: config overrides" do
    before do
      RubyLLM::Agents.configure do |c|
        c.tts_model_pricing = {
          "tts-1" => 0.020,
          "eleven_v3" => 0.24,
          "custom-model" => 0.10
        }
      end
    end

    it "uses config price when available" do
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "tts-1", characters: 1000
      )
      expect(cost).to eq(0.020)
    end

    it "uses config price for ElevenLabs override" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
      )
      expect(cost).to eq(0.24)
    end

    it "uses config price for unknown models" do
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "custom-model", characters: 1000
      )
      expect(cost).to eq(0.10)
    end

    it "falls back to hardcoded when model not in config" do
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "tts-1-hd", characters: 1000
      )
      expect(cost).to eq(0.030)
    end
  end

  describe "Tier 1: LiteLLM (future-proof)" do
    context "when LiteLLM has TTS pricing" do
      let(:litellm_response) do
        {
          "tts-1" => {"input_cost_per_character" => 0.000015},
          "eleven_v3" => {"input_cost_per_character" => 0.000300}
        }
      end

      it "uses LiteLLM price for tts-1" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.015)
      end

      it "uses LiteLLM price for eleven_v3" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.30)
      end
    end

    context "when LiteLLM fetch fails" do
      before do
        stub_request(:get, described_class::LITELLM_PRICING_URL)
          .to_return(status: 500, body: "Server Error")
      end

      it "falls through to hardcoded fallback" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.015)
      end
    end

    context "when LiteLLM URL times out" do
      before do
        stub_request(:get, described_class::LITELLM_PRICING_URL)
          .to_timeout
      end

      it "falls through to hardcoded fallback" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.015)
      end
    end
  end

  describe "Tier 3: ElevenLabs API (dynamic multiplier × base rate)" do
    let(:models_json) { File.read(Rails.root.join("../../spec/fixtures/elevenlabs_models.json")) }
    let(:models_url) { "https://api.elevenlabs.io/v1/models" }

    before do
      RubyLLM::Agents.configure do |c|
        c.elevenlabs_api_key = "xi-test-key"
        c.elevenlabs_base_cost_per_1k = 0.30
      end

      stub_request(:get, models_url)
        .with(headers: {"xi-api-key" => "xi-test-key"})
        .to_return(status: 200, body: models_json, headers: {"Content-Type" => "application/json"})
    end

    it "returns 0.30 for eleven_v3 (multiplier 1.0 × base 0.30)" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
      )
      expect(cost).to eq(0.30)
    end

    it "returns 0.15 for eleven_flash_v2_5 (multiplier 0.5 × base 0.30)" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_flash_v2_5", characters: 1000
      )
      expect(cost).to eq(0.15)
    end

    it "returns 0.15 for eleven_turbo_v2_5 (multiplier 0.5 × base 0.30)" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_turbo_v2_5", characters: 1000
      )
      expect(cost).to eq(0.15)
    end

    it "scales cost with custom elevenlabs_base_cost_per_1k" do
      RubyLLM::Agents.configure { |c| c.elevenlabs_base_cost_per_1k = 0.24 }

      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
      )
      expect(cost).to eq(0.24)
    end

    it "applies multiplier with custom base rate for flash models" do
      RubyLLM::Agents.configure { |c| c.elevenlabs_base_cost_per_1k = 0.24 }

      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_flash_v2_5", characters: 1000
      )
      expect(cost).to eq(0.12)
    end

    it "calculates multi-thousand character cost correctly" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_v3", characters: 5000
      )
      expect(cost).to eq(1.50)
    end

    it "calculates flash model multi-thousand character cost correctly" do
      cost = described_class.calculate_cost(
        provider: :elevenlabs, model_id: "eleven_flash_v2_5", characters: 10000
      )
      expect(cost).to eq(1.50)
    end

    context "priority: user config overrides API tier" do
      before do
        RubyLLM::Agents.configure do |c|
          c.tts_model_pricing = {"eleven_v3" => 0.50}
        end
      end

      it "uses config price instead of API tier" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.50)
      end
    end

    context "when ElevenLabs API is unreachable" do
      before do
        RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
        stub_request(:get, models_url).to_timeout
      end

      it "falls through to hardcoded fallback" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.30)
      end
    end

    context "when model is unknown to the API" do
      it "falls through to hardcoded fallback for unknown model" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_future_v99", characters: 1000
        )
        expect(cost).to eq(0.30) # hardcoded default for unknown ElevenLabs
      end
    end

    it "does not affect OpenAI pricing" do
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "tts-1", characters: 1000
      )
      expect(cost).to eq(0.015)
    end
  end

  describe ".all_pricing" do
    it "returns pricing from all tiers" do
      pricing = described_class.all_pricing

      expect(pricing).to have_key(:litellm)
      expect(pricing).to have_key(:configured)
      expect(pricing).to have_key(:elevenlabs_api)
      expect(pricing).to have_key(:fallbacks)
      expect(pricing[:fallbacks]).to include("tts-1" => 0.015)
      expect(pricing[:fallbacks]).to include("eleven_v3" => 0.30)
    end

    context "with ElevenLabs API configured" do
      let(:models_json) { File.read(Rails.root.join("../../spec/fixtures/elevenlabs_models.json")) }

      before do
        RubyLLM::Agents.configure do |c|
          c.elevenlabs_api_key = "xi-test-key"
          c.elevenlabs_base_cost_per_1k = 0.30
        end

        stub_request(:get, "https://api.elevenlabs.io/v1/models")
          .to_return(status: 200, body: models_json)
      end

      it "includes ElevenLabs API pricing for all models" do
        pricing = described_class.all_pricing
        api_pricing = pricing[:elevenlabs_api]

        expect(api_pricing["eleven_v3"]).to eq(0.30)
        expect(api_pricing["eleven_flash_v2_5"]).to eq(0.15)
        expect(api_pricing["eleven_turbo_v2"]).to eq(0.15)
      end
    end
  end

  describe "fallback pricing table" do
    it "includes all supported models" do
      table = described_class.send(:fallback_pricing_table)

      # OpenAI
      expect(table).to include("tts-1", "tts-1-hd")
      # ElevenLabs v1
      expect(table).to include("eleven_monolingual_v1", "eleven_multilingual_v1")
      # ElevenLabs v2
      expect(table).to include("eleven_multilingual_v2", "eleven_turbo_v2", "eleven_flash_v2")
      # ElevenLabs v2.5
      expect(table).to include("eleven_turbo_v2_5", "eleven_flash_v2_5")
      # ElevenLabs v3
      expect(table).to include("eleven_v3")
    end
  end
end
