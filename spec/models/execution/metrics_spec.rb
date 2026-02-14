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
      let(:execution) { create(:execution, model_id: "nonexistent-model-xyz", input_tokens: 100, output_tokens: 50) }

      it "returns early without setting costs" do
        original_input_cost = execution.input_cost
        execution.calculate_costs!
        expect(execution.input_cost).to eq(original_input_cost)
      end
    end

    context "formula verification with known pricing" do
      let(:model_info) { RubyLLM::Models.find("gpt-4o") }
      let(:input_price) { model_info.pricing.text_tokens.input }
      let(:output_price) { model_info.pricing.text_tokens.output }

      it "correctly calculates costs with real model pricing" do
        execution.update_columns(input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        expected_input = ((100 / 1_000_000.0) * input_price).round(6)
        expected_output = ((50 / 1_000_000.0) * output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
        # Regression: costs must be non-zero for a model with non-zero pricing
        expect(execution.input_cost).to be > 0
        expect(execution.output_cost).to be > 0
      end

      it "calculates costs correctly for small token counts (1 token)" do
        execution.update_columns(input_tokens: 1, output_tokens: 1, input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        expect(execution.input_cost).to eq(((1 / 1_000_000.0) * input_price).round(6))
        expect(execution.output_cost).to eq(((1 / 1_000_000.0) * output_price).round(6))
      end

      it "calculates costs correctly for medium token counts (10K tokens)" do
        execution.update_columns(input_tokens: 10_000, output_tokens: 5_000, input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        expect(execution.input_cost).to eq(((10_000 / 1_000_000.0) * input_price).round(6))
        expect(execution.output_cost).to eq(((5_000 / 1_000_000.0) * output_price).round(6))
      end

      it "calculates costs correctly for large token counts (1M tokens)" do
        execution.update_columns(input_tokens: 1_000_000, output_tokens: 500_000, input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        expect(execution.input_cost).to eq(((1_000_000 / 1_000_000.0) * input_price).round(6))
        expect(execution.output_cost).to eq(((500_000 / 1_000_000.0) * output_price).round(6))
      end

      it "rounds to 6 decimal places for precision" do
        execution.update_columns(input_tokens: 123, output_tokens: 456, input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        expect(execution.input_cost).to eq(((123 / 1_000_000.0) * input_price).round(6))
        expect(execution.output_cost).to eq(((456 / 1_000_000.0) * output_price).round(6))

        # Verify 6 decimal precision
        expect(execution.input_cost.to_s.split(".").last.length).to be <= 6
        expect(execution.output_cost.to_s.split(".").last.length).to be <= 6
      end

      it "uses passed model_info instead of resolving" do
        # Use a nonexistent model so resolve_model_info would return nil
        execution.update_columns(model_id: "nonexistent-model", input_cost: nil, output_cost: nil)

        execution.calculate_costs!(model_info)

        # If resolve_model_info had been called instead, costs would be nil (model not found)
        expect(execution.input_cost).to be_present
        expect(execution.output_cost).to be_present
      end
    end

    context "with zero pricing" do
      let(:zero_pricing_model) { build_model_info_with_pricing(input_price: 0.0, output_price: 0.0) }

      it "returns zero costs when pricing is zero" do
        execution.update_columns(input_cost: nil, output_cost: nil)
        execution.calculate_costs!(zero_pricing_model)

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
    let(:gpt4o_info) { RubyLLM::Models.find("gpt-4o") }
    let(:gpt4o_input_price) { gpt4o_info.pricing.text_tokens.input }
    let(:gpt4o_output_price) { gpt4o_info.pricing.text_tokens.output }

    let(:sonnet_info) { RubyLLM::Models.find("claude-3-5-sonnet-20241022") }
    let(:sonnet_input_price) { sonnet_info.pricing.text_tokens.input }
    let(:sonnet_output_price) { sonnet_info.pricing.text_tokens.output }

    # Helper to set attempts on detail and reset costs on execution
    def set_attempts_and_reset_costs(execution, attempts_data)
      # Use update! instead of update_columns to properly handle JSON type casting
      if attempts_data.nil?
        # attempts has NOT NULL constraint, use update_columns to bypass validation
        execution.detail.update_columns(attempts: nil)
      else
        execution.detail.update!(attempts: attempts_data)
      end
      execution.update_columns(input_cost: nil, output_cost: nil)
      execution.reload
    end

    context "with blank attempts" do
      it "returns early when attempts is nil" do
        # Destroy the detail record so attempts delegation returns nil
        execution.detail.destroy!
        execution.reload
        execution.update_columns(input_cost: nil, output_cost: nil)
        execution.aggregate_attempt_costs!

        expect(execution.input_cost).to be_nil
        expect(execution.output_cost).to be_nil
      end

      it "returns early when attempts is empty array" do
        set_attempts_and_reset_costs(execution, [])
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

      it "calculates costs from single attempt" do
        set_attempts_and_reset_costs(execution, single_attempt)
        execution.aggregate_attempt_costs!

        expected_input = ((1000 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = ((500 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
        # Regression: costs must be non-zero
        expect(execution.input_cost).to be > 0
        expect(execution.output_cost).to be > 0
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

      it "sums costs from all attempts" do
        set_attempts_and_reset_costs(execution, multiple_attempts)
        execution.aggregate_attempt_costs!

        expected_input = (2 * (1000 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = (2 * (500 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
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
            "model_id" => "claude-3-5-sonnet-20241022",
            "input_tokens" => 1000,
            "output_tokens" => 500
          }
        ]
      end

      it "calculates costs using each attempt's model pricing" do
        set_attempts_and_reset_costs(execution, fallback_attempts)
        execution.aggregate_attempt_costs!

        expected_input = (
          (1000 / 1_000_000.0) * gpt4o_input_price +
          (1000 / 1_000_000.0) * sonnet_input_price
        ).round(6)
        expected_output = (
          (500 / 1_000_000.0) * gpt4o_output_price +
          (500 / 1_000_000.0) * sonnet_output_price
        ).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
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

      it "skips short-circuited attempts" do
        set_attempts_and_reset_costs(execution, attempts_with_short_circuit)
        execution.aggregate_attempt_costs!

        expected_input = ((1000 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = ((500 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
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

      it "skips attempts with unavailable model info" do
        set_attempts_and_reset_costs(execution, attempts_with_unknown_model)
        execution.aggregate_attempt_costs!

        expected_input = ((1000 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = ((500 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
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

      it "handles zero tokens gracefully" do
        set_attempts_and_reset_costs(execution, zero_token_attempts)
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

      it "treats nil tokens as zero" do
        set_attempts_and_reset_costs(execution, missing_token_attempts)
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

      it "correctly calculates large token costs" do
        set_attempts_and_reset_costs(execution, large_token_attempts)
        execution.aggregate_attempt_costs!

        expected_input = ((10_000_000 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = ((5_000_000 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
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

      it "rounds final costs to 6 decimal places" do
        set_attempts_and_reset_costs(execution, fractional_attempts)
        execution.aggregate_attempt_costs!

        expected_input = ((123 / 1_000_000.0) * gpt4o_input_price).round(6)
        expected_output = ((456 / 1_000_000.0) * gpt4o_output_price).round(6)
        expect(execution.input_cost).to eq(expected_input)
        expect(execution.output_cost).to eq(expected_output)
      end
    end
  end
end
