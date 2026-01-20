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

    context "formula verification with known pricing" do
      # Mock model info with $5/M input, $15/M output (standard pricing)
      let(:text_tokens_pricing) { double("text_tokens", input: 5.0, output: 15.0) }
      let(:model_pricing) { double("pricing", text_tokens: text_tokens_pricing) }
      let(:model_info) { double("model_info", pricing: model_pricing) }

      before do
        allow(execution).to receive(:resolve_model_info).and_return(model_info)
      end

      it "correctly calculates costs with known pricing ($5/M input, $15/M output)" do
        # Reset costs to nil to test calculation
        execution.update_columns(input_cost: nil, output_cost: nil)

        # 100 input tokens at $5/M = $0.0005
        # 50 output tokens at $15/M = $0.00075
        execution.calculate_costs!

        expect(execution.input_cost).to eq(0.0005)
        expect(execution.output_cost).to eq(0.00075)
      end

      it "calculates costs correctly for small token counts (1 token)" do
        execution.update_columns(input_tokens: 1, output_tokens: 1, input_cost: nil, output_cost: nil)

        execution.calculate_costs!

        # 1 token at $5/M = $0.000005
        # 1 token at $15/M = $0.000015
        expect(execution.input_cost).to eq(0.000005)
        expect(execution.output_cost).to eq(0.000015)
      end

      it "calculates costs correctly for medium token counts (10K tokens)" do
        execution.update_columns(input_tokens: 10_000, output_tokens: 5_000, input_cost: nil, output_cost: nil)

        execution.calculate_costs!

        # 10,000 input tokens at $5/M = $0.05
        # 5,000 output tokens at $15/M = $0.075
        expect(execution.input_cost).to eq(0.05)
        expect(execution.output_cost).to eq(0.075)
      end

      it "calculates costs correctly for large token counts (1M tokens)" do
        execution.update_columns(input_tokens: 1_000_000, output_tokens: 500_000, input_cost: nil, output_cost: nil)

        execution.calculate_costs!

        # 1,000,000 input tokens at $5/M = $5.00
        # 500,000 output tokens at $15/M = $7.50
        expect(execution.input_cost).to eq(5.0)
        expect(execution.output_cost).to eq(7.5)
      end

      it "rounds to 6 decimal places for precision" do
        # 123 tokens produces fractional costs that need rounding
        execution.update_columns(input_tokens: 123, output_tokens: 456, input_cost: nil, output_cost: nil)

        execution.calculate_costs!

        # 123 * 5 / 1,000,000 = 0.000615
        # 456 * 15 / 1,000,000 = 0.00684
        expect(execution.input_cost).to eq(0.000615)
        expect(execution.output_cost).to eq(0.00684)

        # Verify 6 decimal precision
        expect(execution.input_cost.to_s.split(".").last.length).to be <= 6
        expect(execution.output_cost.to_s.split(".").last.length).to be <= 6
      end

      it "uses passed model_info instead of resolving" do
        execution.update_columns(input_cost: nil, output_cost: nil)

        # Don't expect resolve_model_info to be called when model_info is passed
        expect(execution).not_to receive(:resolve_model_info)

        execution.calculate_costs!(model_info)

        expect(execution.input_cost).to be_present
        expect(execution.output_cost).to be_present
      end
    end

    context "with zero pricing" do
      let(:text_tokens_pricing) { double("text_tokens", input: 0.0, output: 0.0) }
      let(:model_pricing) { double("pricing", text_tokens: text_tokens_pricing) }
      let(:model_info) { double("model_info", pricing: model_pricing) }

      before do
        allow(execution).to receive(:resolve_model_info).and_return(model_info)
      end

      it "returns zero costs when pricing is zero" do
        execution.update_columns(input_cost: nil, output_cost: nil)
        execution.calculate_costs!

        expect(execution.input_cost).to eq(0.0)
        expect(execution.output_cost).to eq(0.0)
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

  describe "#aggregate_attempt_costs!" do
    # Mock model info with $5/M input, $15/M output
    let(:text_tokens_pricing) { double("text_tokens", input: 5.0, output: 15.0) }
    let(:model_pricing) { double("pricing", text_tokens: text_tokens_pricing) }
    let(:model_info) { double("model_info", pricing: model_pricing) }

    # Different model with $10/M input, $30/M output (more expensive)
    let(:expensive_text_tokens) { double("text_tokens", input: 10.0, output: 30.0) }
    let(:expensive_pricing) { double("pricing", text_tokens: expensive_text_tokens) }
    let(:expensive_model_info) { double("model_info", pricing: expensive_pricing) }

    context "with blank attempts" do
      it "returns early when attempts is nil" do
        execution.update_columns(attempts: nil, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        expect(execution.input_cost).to be_nil
        expect(execution.output_cost).to be_nil
      end

      it "returns early when attempts is empty array" do
        execution.update_columns(attempts: [], input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        expect(execution.input_cost).to be_nil
        expect(execution.output_cost).to be_nil
      end
    end

    context "with single attempt" do
      let(:single_attempt) do
        [{
          "model_id" => "gpt-4o",
          "input_tokens" => 1000,
          "output_tokens" => 500
        }]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "calculates costs from single attempt" do
        execution.update_columns(attempts: single_attempt, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # 1000 * 5 / 1M = 0.005
        # 500 * 15 / 1M = 0.0075
        expect(execution.input_cost).to eq(0.005)
        expect(execution.output_cost).to eq(0.0075)
      end
    end

    context "with multiple attempts using same model" do
      let(:multiple_attempts) do
        [
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500,
            "error_class" => "RateLimitError"
          },
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "sums costs from all attempts" do
        execution.update_columns(attempts: multiple_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # First attempt: 0.005 input + 0.0075 output
        # Second attempt: 0.005 input + 0.0075 output
        # Total: 0.01 input + 0.015 output
        expect(execution.input_cost).to eq(0.01)
        expect(execution.output_cost).to eq(0.015)
      end
    end

    context "with multiple attempts using different models (fallback scenario)" do
      let(:fallback_attempts) do
        [
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500,
            "error_class" => "RateLimitError"
          },
          {
            "model_id" => "claude-3-opus",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
        allow(execution).to receive(:resolve_model_info).with("claude-3-opus").and_return(expensive_model_info)
      end

      it "calculates costs using each attempt's model pricing" do
        execution.update_columns(attempts: fallback_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # First attempt (gpt-4o at $5/$15): 0.005 input + 0.0075 output
        # Second attempt (claude-3-opus at $10/$30): 0.01 input + 0.015 output
        # Total: 0.015 input + 0.0225 output
        expect(execution.input_cost).to eq(0.015)
        expect(execution.output_cost).to eq(0.0225)
      end
    end

    context "with short-circuited attempts" do
      let(:attempts_with_short_circuit) do
        [
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 0,
            "output_tokens" => 0,
            "short_circuited" => true
          },
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "skips short-circuited attempts" do
        execution.update_columns(attempts: attempts_with_short_circuit, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # Only second attempt counts: 0.005 input + 0.0075 output
        expect(execution.input_cost).to eq(0.005)
        expect(execution.output_cost).to eq(0.0075)
      end
    end

    context "with missing pricing data" do
      let(:attempts_with_unknown_model) do
        [
          {
            "model_id" => "unknown-model",
            "input_tokens" => 1000,
            "output_tokens" => 500
          },
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("unknown-model").and_return(nil)
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "skips attempts with unavailable model info" do
        execution.update_columns(attempts: attempts_with_unknown_model, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # Only gpt-4o attempt counts: 0.005 input + 0.0075 output
        expect(execution.input_cost).to eq(0.005)
        expect(execution.output_cost).to eq(0.0075)
      end
    end

    context "with nil pricing" do
      let(:nil_pricing_model) { double("model_info", pricing: nil) }
      let(:attempts_with_nil_pricing) do
        [
          {
            "model_id" => "model-without-pricing",
            "input_tokens" => 1000,
            "output_tokens" => 500
          },
          {
            "model_id" => "gpt-4o",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("model-without-pricing").and_return(nil_pricing_model)
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "skips attempts where pricing is nil" do
        execution.update_columns(attempts: attempts_with_nil_pricing, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # Only gpt-4o attempt counts
        expect(execution.input_cost).to eq(0.005)
        expect(execution.output_cost).to eq(0.0075)
      end
    end

    context "with zero tokens" do
      let(:zero_token_attempts) do
        [{
          "model_id" => "gpt-4o",
          "input_tokens" => 0,
          "output_tokens" => 0
        }]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "handles zero tokens gracefully" do
        execution.update_columns(attempts: zero_token_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        expect(execution.input_cost).to eq(0.0)
        expect(execution.output_cost).to eq(0.0)
      end
    end

    context "with missing token counts" do
      let(:missing_token_attempts) do
        [{
          "model_id" => "gpt-4o",
          "input_tokens" => nil,
          "output_tokens" => nil
        }]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "treats nil tokens as zero" do
        execution.update_columns(attempts: missing_token_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        expect(execution.input_cost).to eq(0.0)
        expect(execution.output_cost).to eq(0.0)
      end
    end

    context "with large token counts" do
      let(:large_token_attempts) do
        [{
          "model_id" => "gpt-4o",
          "input_tokens" => 10_000_000, # 10M tokens
          "output_tokens" => 5_000_000  # 5M tokens
        }]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "correctly calculates large token costs" do
        execution.update_columns(attempts: large_token_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # 10M * 5 / 1M = 50.0
        # 5M * 15 / 1M = 75.0
        expect(execution.input_cost).to eq(50.0)
        expect(execution.output_cost).to eq(75.0)
      end
    end

    context "rounding to 6 decimal places" do
      let(:fractional_attempts) do
        [{
          "model_id" => "gpt-4o",
          "input_tokens" => 123,
          "output_tokens" => 456
        }]
      end

      before do
        allow(execution).to receive(:resolve_model_info).with("gpt-4o").and_return(model_info)
      end

      it "rounds final costs to 6 decimal places" do
        execution.update_columns(attempts: fractional_attempts, input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        # 123 * 5 / 1M = 0.000615
        # 456 * 15 / 1M = 0.00684
        expect(execution.input_cost).to eq(0.000615)
        expect(execution.output_cost).to eq(0.00684)
      end
    end
  end
end
