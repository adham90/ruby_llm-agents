# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Providers::Inception::Capabilities do
  describe ".context_window_for" do
    it "returns 128_000 for all Mercury models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.context_window_for(model_id)).to eq(128_000),
          "Expected 128_000 for #{model_id}"
      end
    end
  end

  describe ".max_tokens_for" do
    it "returns 32_000 for all Mercury models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.max_tokens_for(model_id)).to eq(32_000),
          "Expected 32_000 for #{model_id}"
      end
    end
  end

  describe ".input_price_for" do
    it "returns 0.25 for all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.input_price_for(model_id)).to eq(0.25),
          "Expected 0.25 for #{model_id}"
      end
    end
  end

  describe ".output_price_for" do
    it "returns 0.75 for chat models" do
      expect(described_class.output_price_for("mercury-2")).to eq(0.75)
      expect(described_class.output_price_for("mercury")).to eq(0.75)
    end

    it "returns 1.00 for coder models" do
      expect(described_class.output_price_for("mercury-coder-small")).to eq(1.00)
      expect(described_class.output_price_for("mercury-edit")).to eq(1.00)
    end
  end

  describe ".supports_vision?" do
    it "returns false for all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.supports_vision?(model_id)).to be(false)
      end
    end
  end

  describe ".supports_functions?" do
    it "returns true for mercury-2" do
      expect(described_class.supports_functions?("mercury-2")).to be true
    end

    it "returns true for mercury" do
      expect(described_class.supports_functions?("mercury")).to be true
    end

    it "returns false for coder models" do
      expect(described_class.supports_functions?("mercury-coder-small")).to be false
      expect(described_class.supports_functions?("mercury-edit")).to be false
    end
  end

  describe ".supports_json_mode?" do
    it "returns true for chat models" do
      expect(described_class.supports_json_mode?("mercury-2")).to be true
      expect(described_class.supports_json_mode?("mercury")).to be true
    end

    it "returns false for coder models" do
      expect(described_class.supports_json_mode?("mercury-coder-small")).to be false
      expect(described_class.supports_json_mode?("mercury-edit")).to be false
    end
  end

  describe ".format_display_name" do
    it "returns 'Mercury 2' for mercury-2" do
      expect(described_class.format_display_name("mercury-2")).to eq("Mercury 2")
    end

    it "returns 'Mercury' for mercury" do
      expect(described_class.format_display_name("mercury")).to eq("Mercury")
    end

    it "returns 'Mercury Coder Small' for mercury-coder-small" do
      expect(described_class.format_display_name("mercury-coder-small")).to eq("Mercury Coder Small")
    end

    it "returns 'Mercury Edit' for mercury-edit" do
      expect(described_class.format_display_name("mercury-edit")).to eq("Mercury Edit")
    end

    it "capitalizes unknown model names" do
      expect(described_class.format_display_name("mercury-future-model")).to eq("Mercury Future Model")
    end
  end

  describe ".model_type" do
    it "returns 'chat' for mercury-2" do
      expect(described_class.model_type("mercury-2")).to eq("chat")
    end

    it "returns 'chat' for mercury" do
      expect(described_class.model_type("mercury")).to eq("chat")
    end

    it "returns 'code' for mercury-coder-small" do
      expect(described_class.model_type("mercury-coder-small")).to eq("code")
    end

    it "returns 'code' for mercury-edit" do
      expect(described_class.model_type("mercury-edit")).to eq("code")
    end
  end

  describe ".model_family" do
    it "returns :mercury for all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.model_family(model_id)).to eq(:mercury),
          "Expected :mercury for #{model_id}"
      end
    end
  end

  describe ".modalities_for" do
    it "returns text-only modalities for all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        result = described_class.modalities_for(model_id)
        expect(result).to eq({input: ["text"], output: ["text"]}),
          "Expected text-only modalities for #{model_id}"
      end
    end
  end

  describe ".capabilities_for" do
    it "includes streaming for all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        expect(described_class.capabilities_for(model_id)).to include("streaming"),
          "Expected streaming for #{model_id}"
      end
    end

    it "includes function_calling for mercury-2" do
      expect(described_class.capabilities_for("mercury-2")).to include("function_calling")
    end

    it "includes structured_output for mercury-2" do
      expect(described_class.capabilities_for("mercury-2")).to include("structured_output")
    end

    it "includes reasoning for mercury-2" do
      expect(described_class.capabilities_for("mercury-2")).to include("reasoning")
    end

    it "includes function_calling for mercury" do
      expect(described_class.capabilities_for("mercury")).to include("function_calling")
    end

    it "includes structured_output for mercury" do
      expect(described_class.capabilities_for("mercury")).to include("structured_output")
    end

    it "does not include reasoning for mercury" do
      expect(described_class.capabilities_for("mercury")).not_to include("reasoning")
    end

    it "only includes streaming for coder models" do
      %w[mercury-coder-small mercury-edit].each do |model_id|
        caps = described_class.capabilities_for(model_id)
        expect(caps).to eq(["streaming"]),
          "Expected only streaming for #{model_id}, got #{caps.inspect}"
      end
    end
  end

  describe ".pricing_for" do
    it "returns correct pricing for mercury-2" do
      pricing = described_class.pricing_for("mercury-2")
      expect(pricing).to eq({
        text_tokens: {
          standard: {
            input_per_million: 0.25,
            output_per_million: 0.75
          }
        }
      })
    end

    it "returns correct pricing for mercury-coder-small" do
      pricing = described_class.pricing_for("mercury-coder-small")
      expect(pricing).to eq({
        text_tokens: {
          standard: {
            input_per_million: 0.25,
            output_per_million: 1.00
          }
        }
      })
    end
  end
end
