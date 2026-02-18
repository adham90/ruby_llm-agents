# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pricing Adapters Integration", :integration do
  before(:all) do
    WebMock.allow_net_connect!
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  after(:all) do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    WebMock.disable_net_connect!
  end

  describe RubyLLM::Agents::Pricing::LiteLLMAdapter do
    describe ".find_model" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:output_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:litellm)
      end

      it "returns transcription pricing for whisper-1" do
        result = described_class.find_model("whisper-1")
        expect(result[:input_cost_per_second]).to be > 0
        expect(result[:source]).to eq(:litellm)
      end

      it "returns TTS pricing for tts-1" do
        result = described_class.find_model("tts-1")
        expect(result).to be_present
        expect(result[:source]).to eq(:litellm)
      end

      it "returns nil for unknown models" do
        result = described_class.find_model("totally-fake-model-xyz")
        expect(result).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Pricing::PortkeyAdapter do
    describe ".find_model" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:output_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:portkey)
      end

      it "returns audio token pricing for whisper-1" do
        result = described_class.find_model("whisper-1")
        if result
          expect(result[:source]).to eq(:portkey)
        else
          skip "Portkey may not have whisper-1 pricing"
        end
      end

      it "returns pricing for claude models" do
        result = described_class.find_model("claude-3-5-sonnet-20241022")
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:portkey)
        else
          skip "Portkey may not have this claude model"
        end
      end

      it "returns nil for unknown models" do
        result = described_class.find_model("totally-fake-model-xyz")
        expect(result).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Pricing::OpenRouterAdapter do
    describe ".find_model" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:output_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:openrouter)
      end

      it "returns pricing by full ID" do
        result = described_class.find_model("openai/gpt-4o")
        expect(result[:input_cost_per_token]).to be > 0
      end

      it "returns nil for transcription models (not in OpenRouter)" do
        result = described_class.find_model("whisper-1")
        expect(result).to be_nil
      end

      it "returns nil for unknown models" do
        result = described_class.find_model("totally-fake-model-xyz")
        expect(result).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Pricing::HeliconeAdapter do
    describe ".find_model" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:helicone)
        else
          skip "Helicone may not have gpt-4o"
        end
      end

      it "returns nil for transcription models (not in Helicone)" do
        result = described_class.find_model("whisper-1")
        expect(result).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Pricing::LLMPricingAdapter do
    describe ".find_model" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:llmpricing)
        else
          skip "llmpricing.ai may be unavailable"
        end
      end

      it "returns nil for non-covered models" do
        result = described_class.find_model("whisper-1")
        expect(result).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Pricing::RubyLLMAdapter do
    describe ".find_model" do
      it "returns pricing for gpt-4o from ruby_llm gem" do
        result = described_class.find_model("gpt-4o")
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:output_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:ruby_llm)
        else
          skip "gpt-4o not in ruby_llm registry"
        end
      end

      it "returns nil for unknown models" do
        result = described_class.find_model("totally-fake-model-xyz")
        expect(result).to be_nil
      end
    end
  end

  describe "cross-source price consistency" do
    it "all sources agree on gpt-4o within an order of magnitude" do
      litellm_result = RubyLLM::Agents::Pricing::LiteLLMAdapter.find_model("gpt-4o")
      openrouter_result = RubyLLM::Agents::Pricing::OpenRouterAdapter.find_model("gpt-4o")
      portkey_result = RubyLLM::Agents::Pricing::PortkeyAdapter.find_model("gpt-4o")

      prices = [litellm_result, openrouter_result, portkey_result]
        .compact
        .map { |r| r[:input_cost_per_token] }
        .compact

      next skip("Not enough sources returned pricing") if prices.size < 2

      max = prices.max
      min = prices.min

      # Prices should be within 10x of each other
      expect(max / min).to be < 10
    end
  end
end
