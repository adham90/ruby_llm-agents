# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::LLMPricingAdapter do
  before do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: {}.to_json)
    # Default: return 404 for any llmpricing request
    stub_request(:get, /llmpricing\.ai/)
      .to_return(status: 404, body: {}.to_json)
  end

  after do
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  describe ".find_model" do
    context "OpenAI model" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        # Stub all llmpricing URLs to return pricing data
        stub_request(:get, /llmpricing\.ai/)
          .to_return(status: 200, body: {"input_cost" => 2.5, "output_cost" => 10.0}.to_json)
      end

      it "converts calculated costs to per-token rates" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to be_within(1e-12).of(2.5 / 1_000_000.0)
        expect(result[:output_cost_per_token]).to be_within(1e-12).of(10.0 / 1_000_000.0)
        expect(result[:source]).to eq(:llmpricing)
      end
    end

    context "Anthropic model" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, /llmpricing\.ai\/api\/prices\?.*provider=Anthropic/)
          .to_return(status: 200, body: {"input_cost" => 3.0, "output_cost" => 15.0}.to_json)
      end

      it "resolves provider correctly" do
        result = described_class.find_model("claude-3-5-sonnet-20241022")
        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:llmpricing)
      end
    end

    context "Mistral model" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, /llmpricing\.ai\/api\/prices\?.*provider=Mistral/)
          .to_return(status: 200, body: {"input_cost" => 2.0, "output_cost" => 6.0}.to_json)
      end

      it "resolves provider correctly" do
        result = described_class.find_model("mistral-large-latest")
        expect(result[:input_cost_per_token]).to be > 0
      end
    end

    context "unknown provider" do
      it "returns nil for models with no provider mapping" do
        expect(described_class.find_model("some-random-model")).to be_nil
      end
    end

    context "transcription model (not supported)" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, /llmpricing\.ai\/api\/prices\?.*model=whisper-1/)
          .to_return(status: 200, body: {}.to_json)
      end

      it "returns nil because llmpricing.ai doesn't have transcription" do
        expect(described_class.find_model("whisper-1")).to be_nil
      end
    end

    context "when API fails" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, /llmpricing\.ai/)
          .to_return(status: 500, body: "error")
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end
  end
end
