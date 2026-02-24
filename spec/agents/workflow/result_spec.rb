# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::WorkflowResult do
  def build_step_result(content: "test", cost: 0.001, input_tokens: 100, output_tokens: 50, model_id: "gpt-4o", success: true)
    result = double("Result")
    allow(result).to receive(:content).and_return(content)
    allow(result).to receive(:total_cost).and_return(cost)
    allow(result).to receive(:input_cost).and_return(cost * 0.4)
    allow(result).to receive(:output_cost).and_return(cost * 0.6)
    allow(result).to receive(:input_tokens).and_return(input_tokens)
    allow(result).to receive(:output_tokens).and_return(output_tokens)
    allow(result).to receive(:model_id).and_return(model_id)
    allow(result).to receive(:success?).and_return(success)
    result
  end

  let(:step_a) { build_step_result(content: "draft", cost: 0.002, input_tokens: 200, output_tokens: 100) }
  let(:step_b) { build_step_result(content: "edited", cost: 0.001, input_tokens: 150, output_tokens: 75) }

  let(:result) do
    described_class.new(
      step_results: {draft: step_a, edit: step_b},
      step_timings: {
        draft: {started_at: Time.current - 2, completed_at: Time.current - 1, duration_ms: 1000},
        edit: {started_at: Time.current - 1, completed_at: Time.current, duration_ms: 500}
      },
      errors: {},
      started_at: Time.current - 2,
      completed_at: Time.current,
      workflow_class: "ContentWorkflow"
    )
  end

  describe "#success?" do
    it "returns true when all steps succeed" do
      expect(result.success?).to be true
    end

    it "returns false when there are errors" do
      error_result = described_class.new(
        step_results: {draft: step_a},
        errors: {edit: StandardError.new("boom")},
        started_at: Time.current,
        completed_at: Time.current,
        workflow_class: "Test"
      )
      expect(error_result.success?).to be false
    end

    it "returns false with top-level error" do
      error_result = described_class.new(
        step_results: {},
        started_at: Time.current,
        completed_at: Time.current,
        workflow_class: "Test",
        error_class: "RuntimeError",
        error_message: "boom"
      )
      expect(error_result.success?).to be false
    end
  end

  describe "#partial?" do
    it "returns true when some steps succeed and some fail" do
      partial = described_class.new(
        step_results: {draft: step_a},
        errors: {edit: StandardError.new("boom")},
        started_at: Time.current,
        completed_at: Time.current,
        workflow_class: "Test"
      )
      expect(partial.partial?).to be true
    end

    it "returns false when all succeed" do
      expect(result.partial?).to be false
    end
  end

  describe "step access" do
    it "accesses step by name" do
      expect(result.step(:draft)).to eq(step_a)
      expect(result[:edit]).to eq(step_b)
    end

    it "returns step names" do
      expect(result.step_names).to eq([:draft, :edit])
    end

    it "returns final result" do
      expect(result.final_result).to eq(step_b)
    end

    it "returns content from final step" do
      expect(result.content).to eq("edited")
    end
  end

  describe "count helpers" do
    it "returns step_count" do
      expect(result.step_count).to eq(2)
    end

    it "returns successful_step_count" do
      expect(result.successful_step_count).to eq(2)
    end

    it "returns failed_step_count" do
      expect(result.failed_step_count).to eq(0)
    end
  end

  describe "cost aggregation" do
    it "sums total_cost" do
      expect(result.total_cost).to eq(0.003)
    end

    it "sums input_cost" do
      expect(result.input_cost).to be_within(0.0001).of(0.0012)
    end

    it "sums output_cost" do
      expect(result.output_cost).to be_within(0.0001).of(0.0018)
    end
  end

  describe "token aggregation" do
    it "sums input_tokens" do
      expect(result.input_tokens).to eq(350)
    end

    it "sums output_tokens" do
      expect(result.output_tokens).to eq(175)
    end

    it "sums total_tokens" do
      expect(result.total_tokens).to eq(525)
    end
  end

  describe "#duration_ms" do
    it "returns wall-clock duration" do
      expect(result.duration_ms).to be > 0
    end
  end

  describe "#primary_model_id" do
    it "returns model from first step" do
      expect(result.primary_model_id).to eq("gpt-4o")
    end
  end

  describe "#to_h" do
    it "returns a complete hash" do
      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:step_count]).to eq(2)
      expect(hash[:total_cost]).to eq(0.003)
      expect(hash[:total_tokens]).to eq(525)
      expect(hash[:workflow_class]).to eq("ContentWorkflow")
      expect(hash[:steps]).to be_an(Array)
      expect(hash[:steps].size).to eq(2)
    end
  end
end
