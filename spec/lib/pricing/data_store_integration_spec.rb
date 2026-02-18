# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::DataStore, :integration do
  before do
    described_class.refresh!
    WebMock.allow_net_connect!
  end

  after do
    described_class.refresh!
    WebMock.disable_net_connect!
  end

  describe ".litellm_data" do
    it "fetches and returns a large hash" do
      data = described_class.litellm_data
      expect(data).to be_a(Hash)
      expect(data.size).to be > 500
    end

    it "contains whisper-1 with input_cost_per_second" do
      data = described_class.litellm_data
      expect(data["whisper-1"]).to be_a(Hash)
      expect(data["whisper-1"]["input_cost_per_second"]).to be > 0
    end

    it "contains gpt-4o with input_cost_per_token" do
      data = described_class.litellm_data
      expect(data["gpt-4o"]).to be_a(Hash)
      expect(data["gpt-4o"]["input_cost_per_token"]).to be > 0
    end

    it "second fetch is instant (in-memory cache)" do
      described_class.refresh!(:litellm)

      start1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.litellm_data
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start1

      start2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.litellm_data
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start2

      expect(t2).to be < (t1 / 10.0)
    end
  end

  describe ".openrouter_data" do
    it "fetches and returns an array of models" do
      data = described_class.openrouter_data
      expect(data).to be_an(Array)
      expect(data.size).to be > 100
    end

    it "models have pricing with prompt and completion" do
      data = described_class.openrouter_data
      model = data.find { |m| m["id"]&.include?("gpt-4o") }
      expect(model).to be_present
      expect(model.dig("pricing", "prompt")).to be_present
    end
  end

  describe ".helicone_data" do
    it "fetches and returns model cost entries" do
      data = described_class.helicone_data
      expect(data).to be_an(Array)
      expect(data.size).to be > 50
    end

    it "entries have input_cost_per_1m" do
      data = described_class.helicone_data
      openai_entry = data.find { |e| e["provider"]&.upcase == "OPENAI" && e["model"]&.include?("gpt-4o") }
      expect(openai_entry).to be_present
      expect(openai_entry["input_cost_per_1m"]).to be > 0
    end
  end

  describe ".portkey_data" do
    it "returns pricing for openai/gpt-4o" do
      data = described_class.portkey_data("openai", "gpt-4o")
      expect(data).to be_a(Hash)
      expect(data.dig("pay_as_you_go", "request_token", "price")).to be > 0
    end

    it "returns pricing for openai/whisper-1" do
      data = described_class.portkey_data("openai", "whisper-1")
      expect(data).to be_a(Hash)
    end

    it "returns nil-like for nonexistent models" do
      data = described_class.portkey_data("openai", "fake-model-xyz-999")
      expect(data).to satisfy { |d| d.nil? || d.empty? || !d.key?("pay_as_you_go") }
    end
  end

  describe ".llmpricing_data" do
    it "returns pricing for OpenAI/gpt-4o" do
      data = described_class.llmpricing_data("OpenAI", "gpt-4o", 1_000_000, 1_000_000)
      if data
        expect(data).to be_a(Hash)
        expect(data["input_cost"]).to be > 0
        expect(data["output_cost"]).to be > 0
      else
        skip "llmpricing.ai may be unavailable"
      end
    end
  end

  describe ".refresh!" do
    it "forces re-fetch after refresh" do
      data1 = described_class.litellm_data
      described_class.refresh!(:litellm)
      data2 = described_class.litellm_data

      # Should be different objects (not same reference)
      expect(data1).not_to equal(data2)
      # But same content
      expect(data2).to be_a(Hash)
    end
  end

  describe ".cache_stats" do
    it "reports cache state" do
      described_class.litellm_data
      stats = described_class.cache_stats

      expect(stats[:litellm][:cached]).to be true
      expect(stats[:litellm][:size]).to be > 500
    end
  end
end
