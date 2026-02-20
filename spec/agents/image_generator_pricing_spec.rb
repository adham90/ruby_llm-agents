# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator::Pricing do
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

  # Default: LiteLLM has no image entries
  let(:litellm_response) { {"gpt-4o" => {"input_cost_per_token" => 0.0025}} }

  describe ".cost_per_image" do
    context "when no pricing is found" do
      it "returns zero for unknown models" do
        price = described_class.cost_per_image("unknown-model")
        expect(price).to eq(0)
      end

      it "returns user-configured default when set" do
        RubyLLM::Agents.configure { |c| c.default_image_cost = 0.05 }
        price = described_class.cost_per_image("unknown-model")
        expect(price).to eq(0.05)
      end
    end

    context "with LiteLLM pricing" do
      let(:litellm_response) do
        {
          "gpt-image-1" => {"input_cost_per_image" => 0.04, "mode" => "image_generation"},
          "dall-e-3" => {"input_cost_per_image" => 0.04, "input_cost_per_image_hd" => 0.08},
          "dall-e-2" => {"input_cost_per_image" => 0.02},
          "flux-pro" => {"input_cost_per_image" => 0.05},
          "flux-schnell" => {"input_cost_per_image" => 0.003},
          "sdxl" => {"input_cost_per_image" => 0.04},
          "imagen-3" => {"input_cost_per_image" => 0.02},
          "pixel-model" => {"input_cost_per_pixel" => 0.00000005}
        }
      end

      it "returns correct price for gpt-image-1" do
        price = described_class.cost_per_image("gpt-image-1")
        expect(price).to eq(0.04)
      end

      it "returns correct price for DALL-E 2" do
        price = described_class.cost_per_image("dall-e-2")
        expect(price).to eq(0.02)
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

      it "uses HD pricing when quality is hd" do
        price = described_class.cost_per_image("dall-e-3", quality: "hd")
        expect(price).to eq(0.08)
      end

      it "calculates pixel-based pricing when size provided" do
        # 1024x1024 = 1,048,576 pixels × 0.00000005 = 0.052429
        price = described_class.cost_per_image("pixel-model", size: "1024x1024")
        expect(price).to eq(0.052429)
      end
    end

    context "with RubyLLM adapter pricing" do
      before do
        allow(RubyLLM::Agents::Pricing::RubyLLMAdapter).to receive(:find_model)
          .with("gpt-image-1")
          .and_return({input_cost_per_image: 0.04, source: :ruby_llm})
      end

      it "uses RubyLLM adapter pricing" do
        price = described_class.cost_per_image("gpt-image-1")
        expect(price).to eq(0.04)
      end
    end

    context "with configured pricing" do
      before do
        RubyLLM::Agents.configure do |config|
          config.image_model_pricing = {
            "custom-model" => 0.10,
            "tiered-model" => {
              "1024x1024" => 0.05,
              "512x512" => 0.025,
              "default" => 0.05
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

      it "config takes priority over LiteLLM" do
        litellm_data = {"custom-model" => {"input_cost_per_image" => 0.50}}
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_return(status: 200, body: litellm_data.to_json)
        described_class.refresh!

        price = described_class.cost_per_image("custom-model")
        expect(price).to eq(0.10) # config wins
      end
    end
  end

  describe ".calculate_cost" do
    let(:litellm_response) do
      {
        "gpt-image-1" => {"input_cost_per_image" => 0.04}
      }
    end

    it "calculates total cost for multiple images" do
      cost = described_class.calculate_cost(
        model_id: "gpt-image-1",
        count: 4
      )
      expect(cost).to eq(0.16) # 0.04 * 4
    end

    it "defaults count to 1" do
      cost = described_class.calculate_cost(model_id: "gpt-image-1")
      expect(cost).to eq(0.04)
    end
  end

  describe ".all_pricing" do
    it "returns pricing from all sources" do
      pricing = described_class.all_pricing

      expect(pricing).to have_key(:litellm)
      expect(pricing).to have_key(:configured)
    end
  end

  describe ".refresh!" do
    it "delegates to DataStore" do
      expect(RubyLLM::Agents::Pricing::DataStore).to receive(:refresh!).at_least(:once)
      described_class.refresh!
    end
  end
end
