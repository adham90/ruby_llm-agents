# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Providers::Inception::Registry do
  describe ".register_models!" do
    it "registers all Mercury models in the RubyLLM registry" do
      described_class::MODELS.each do |model_def|
        model = RubyLLM::Models.find(model_def[:id])
        expect(model).to be_a(RubyLLM::Model::Info)
        expect(model.id).to eq(model_def[:id])
        expect(model.provider).to eq("inception")
      end
    end
  end

  describe "mercury-2 model resolution" do
    let(:model) { RubyLLM::Models.find("mercury-2") }

    it "has correct provider" do
      expect(model.provider).to eq("inception")
    end

    it "has correct name" do
      expect(model.name).to eq("Mercury 2")
    end

    it "has correct family" do
      expect(model.family).to eq("mercury")
    end

    it "has 128K context window" do
      expect(model.context_window).to eq(128_000)
    end

    it "has 32K max output tokens" do
      expect(model.max_output_tokens).to eq(32_000)
    end

    it "supports streaming" do
      expect(model.capabilities).to include("streaming")
    end

    it "supports function calling" do
      expect(model.capabilities).to include("function_calling")
    end

    it "supports structured output" do
      expect(model.capabilities).to include("structured_output")
    end

    it "supports reasoning" do
      expect(model.capabilities).to include("reasoning")
    end

    it "has text-only modalities" do
      expect(model.modalities.input).to eq(["text"])
      expect(model.modalities.output).to eq(["text"])
    end

    it "has correct pricing" do
      expect(model.pricing.text_tokens.standard.input_per_million).to eq(0.25)
      expect(model.pricing.text_tokens.standard.output_per_million).to eq(0.75)
    end
  end

  describe "mercury model resolution" do
    let(:model) { RubyLLM::Models.find("mercury") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "does not include reasoning" do
      expect(model.capabilities).not_to include("reasoning")
    end
  end

  describe "mercury-coder-small model resolution" do
    let(:model) { RubyLLM::Models.find("mercury-coder-small") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "has only streaming capability" do
      expect(model.capabilities).to eq(["streaming"])
    end

    it "has higher output pricing" do
      expect(model.pricing.text_tokens.standard.output_per_million).to eq(1.00)
    end
  end

  describe "mercury-edit model resolution" do
    let(:model) { RubyLLM::Models.find("mercury-edit") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "has only streaming capability" do
      expect(model.capabilities).to eq(["streaming"])
    end
  end
end
