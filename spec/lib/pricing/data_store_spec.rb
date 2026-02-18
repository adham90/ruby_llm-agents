# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::DataStore do
  before do
    described_class.refresh!
  end

  after do
    described_class.refresh!
  end

  describe ".litellm_data" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: litellm_body.to_json)
    end

    let(:litellm_body) do
      {
        "whisper-1" => {
          "mode" => "audio_transcription",
          "input_cost_per_second" => 0.0001
        },
        "gpt-4o" => {
          "input_cost_per_token" => 0.0000025,
          "output_cost_per_token" => 0.00001
        }
      }
    end

    it "returns parsed JSON hash" do
      data = described_class.litellm_data
      expect(data).to be_a(Hash)
      expect(data).to have_key("whisper-1")
      expect(data).to have_key("gpt-4o")
    end

    it "caches in-memory on second call" do
      first = described_class.litellm_data
      second = described_class.litellm_data
      expect(first).to equal(second) # same object reference
    end

    it "returns nil on HTTP failure" do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 500, body: "error")
      described_class.refresh!(:litellm)

      expect(described_class.litellm_data).to be_nil
    end

    it "returns nil on timeout" do
      stub_request(:get, described_class::LITELLM_URL)
        .to_timeout
      described_class.refresh!(:litellm)

      expect(described_class.litellm_data).to be_nil
    end
  end

  describe ".openrouter_data" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)
      stub_request(:get, described_class::OPENROUTER_URL)
        .to_return(status: 200, body: openrouter_body.to_json)
    end

    let(:openrouter_body) do
      {
        "data" => [
          {"id" => "openai/gpt-4o", "pricing" => {"prompt" => "0.0000025", "completion" => "0.00001"}}
        ]
      }
    end

    it "returns array of models from data key" do
      data = described_class.openrouter_data
      expect(data).to be_an(Array)
      expect(data.first["id"]).to eq("openai/gpt-4o")
    end
  end

  describe ".helicone_data" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)
      stub_request(:get, described_class::HELICONE_URL)
        .to_return(status: 200, body: helicone_body.to_json)
    end

    let(:helicone_body) do
      [
        {"model" => "gpt-4o", "provider" => "OPENAI", "input_cost_per_1m" => 2.5, "output_cost_per_1m" => 10.0}
      ]
    end

    it "returns array of cost entries" do
      data = described_class.helicone_data
      expect(data).to be_an(Array)
      expect(data.first["model"]).to eq("gpt-4o")
    end
  end

  describe ".portkey_data" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)
      stub_request(:get, "#{described_class::PORTKEY_BASE_URL}/openai/gpt-4o")
        .to_return(status: 200, body: portkey_body.to_json)
    end

    let(:portkey_body) do
      {"pay_as_you_go" => {"request_token" => {"price" => 0.00025}, "response_token" => {"price" => 0.001}}}
    end

    it "returns pricing for a specific provider/model" do
      data = described_class.portkey_data("openai", "gpt-4o")
      expect(data).to be_a(Hash)
      expect(data.dig("pay_as_you_go", "request_token", "price")).to eq(0.00025)
    end

    it "caches per-model results" do
      first = described_class.portkey_data("openai", "gpt-4o")
      second = described_class.portkey_data("openai", "gpt-4o")
      expect(first).to equal(second)
    end
  end

  describe ".llmpricing_data" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)
      stub_request(:get, /llmpricing\.ai/)
        .to_return(status: 200, body: llmpricing_body.to_json)
    end

    let(:llmpricing_body) do
      {"input_cost" => 2.5, "output_cost" => 10.0}
    end

    it "returns pricing data" do
      data = described_class.llmpricing_data("OpenAI", "gpt-4o", 1_000_000, 1_000_000)
      expect(data).to be_a(Hash)
      expect(data["input_cost"]).to eq(2.5)
    end
  end

  describe ".refresh!" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {"gpt-4o" => {}}.to_json)
    end

    it "clears all caches when called with :all" do
      described_class.litellm_data # populate
      described_class.refresh!(:all)

      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)

      data = described_class.litellm_data
      expect(data).to eq({})
    end

    it "clears only specified source" do
      described_class.litellm_data # populate
      described_class.refresh!(:litellm)

      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {"new" => {}}.to_json)

      data = described_class.litellm_data
      expect(data).to have_key("new")
    end
  end

  describe ".cache_stats" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {"gpt-4o" => {}}.to_json)
    end

    it "returns stats for all sources" do
      described_class.litellm_data
      stats = described_class.cache_stats

      expect(stats).to have_key(:litellm)
      expect(stats).to have_key(:openrouter)
      expect(stats).to have_key(:helicone)
      expect(stats).to have_key(:portkey)
      expect(stats).to have_key(:llmpricing)
      expect(stats[:litellm][:cached]).to be true
      expect(stats[:litellm][:size]).to eq(1)
    end
  end

  describe "source_enabled? respects config" do
    before do
      stub_request(:get, described_class::LITELLM_URL)
        .to_return(status: 200, body: {}.to_json)
      stub_request(:get, described_class::OPENROUTER_URL)
        .to_return(status: 200, body: {"data" => [{"id" => "test"}]}.to_json)
    end

    it "returns nil when source is disabled" do
      RubyLLM::Agents.configure { |c| c.openrouter_pricing_enabled = false }
      expect(described_class.openrouter_data).to be_nil
      RubyLLM::Agents.configure { |c| c.openrouter_pricing_enabled = true }
    end
  end
end
