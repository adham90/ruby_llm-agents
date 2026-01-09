# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::CostCalculation do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include RubyLLM::Agents::Base::CostCalculation

      def model
        "gpt-4o"
      end
    end
  end

  let(:instance) { test_class.new }

  # Mock model info structure
  let(:text_tokens_pricing) do
    double("text_tokens", input: 5.0, output: 15.0)
  end

  let(:model_pricing) do
    double("pricing", text_tokens: text_tokens_pricing)
  end

  let(:model_info) do
    double("model_info", pricing: model_pricing)
  end

  describe "#result_model_info" do
    it "resolves model info from response model_id" do
      allow(RubyLLM::Models).to receive(:resolve).with("gpt-4o").and_return([model_info, :openai])

      result = instance.result_model_info("gpt-4o")
      expect(result).to eq(model_info)
    end

    it "falls back to instance model when response model_id is nil" do
      allow(RubyLLM::Models).to receive(:resolve).with("gpt-4o").and_return([model_info, :openai])

      result = instance.result_model_info(nil)
      expect(result).to eq(model_info)
    end

    it "returns nil when lookup_id is nil and model is nil" do
      allow(instance).to receive(:model).and_return(nil)

      result = instance.result_model_info(nil)
      expect(result).to be_nil
    end

    it "returns nil when RubyLLM::Models.resolve raises an error" do
      allow(RubyLLM::Models).to receive(:resolve).and_raise(StandardError.new("Unknown model"))

      result = instance.result_model_info("unknown-model")
      expect(result).to be_nil
    end
  end

  describe "#resolve_model_info" do
    it "resolves model info object (extracts from tuple)" do
      allow(RubyLLM::Models).to receive(:resolve).with("gpt-4o").and_return([model_info, :openai])

      result = instance.resolve_model_info("gpt-4o")
      expect(result).to eq(model_info)
    end

    it "returns nil on error" do
      allow(RubyLLM::Models).to receive(:resolve).and_raise(StandardError.new("Error"))

      result = instance.resolve_model_info("bad-model")
      expect(result).to be_nil
    end
  end

  describe "#result_input_cost" do
    before do
      allow(instance).to receive(:result_model_info).and_return(model_info)
    end

    it "returns nil when input_tokens is nil" do
      result = instance.result_input_cost(nil, "gpt-4o")
      expect(result).to be_nil
    end

    it "returns nil when model_info is nil" do
      allow(instance).to receive(:result_model_info).and_return(nil)

      result = instance.result_input_cost(100, "gpt-4o")
      expect(result).to be_nil
    end

    it "returns nil when pricing is nil" do
      allow(model_info).to receive(:pricing).and_return(nil)

      result = instance.result_input_cost(100, "gpt-4o")
      expect(result).to be_nil
    end

    it "calculates cost per million tokens" do
      # 1000 tokens at $5.00/million = $0.005
      result = instance.result_input_cost(1000, "gpt-4o")
      expect(result).to eq(0.005)
    end

    it "rounds to 6 decimal places" do
      # 123 tokens at $5.00/million = $0.000615
      result = instance.result_input_cost(123, "gpt-4o")
      expect(result).to eq(0.000615)
    end

    it "handles zero tokens" do
      result = instance.result_input_cost(0, "gpt-4o")
      expect(result).to eq(0.0)
    end

    it "handles large token counts" do
      # 10 million tokens at $5.00/million = $50.00
      result = instance.result_input_cost(10_000_000, "gpt-4o")
      expect(result).to eq(50.0)
    end

    it "uses 0 when text_tokens input is nil" do
      allow(text_tokens_pricing).to receive(:input).and_return(nil)

      result = instance.result_input_cost(1000, "gpt-4o")
      expect(result).to eq(0.0)
    end
  end

  describe "#result_output_cost" do
    before do
      allow(instance).to receive(:result_model_info).and_return(model_info)
    end

    it "returns nil when output_tokens is nil" do
      result = instance.result_output_cost(nil, "gpt-4o")
      expect(result).to be_nil
    end

    it "returns nil when model_info is nil" do
      allow(instance).to receive(:result_model_info).and_return(nil)

      result = instance.result_output_cost(100, "gpt-4o")
      expect(result).to be_nil
    end

    it "calculates cost per million tokens" do
      # 1000 tokens at $15.00/million = $0.015
      result = instance.result_output_cost(1000, "gpt-4o")
      expect(result).to eq(0.015)
    end

    it "rounds to 6 decimal places" do
      # 123 tokens at $15.00/million = $0.001845
      result = instance.result_output_cost(123, "gpt-4o")
      expect(result).to eq(0.001845)
    end

    it "handles zero tokens" do
      result = instance.result_output_cost(0, "gpt-4o")
      expect(result).to eq(0.0)
    end

    it "uses 0 when text_tokens output is nil" do
      allow(text_tokens_pricing).to receive(:output).and_return(nil)

      result = instance.result_output_cost(1000, "gpt-4o")
      expect(result).to eq(0.0)
    end
  end

  describe "#result_total_cost" do
    before do
      allow(instance).to receive(:result_model_info).and_return(model_info)
    end

    it "returns nil when both costs are nil" do
      allow(instance).to receive(:result_input_cost).and_return(nil)
      allow(instance).to receive(:result_output_cost).and_return(nil)

      result = instance.result_total_cost(nil, nil, "gpt-4o")
      expect(result).to be_nil
    end

    it "calculates sum of input and output costs" do
      # Input: 1000 tokens at $5.00/million = $0.005
      # Output: 500 tokens at $15.00/million = $0.0075
      # Total: $0.0125
      result = instance.result_total_cost(1000, 500, "gpt-4o")
      expect(result).to eq(0.0125)
    end

    it "rounds total to 6 decimal places" do
      result = instance.result_total_cost(123, 456, "gpt-4o")
      expect(result.to_s.split(".").last.length).to be <= 6
    end

    it "handles only input cost present" do
      allow(instance).to receive(:result_output_cost).and_return(nil)

      result = instance.result_total_cost(1000, nil, "gpt-4o")
      expect(result).to eq(0.005)
    end

    it "handles only output cost present" do
      allow(instance).to receive(:result_input_cost).and_return(nil)

      result = instance.result_total_cost(nil, 1000, "gpt-4o")
      expect(result).to eq(0.015)
    end
  end

  describe "#record_attempt_cost" do
    let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      RubyLLM::Agents.reset_configuration!
      allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
      cache_store.clear
    end

    context "without successful attempt" do
      it "returns early when attempt_tracker has no successful attempt" do
        tracker = double("tracker", successful_attempt: nil)

        expect(RubyLLM::Agents::BudgetTracker).not_to receive(:record_spend!)
        instance.record_attempt_cost(tracker)
      end
    end

    context "with successful attempt" do
      let(:successful_attempt) do
        {
          model_id: "gpt-4o",
          input_tokens: 1000,
          output_tokens: 500
        }
      end

      let(:tracker) { double("tracker", successful_attempt: successful_attempt) }

      before do
        allow(instance).to receive(:resolve_model_info).and_return(model_info)
      end

      it "records spend to BudgetTracker" do
        # Expected cost: (1000/1M * 5.0) + (500/1M * 15.0) = 0.005 + 0.0075 = 0.0125
        expect(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!)
          .with(anything, 0.0125, tenant_id: nil)

        instance.record_attempt_cost(tracker)
      end

      it "passes tenant_id to BudgetTracker" do
        expect(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!)
          .with(anything, anything, tenant_id: "tenant_123")

        instance.record_attempt_cost(tracker, tenant_id: "tenant_123")
      end

      it "handles missing input_tokens" do
        tracker = double("tracker", successful_attempt: {
          model_id: "gpt-4o",
          input_tokens: nil,
          output_tokens: 500
        })

        # Expected cost: (0/1M * 5.0) + (500/1M * 15.0) = 0 + 0.0075 = 0.0075
        expect(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!)
          .with(anything, 0.0075, tenant_id: nil)

        instance.record_attempt_cost(tracker)
      end

      it "handles missing output_tokens" do
        tracker = double("tracker", successful_attempt: {
          model_id: "gpt-4o",
          input_tokens: 1000,
          output_tokens: nil
        })

        # Expected cost: (1000/1M * 5.0) + (0/1M * 15.0) = 0.005 + 0 = 0.005
        expect(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!)
          .with(anything, 0.005, tenant_id: nil)

        instance.record_attempt_cost(tracker)
      end
    end

    context "when model_info is unavailable" do
      it "returns early without recording" do
        tracker = double("tracker", successful_attempt: { model_id: "unknown-model" })
        allow(instance).to receive(:resolve_model_info).and_return(nil)

        expect(RubyLLM::Agents::BudgetTracker).not_to receive(:record_spend!)
        instance.record_attempt_cost(tracker)
      end

      it "returns early when pricing is nil" do
        tracker = double("tracker", successful_attempt: { model_id: "gpt-4o" })
        model_without_pricing = double("model", pricing: nil)
        allow(instance).to receive(:resolve_model_info).and_return(model_without_pricing)

        expect(RubyLLM::Agents::BudgetTracker).not_to receive(:record_spend!)
        instance.record_attempt_cost(tracker)
      end
    end

    context "when an error occurs" do
      let(:tracker) { double("tracker", successful_attempt: { model_id: "gpt-4o", input_tokens: 100, output_tokens: 50 }) }

      before do
        allow(instance).to receive(:resolve_model_info).and_return(model_info)
        allow(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!).and_raise(StandardError.new("Budget error"))
      end

      it "logs a warning and does not raise" do
        expect(Rails.logger).to receive(:warn).with(/Failed to record budget spend/)

        expect { instance.record_attempt_cost(tracker) }.not_to raise_error
      end
    end
  end
end
