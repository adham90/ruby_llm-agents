# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::HeliconeAdapter do
  before do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: {}.to_json)
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::HELICONE_URL)
      .to_return(status: 200, body: helicone_data.to_json)
  end

  after do
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  let(:helicone_data) do
    [
      {
        "model" => "gpt-4o",
        "provider" => "OPENAI",
        "input_cost_per_1m" => 2.5,
        "output_cost_per_1m" => 10.0
      },
      {
        "model" => "gpt-4o-realtime-preview",
        "provider" => "OPENAI",
        "input_cost_per_1m" => 5.0,
        "output_cost_per_1m" => 20.0,
        "prompt_audio_per_1m" => 100.0,
        "completion_audio_per_1m" => 200.0
      },
      {
        "model" => "claude-3-5-sonnet-20241022",
        "provider" => "ANTHROPIC",
        "input_cost_per_1m" => 3.0,
        "output_cost_per_1m" => 15.0
      }
    ]
  end

  describe ".find_model" do
    context "text LLM model" do
      it "converts per-1M pricing to per-token" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to eq(2.5 / 1_000_000.0)
        expect(result[:output_cost_per_token]).to eq(10.0 / 1_000_000.0)
        expect(result[:source]).to eq(:helicone)
      end
    end

    context "model with audio pricing" do
      it "includes audio token pricing" do
        result = described_class.find_model("gpt-4o-realtime-preview")
        expect(result[:input_cost_per_audio_token]).to eq(100.0 / 1_000_000.0)
        expect(result[:output_cost_per_audio_token]).to eq(200.0 / 1_000_000.0)
      end
    end

    context "claude model" do
      it "finds and normalizes pricing" do
        result = described_class.find_model("claude-3-5-sonnet-20241022")
        expect(result[:input_cost_per_token]).to eq(3.0 / 1_000_000.0)
        expect(result[:source]).to eq(:helicone)
      end
    end

    context "unknown model" do
      it "returns nil" do
        expect(described_class.find_model("whisper-1")).to be_nil
      end
    end

    context "when Helicone data is unavailable" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::HELICONE_URL)
          .to_return(status: 500, body: "error")
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end
  end
end
