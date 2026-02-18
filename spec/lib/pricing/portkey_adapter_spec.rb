# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::PortkeyAdapter do
  before do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: {}.to_json)
  end

  after do
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  describe ".find_model" do
    context "text LLM model" do
      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/openai/gpt-4o")
          .to_return(status: 200, body: portkey_gpt4o.to_json)
      end

      let(:portkey_gpt4o) do
        {
          "pay_as_you_go" => {
            "request_token" => {"price" => 0.00025},
            "response_token" => {"price" => 0.001}
          }
        }
      end

      it "returns normalized pricing with cents-to-USD conversion" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to eq(0.0000025)
        expect(result[:output_cost_per_token]).to eq(0.00001)
        expect(result[:source]).to eq(:portkey)
      end
    end

    context "transcription model with audio tokens" do
      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/openai/whisper-1")
          .to_return(status: 200, body: portkey_whisper.to_json)
      end

      let(:portkey_whisper) do
        {
          "pay_as_you_go" => {
            "request_token" => {"price" => 0},
            "response_token" => {"price" => 0},
            "additional_units" => {
              "request_audio_token" => {"price" => 0.0006}
            }
          }
        }
      end

      it "returns audio token pricing" do
        result = described_class.find_model("whisper-1")
        expect(result[:input_cost_per_audio_token]).to be_within(1e-12).of(0.000006)
        expect(result[:source]).to eq(:portkey)
      end
    end

    context "prefixed model IDs" do
      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/groq/llama-3")
          .to_return(status: 200, body: portkey_groq.to_json)
      end

      let(:portkey_groq) do
        {
          "pay_as_you_go" => {
            "request_token" => {"price" => 0.00005},
            "response_token" => {"price" => 0.0001}
          }
        }
      end

      it "resolves groq/llama-3 correctly" do
        result = described_class.find_model("groq/llama-3")
        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:portkey)
      end
    end

    context "provider resolution" do
      it "maps claude models to anthropic" do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/anthropic/claude-3-5-sonnet-20241022")
          .to_return(status: 200, body: {"pay_as_you_go" => {"request_token" => {"price" => 0.0003}}}.to_json)

        result = described_class.find_model("claude-3-5-sonnet-20241022")
        expect(result[:input_cost_per_token]).to be_within(1e-12).of(0.000003)
      end

      it "returns nil for unmapped providers" do
        expect(described_class.find_model("some-random-unknown-model")).to be_nil
      end
    end

    context "when API returns non-pricing response" do
      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/openai/gpt-4o")
          .to_return(status: 200, body: {"error" => "not found"}.to_json)
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end

    context "when API returns error" do
      before do
        stub_request(:get, "#{RubyLLM::Agents::Pricing::DataStore::PORTKEY_BASE_URL}/openai/gpt-4o")
          .to_return(status: 404, body: "Not Found")
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end
  end
end
