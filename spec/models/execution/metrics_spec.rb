# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution::Metrics do
  let(:execution) { create(:execution, input_tokens: 100, output_tokens: 50, duration_ms: 1500) }

  describe "#calculate_costs!" do
    context "with missing token data" do
      let(:execution) { create(:execution, input_tokens: nil, output_tokens: nil) }

      it "returns early without error" do
        expect { execution.calculate_costs! }.not_to raise_error
      end
    end

    context "with tokens but no model info" do
      before do
        allow(execution).to receive(:resolve_model_info).and_return(nil)
      end

      it "returns early without setting costs" do
        original_input_cost = execution.input_cost
        execution.calculate_costs!
        expect(execution.input_cost).to eq(original_input_cost)
      end
    end
  end

  describe "#duration_seconds" do
    it "converts milliseconds to seconds" do
      expect(execution.duration_seconds).to eq(1.5)
    end

    context "with nil duration_ms" do
      let(:execution) { build(:execution, duration_ms: nil) }

      it "returns nil" do
        expect(execution.duration_seconds).to be_nil
      end
    end
  end

  describe "#tokens_per_second" do
    it "calculates tokens per second" do
      expect(execution.tokens_per_second).to eq(100.0) # 150 tokens / 1.5 seconds
    end

    context "with zero duration" do
      let(:execution) { create(:execution, duration_ms: 0, total_tokens: 100) }

      it "returns nil to avoid division by zero" do
        expect(execution.tokens_per_second).to be_nil
      end
    end

    context "with nil duration" do
      let(:execution) { create(:execution, duration_ms: nil, total_tokens: 100) }

      it "returns nil" do
        expect(execution.tokens_per_second).to be_nil
      end
    end
  end

  describe "#cost_per_1k_tokens" do
    let(:execution) { create(:execution, input_cost: 0.0075, output_cost: 0.0075, total_tokens: 150) }

    it "calculates cost per 1000 tokens" do
      # total_cost = 0.015, tokens = 150, so 0.015/150*1000 = 0.1
      expect(execution.cost_per_1k_tokens).to eq(0.1)
    end

    context "with zero tokens" do
      let(:execution) do
        exec = create(:execution, input_cost: 0.015, output_cost: 0, input_tokens: 0, output_tokens: 0)
        exec.update_column(:total_tokens, 0) # bypass callback
        exec
      end

      it "returns nil" do
        expect(execution.cost_per_1k_tokens).to be_nil
      end
    end

    context "with nil total_cost" do
      let(:execution) { build(:execution, input_cost: nil, output_cost: nil, total_cost: nil, total_tokens: 100) }

      it "returns nil" do
        expect(execution.cost_per_1k_tokens).to be_nil
      end
    end
  end

  describe "#formatted_total_cost" do
    it "formats cost as currency string" do
      execution.total_cost = 0.000045
      expect(execution.formatted_total_cost).to eq("$0.000045")
    end

    it "formats larger costs" do
      execution.total_cost = 1.234567
      expect(execution.formatted_total_cost).to eq("$1.234567")
    end

    context "with nil cost" do
      it "returns nil" do
        execution.total_cost = nil
        expect(execution.formatted_total_cost).to be_nil
      end
    end
  end

  describe "#formatted_input_cost" do
    it "formats input cost" do
      execution.input_cost = 0.001
      expect(execution.formatted_input_cost).to eq("$0.001000")
    end
  end

  describe "#formatted_output_cost" do
    it "formats output cost" do
      execution.output_cost = 0.002
      expect(execution.formatted_output_cost).to eq("$0.002000")
    end
  end
end
