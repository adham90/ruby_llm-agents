# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::TranscriptionPricing do
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
    # Prevent ruby_llm adapter from interfering in unit tests
    allow(RubyLLM::Agents::Pricing::RubyLLMAdapter).to receive(:find_model).and_return(nil)
    described_class.refresh!
  end

  after do
    described_class.refresh!
  end

  # Default: LiteLLM has no transcription entries
  let(:litellm_response) { {"gpt-4o" => {"input_cost_per_token" => 0.0025}} }

  describe ".calculate_cost" do
    context "when no pricing is found" do
      it "returns nil" do
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 60)
        expect(cost).to be_nil
      end

      it "returns nil for unknown models" do
        cost = described_class.calculate_cost(model_id: "some-unknown-model", duration_seconds: 120)
        expect(cost).to be_nil
      end
    end

    context "with user config pricing" do
      before do
        RubyLLM::Agents.configure do |c|
          c.transcription_model_pricing = {"whisper-1" => 0.006}
        end
      end

      it "calculates cost based on duration" do
        # 60 seconds = 1 minute at $0.006/min = $0.006
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 60)
        expect(cost).to eq(0.006)
      end

      it "scales linearly with duration" do
        # 300 seconds = 5 minutes at $0.006/min = $0.030
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 300)
        expect(cost).to eq(0.03)
      end

      it "handles zero duration" do
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 0)
        expect(cost).to eq(0.0)
      end

      it "handles fractional minutes" do
        # 90 seconds = 1.5 minutes at $0.006/min = $0.009
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 90)
        expect(cost).to eq(0.009)
      end

      it "returns nil for unconfigured models" do
        cost = described_class.calculate_cost(model_id: "gpt-4o-transcribe", duration_seconds: 60)
        expect(cost).to be_nil
      end
    end
  end

  describe ".cost_per_minute" do
    context "when no pricing is found" do
      it "returns nil" do
        expect(described_class.cost_per_minute("whisper-1")).to be_nil
      end
    end

    context "with user config" do
      before do
        RubyLLM::Agents.configure do |c|
          c.transcription_model_pricing = {
            "whisper-1" => 0.006,
            "gpt-4o-transcribe" => 0.01
          }
        end
      end

      it "returns configured price for whisper-1" do
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end

      it "returns configured price for gpt-4o-transcribe" do
        expect(described_class.cost_per_minute("gpt-4o-transcribe")).to eq(0.01)
      end

      it "returns nil for unconfigured models" do
        expect(described_class.cost_per_minute("unknown-model")).to be_nil
      end
    end
  end

  describe "LiteLLM source" do
    context "when LiteLLM has transcription pricing with input_cost_per_second" do
      let(:litellm_response) do
        {
          "whisper-1" => {
            "mode" => "audio_transcription",
            "input_cost_per_second" => 0.0001
          },
          "gpt-4o-transcribe" => {
            "mode" => "audio_transcription",
            "input_cost_per_second" => 0.000167
          }
        }
      end

      it "converts input_cost_per_second to per-minute for whisper-1" do
        # $0.0001/sec * 60 = $0.006/min
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end

      it "converts input_cost_per_second to per-minute for gpt-4o-transcribe" do
        # $0.000167/sec * 60 = $0.01002/min
        expect(described_class.cost_per_minute("gpt-4o-transcribe")).to eq(0.01002)
      end

      it "calculates total cost correctly" do
        # 120 seconds = 2 minutes at $0.006/min = $0.012
        cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 120)
        expect(cost).to eq(0.012)
      end
    end

    context "when LiteLLM has input_cost_per_audio_token" do
      let(:litellm_response) do
        {
          "gpt-4o-transcribe" => {
            "mode" => "audio_transcription",
            "input_cost_per_audio_token" => 0.000006
          }
        }
      end

      it "converts per-audio-token to per-minute" do
        # $0.000006/token * 1500 tokens/min = $0.009/min
        expect(described_class.cost_per_minute("gpt-4o-transcribe")).to eq(0.009)
      end
    end

    context "when LiteLLM uses prefixed model keys" do
      let(:litellm_response) do
        {
          "audio_transcription/whisper-1" => {
            "mode" => "audio_transcription",
            "input_cost_per_second" => 0.0001
          }
        }
      end

      it "finds model via prefix matching" do
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end
    end

    context "when LiteLLM fetch fails" do
      before do
        described_class.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_return(status: 500, body: "Server Error")
        described_class.refresh!
      end

      it "returns nil (no hardcoded fallback)" do
        expect(described_class.cost_per_minute("whisper-1")).to be_nil
      end

      it "falls through to user config if available" do
        RubyLLM::Agents.configure do |c|
          c.transcription_model_pricing = {"whisper-1" => 0.006}
        end
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end
    end

    context "when LiteLLM URL times out" do
      before do
        described_class.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_timeout
        described_class.refresh!
      end

      it "returns nil (no hardcoded fallback)" do
        expect(described_class.cost_per_minute("whisper-1")).to be_nil
      end

      it "falls through to user config if available" do
        RubyLLM::Agents.configure do |c|
          c.transcription_model_pricing = {"whisper-1" => 0.006}
        end
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end
    end
  end

  describe "User config overrides" do
    before do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {
          "whisper-1" => 0.008,
          "gpt-4o-transcribe" => 0.012,
          "custom-model" => 0.05
        }
      end
    end

    it "uses config price for known models" do
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.008)
    end

    it "uses config price for custom models" do
      expect(described_class.cost_per_minute("custom-model")).to eq(0.05)
    end

    it "supports symbol keys" do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"whisper-1": 0.007}
      end
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.007)
    end

    it "returns nil for models not in config" do
      expect(described_class.cost_per_minute("unknown-model")).to be_nil
    end
  end

  describe "priority: config > LiteLLM" do
    let(:litellm_response) do
      {
        "whisper-1" => {
          "mode" => "audio_transcription",
          "input_cost_per_second" => 0.0001  # $0.006/min
        }
      }
    end

    before do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"whisper-1" => 0.020}
      end
    end

    it "prefers user config over LiteLLM" do
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.020)
    end

    it "falls through to LiteLLM for models not in config" do
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.020)
      # Add a model not in config
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"custom-only" => 0.020}
      end
      # whisper-1 should come from LiteLLM now
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
    end

    it "uses config for models not in LiteLLM" do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {
          "whisper-1" => 0.020,
          "custom-model" => 0.05
        }
      end
      expect(described_class.cost_per_minute("custom-model")).to eq(0.05)
    end
  end

  describe "duration scaling" do
    before do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"whisper-1" => 0.006}
      end
    end

    it "handles zero duration" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 0)
      expect(cost).to eq(0.0)
    end

    it "handles fractional seconds" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 30.5)
      expected = (30.5 / 60.0 * 0.006).round(6)
      expect(cost).to eq(expected)
    end

    it "scales linearly for 1 minute" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 60)
      expect(cost).to eq(0.006)
    end

    it "scales linearly for 10 minutes" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 600)
      expect(cost).to eq(0.06)
    end

    it "scales linearly for 1 hour" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 3600)
      expect(cost).to eq(0.36)
    end
  end

  describe ".refresh!" do
    let(:litellm_response) do
      {"whisper-1" => {"mode" => "audio_transcription", "input_cost_per_second" => 0.0001}}
    end

    it "clears and re-fetches data" do
      # First call loads data
      expect(described_class.cost_per_minute("whisper-1")).to be_present

      # Stub new response with no transcription data
      stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)

      described_class.refresh!

      # After refresh, old data should be gone
      expect(described_class.cost_per_minute("whisper-1")).to be_nil
    end
  end

  describe "multi-source cascade" do
    context "when LiteLLM misses but Portkey has pricing" do
      let(:litellm_response) { {} }

      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/openai/whisper-1")
          .to_return(status: 200, body: {
            "pay_as_you_go" => {
              "request_token" => {"price" => 0},
              "response_token" => {"price" => 0},
              "additional_units" => {
                "request_audio_token" => {"price" => 0.0006}
              }
            }
          }.to_json)
      end

      it "falls through to Portkey" do
        # Portkey: 0.0006 cents/audio_token → $0.000006/audio_token
        # Per minute: $0.000006 * 1500 = $0.009
        price = described_class.cost_per_minute("whisper-1")
        expect(price).to eq(0.009)
      end
    end

    context "when all external sources fail" do
      let(:litellm_response) { {} }

      before do
        described_class.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_return(status: 500, body: "error")
        stub_request(:get, /#{Regexp.escape(RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL)}/o)
          .to_return(status: 500, body: "error")
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::OPENROUTER_URL)
          .to_return(status: 500, body: "error")
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::HELICONE_URL)
          .to_return(status: 500, body: "error")
        stub_request(:get, /llmpricing\.ai/)
          .to_return(status: 500, body: "error")
        described_class.refresh!
      end

      it "returns nil gracefully" do
        expect(described_class.cost_per_minute("whisper-1")).to be_nil
      end

      it "still respects user config" do
        RubyLLM::Agents.configure do |c|
          c.transcription_model_pricing = {"whisper-1" => 0.006}
        end
        expect(described_class.cost_per_minute("whisper-1")).to eq(0.006)
      end
    end
  end
end
