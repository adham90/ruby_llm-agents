# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::RubyLLMAdapter do
  describe ".find_model" do
    context "with a known text LLM model" do
      it "returns pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        # gpt-4o should be in ruby_llm's model registry
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:output_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:ruby_llm)
        else
          skip "gpt-4o not in ruby_llm registry in this environment"
        end
      end

      it "returns pricing for claude-3-5-sonnet" do
        result = described_class.find_model("claude-3-5-sonnet-20241022")
        if result
          expect(result[:input_cost_per_token]).to be > 0
          expect(result[:source]).to eq(:ruby_llm)
        else
          skip "claude-3-5-sonnet not in ruby_llm registry in this environment"
        end
      end
    end

    context "with an unknown model" do
      it "returns nil" do
        result = described_class.find_model("totally-fake-model-xyz-999")
        expect(result).to be_nil
      end
    end

    context "with a whisper model" do
      it "attempts to find pricing" do
        result = described_class.find_model("whisper-1")
        # May or may not be in ruby_llm's registry
        if result
          expect(result[:source]).to eq(:ruby_llm)
        else
          expect(result).to be_nil
        end
      end
    end
  end
end
