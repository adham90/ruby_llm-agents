# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::OpenRouterAdapter do
  before do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: {}.to_json)
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::OPENROUTER_URL)
      .to_return(status: 200, body: openrouter_data.to_json)
  end

  after do
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  let(:openrouter_data) do
    {
      "data" => [
        {
          "id" => "openai/gpt-4o",
          "pricing" => {
            "prompt" => "0.0000025",
            "completion" => "0.00001"
          }
        },
        {
          "id" => "anthropic/claude-3-5-sonnet-20241022",
          "pricing" => {
            "prompt" => "0.000003",
            "completion" => "0.000015"
          }
        },
        {
          "id" => "openai/gpt-4o-audio-preview",
          "pricing" => {
            "prompt" => "0.0000025",
            "completion" => "0.00001",
            "image" => "0.007225"
          },
          "architecture" => {"modality" => "text+image+audio->text+audio"}
        }
      ]
    }
  end

  describe ".find_model" do
    context "exact ID match" do
      it "finds openai/gpt-4o" do
        result = described_class.find_model("openai/gpt-4o")
        expect(result[:input_cost_per_token]).to eq(0.0000025)
        expect(result[:output_cost_per_token]).to eq(0.00001)
        expect(result[:source]).to eq(:openrouter)
      end
    end

    context "without provider prefix" do
      it "finds gpt-4o without prefix" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to eq(0.0000025)
        expect(result[:source]).to eq(:openrouter)
      end
    end

    context "claude model" do
      it "finds claude-3-5-sonnet" do
        result = described_class.find_model("claude-3-5-sonnet-20241022")
        expect(result[:input_cost_per_token]).to eq(0.000003)
        expect(result[:output_cost_per_token]).to eq(0.000015)
      end
    end

    context "model with image pricing" do
      it "includes image_cost_raw" do
        result = described_class.find_model("openai/gpt-4o-audio-preview")
        expect(result[:image_cost_raw]).to eq(0.007225)
      end
    end

    context "unknown model" do
      it "returns nil" do
        expect(described_class.find_model("totally-fake-model")).to be_nil
      end
    end

    context "when OpenRouter data is unavailable" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::OPENROUTER_URL)
          .to_return(status: 500, body: "error")
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end
  end
end
