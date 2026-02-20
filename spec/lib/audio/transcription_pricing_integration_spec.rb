# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Audio::TranscriptionPricing, :integration do
  before do
    WebMock.allow_net_connect!
    RubyLLM::Agents.reset_configuration!
    described_class.refresh!
  end

  after do
    described_class.refresh!
    WebMock.disable_net_connect!
  end

  describe ".cost_per_minute" do
    it "finds pricing for whisper-1" do
      price = described_class.cost_per_minute("whisper-1")
      expect(price).to be > 0
      expect(price).to be < 1 # sanity: less than $1/min
    end

    it "finds pricing for gpt-4o-transcribe" do
      price = described_class.cost_per_minute("gpt-4o-transcribe")
      expect(price).to be > 0
    end

    it "finds pricing for gpt-4o-mini-transcribe" do
      price = described_class.cost_per_minute("gpt-4o-mini-transcribe")
      expect(price).to be > 0
    end

    it "returns nil for unknown models" do
      expect(described_class.cost_per_minute("fake-model-xyz")).to be_nil
    end
  end

  describe ".calculate_cost" do
    it "calculates cost for 2 minutes of whisper-1" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 120)
      expect(cost).to be > 0
      expect(cost).to be < 1 # sanity
    end

    it "handles zero duration" do
      cost = described_class.calculate_cost(model_id: "whisper-1", duration_seconds: 0)
      expect(cost).to eq(0.0)
    end
  end

  describe "user config takes priority over all API sources" do
    it "returns user price even when APIs disagree" do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"whisper-1" => 0.999}
      end
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.999)
    end

    it "uses API price for models not in config" do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = {"custom-model" => 0.123}
      end
      # whisper-1 should still come from LiteLLM or another source
      expect(described_class.cost_per_minute("whisper-1")).to be > 0
    end
  end

  describe ".pricing_found?" do
    it "returns true for known models" do
      expect(described_class.pricing_found?("whisper-1")).to be true
    end

    it "returns false for unknown models" do
      expect(described_class.pricing_found?("fake-model-xyz")).to be false
    end
  end

  describe ".all_pricing" do
    it "returns data from multiple tiers" do
      pricing = described_class.all_pricing
      expect(pricing.keys).to include(:litellm, :configured)
      expect(pricing[:litellm]).to be_a(Hash)
    end
  end
end
