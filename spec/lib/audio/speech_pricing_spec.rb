# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::SpeechPricing do
  before do
    RubyLLM::Agents.reset_configuration!
    # Stub all external pricing URLs to prevent real HTTP calls
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: litellm_response.to_json)
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::OPENROUTER_URL)
      .to_return(status: 200, body: {"data" => []}.to_json)
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::HELICONE_URL)
      .to_return(status: 200, body: [].to_json)
    stub_request(:get, /#{Regexp.escape(RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL)}/o)
      .to_return(status: 404, body: {}.to_json)
    stub_request(:get, /llmpricing\.ai/)
      .to_return(status: 404, body: {}.to_json)
    described_class.refresh!
  end

  after do
    described_class.refresh!
    RubyLLM::Agents::Audio::ElevenLabs::ModelRegistry.clear_cache!
  end

  # Default: LiteLLM has no TTS entries
  let(:litellm_response) { {"gpt-4o" => {"input_cost_per_token" => 0.0025}} }

  describe ".calculate_cost" do
    context "when no pricing is found" do
      it "returns zero for unknown models" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "unknown-tts-model", characters: 1000
        )
        expect(cost).to eq(0.0)
      end

      it "returns zero for unknown provider" do
        cost = described_class.calculate_cost(
          provider: :unknown, model_id: "some-model", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
    end

    context "with LiteLLM pricing" do
      let(:litellm_response) do
        {
          "tts/tts-1" => {"input_cost_per_character" => 0.000015, "mode" => "tts"},
          "tts/tts-1-hd" => {"input_cost_per_character" => 0.000030, "mode" => "tts"},
          "elevenlabs/eleven_v3" => {"input_cost_per_character" => 0.000300, "mode" => "tts"},
          "elevenlabs/eleven_flash_v2" => {"input_cost_per_character" => 0.000150, "mode" => "tts"}
        }
      end

      it "prices tts-1 from LiteLLM" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.015)
      end

      it "prices tts-1-hd from LiteLLM" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1-hd", characters: 1000
        )
        expect(cost).to eq(0.030)
      end

      it "prices eleven_v3 from LiteLLM" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.30)
      end

      it "prices eleven_flash_v2 from LiteLLM" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_flash_v2", characters: 1000
        )
        expect(cost).to eq(0.15)
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

    context "when LiteLLM fetch fails" do
      before do
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_return(status: 500, body: "Server Error")
        described_class.refresh!
      end

      it "returns zero when no other source available" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
    end

    context "when LiteLLM URL times out" do
      before do
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_timeout
        described_class.refresh!
      end

      it "returns zero when no other source available" do
        cost = described_class.calculate_cost(
          provider: :openai, model_id: "tts-1", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
    end
  end

  describe "Tier 1: config overrides" do
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

    it "falls through to LiteLLM when model not in config" do
      litellm_data = {"tts/tts-1-hd" => {"input_cost_per_character" => 0.000030}}
      stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
        .to_return(status: 200, body: litellm_data.to_json)
      described_class.refresh!

      cost = described_class.calculate_cost(
        provider: :openai, model_id: "tts-1-hd", characters: 1000
      )
      expect(cost).to eq(0.030)
    end
  end

  describe "config default_tts_cost fallback" do
    it "uses default_tts_cost when configured and no other source found" do
      RubyLLM::Agents.configure { |c| c.default_tts_cost = 0.02 }

      cost = described_class.calculate_cost(
        provider: :openai, model_id: "unknown-model", characters: 1000
      )
      expect(cost).to eq(0.02)
    end

    it "returns zero when default_tts_cost is nil" do
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "unknown-model", characters: 1000
      )
      expect(cost).to eq(0.0)
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

    context "when elevenlabs_base_cost_per_1k is nil (not configured)" do
      before do
        RubyLLM::Agents.configure { |c| c.elevenlabs_base_cost_per_1k = nil }
      end

      it "skips ElevenLabs API tier and returns zero" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
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

      it "returns zero when no other source available" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_v3", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
    end

    context "when model is unknown to the API" do
      it "returns zero for unknown model" do
        cost = described_class.calculate_cost(
          provider: :elevenlabs, model_id: "eleven_future_v99", characters: 1000
        )
        expect(cost).to eq(0.0)
      end
    end

    it "does not affect OpenAI pricing" do
      # OpenAI models are not in ElevenLabs API, and LiteLLM has no TTS data
      cost = described_class.calculate_cost(
        provider: :openai, model_id: "tts-1", characters: 1000
      )
      expect(cost).to eq(0.0)
    end
  end

  describe ".all_pricing" do
    it "returns pricing from all tiers" do
      pricing = described_class.all_pricing

      expect(pricing).to have_key(:litellm)
      expect(pricing).to have_key(:configured)
      expect(pricing).to have_key(:elevenlabs_api)
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

    context "when elevenlabs_base_cost_per_1k is nil" do
      it "returns empty hash for elevenlabs_api" do
        pricing = described_class.all_pricing
        expect(pricing[:elevenlabs_api]).to eq({})
      end
    end
  end
end
