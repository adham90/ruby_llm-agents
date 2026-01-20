# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator::Pricing do
  describe ".cost_per_image" do
    context "with fallback pricing" do
      before do
        # Clear any cached LiteLLM data
        described_class.instance_variable_set(:@litellm_data, nil)
        described_class.instance_variable_set(:@litellm_fetched_at, nil)

        # Stub HTTP to return empty (force fallback)
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      end

      # Note: 1024x1024 = 1,048,576 pixels which is >= 1,000,000, so it's "large"
      it "returns correct price for DALL-E 3 standard quality (large)" do
        price = described_class.cost_per_image("gpt-image-1", size: "1024x1024", quality: "standard")
        expect(price).to eq(0.08) # Large standard
      end

      it "returns correct price for DALL-E 3 HD quality (large)" do
        price = described_class.cost_per_image("gpt-image-1", size: "1024x1024", quality: "hd")
        expect(price).to eq(0.12) # Large HD
      end

      it "returns correct price for DALL-E 3 standard quality (small)" do
        price = described_class.cost_per_image("gpt-image-1", size: "512x512", quality: "standard")
        expect(price).to eq(0.04) # Small standard
      end

      it "returns correct price for DALL-E 3 HD quality (small)" do
        price = described_class.cost_per_image("gpt-image-1", size: "512x512", quality: "hd")
        expect(price).to eq(0.08) # Small HD
      end

      it "returns correct price for DALL-E 3 HD extra large size" do
        price = described_class.cost_per_image("gpt-image-1", size: "1792x1024", quality: "hd")
        expect(price).to eq(0.12) # Large HD
      end

      it "returns correct price for DALL-E 2" do
        price = described_class.cost_per_image("dall-e-2", size: "1024x1024")
        expect(price).to eq(0.02)
      end

      it "returns correct price for DALL-E 2 smaller size" do
        price = described_class.cost_per_image("dall-e-2", size: "512x512")
        expect(price).to eq(0.018)
      end

      it "returns correct price for FLUX Pro" do
        price = described_class.cost_per_image("flux-pro")
        expect(price).to eq(0.05)
      end

      it "returns correct price for FLUX Schnell" do
        price = described_class.cost_per_image("flux-schnell")
        expect(price).to eq(0.003)
      end

      it "returns correct price for SDXL" do
        price = described_class.cost_per_image("sdxl")
        expect(price).to eq(0.04)
      end

      it "returns correct price for Imagen" do
        price = described_class.cost_per_image("imagen-3")
        expect(price).to eq(0.02)
      end

      it "returns default price for unknown models" do
        price = described_class.cost_per_image("unknown-model")
        expect(price).to eq(0.04) # default_image_cost
      end
    end

    context "with configured pricing" do
      before do
        described_class.instance_variable_set(:@litellm_data, nil)
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

        RubyLLM::Agents.configure do |config|
          config.image_model_pricing = {
            "custom-model" => 0.10,
            "tiered-model" => {
              "1024x1024" => 0.05,
              "512x512" => 0.025,
              default: 0.05
            }
          }
        end
      end

      after do
        RubyLLM::Agents.configure do |config|
          config.image_model_pricing = {}
        end
      end

      it "uses configured flat pricing" do
        price = described_class.cost_per_image("custom-model")
        expect(price).to eq(0.10)
      end

      it "uses configured size-based pricing" do
        price = described_class.cost_per_image("tiered-model", size: "512x512")
        expect(price).to eq(0.025)
      end
    end
  end

  describe ".calculate_cost" do
    before do
      described_class.instance_variable_set(:@litellm_data, nil)
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
    end

    it "calculates total cost for multiple images" do
      cost = described_class.calculate_cost(
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        count: 4
      )

      expect(cost).to eq(0.32) # 0.08 * 4 (large standard)
    end

    it "calculates HD pricing correctly" do
      cost = described_class.calculate_cost(
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "hd",
        count: 2
      )

      expect(cost).to eq(0.24) # 0.12 * 2 (large HD)
    end

    it "calculates small image pricing correctly" do
      cost = described_class.calculate_cost(
        model_id: "gpt-image-1",
        size: "512x512",
        quality: "standard",
        count: 4
      )

      expect(cost).to eq(0.16) # 0.04 * 4 (small standard)
    end
  end

  describe ".all_pricing" do
    before do
      described_class.instance_variable_set(:@litellm_data, nil)
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
    end

    it "returns pricing from all sources" do
      pricing = described_class.all_pricing

      expect(pricing).to have_key(:litellm)
      expect(pricing).to have_key(:configured)
      expect(pricing).to have_key(:fallbacks)
      expect(pricing[:fallbacks]).to include("gpt-image-1")
    end
  end

  describe ".refresh!" do
    it "clears cached data" do
      described_class.instance_variable_set(:@litellm_data, { "test" => true })
      described_class.instance_variable_set(:@litellm_fetched_at, Time.now)

      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      described_class.refresh!

      # Should have cleared and re-fetched (empty due to connection refused)
      expect(described_class.instance_variable_get(:@litellm_data)).to eq({})
    end
  end
end
