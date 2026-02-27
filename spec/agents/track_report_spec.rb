# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Agents::TrackReport do
  let(:started_at) { 1.second.ago }
  let(:completed_at) { Time.current }

  def build_result(**overrides)
    defaults = {
      content: "response",
      input_tokens: 100,
      output_tokens: 50,
      input_cost: 0.001,
      output_cost: 0.002,
      total_cost: 0.003,
      model_id: "gpt-4o",
      chosen_model_id: "gpt-4o",
      started_at: started_at,
      completed_at: completed_at,
      duration_ms: 500,
      agent_class_name: "TestAgent"
    }
    RubyLLM::Agents::Result.new(**defaults.merge(overrides))
  end

  let(:results) do
    [
      build_result(input_tokens: 100, output_tokens: 50, input_cost: 0.001, output_cost: 0.002, total_cost: 0.003, chosen_model_id: "gpt-4o", duration_ms: 400, agent_class_name: "AgentA"),
      build_result(input_tokens: 500, output_tokens: 200, input_cost: 0.005, output_cost: 0.010, total_cost: 0.015, chosen_model_id: "gpt-4o-mini", duration_ms: 600, agent_class_name: "AgentB"),
      build_result(input_tokens: 300, output_tokens: 100, input_cost: 0.003, output_cost: 0.004, total_cost: 0.007, chosen_model_id: "gpt-4o", duration_ms: 500, agent_class_name: "AgentC")
    ]
  end

  let(:report) do
    described_class.new(
      value: "done",
      error: nil,
      results: results,
      request_id: "req_123",
      started_at: started_at,
      completed_at: completed_at
    )
  end

  describe "#successful?" do
    it "returns true when no error" do
      expect(report).to be_successful
    end

    it "returns false when error is present" do
      error_report = described_class.new(
        value: nil, error: RuntimeError.new("boom"),
        results: [], request_id: "req_1",
        started_at: started_at, completed_at: completed_at
      )
      expect(error_report).not_to be_successful
    end
  end

  describe "#failed?" do
    it "is the inverse of successful?" do
      expect(report).not_to be_failed
    end
  end

  describe "#call_count" do
    it "returns number of results" do
      expect(report.call_count).to eq(3)
    end

    it "returns 0 for empty results" do
      empty = described_class.new(
        value: nil, error: nil, results: [],
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(empty.call_count).to eq(0)
    end
  end

  describe "cost aggregation" do
    it "sums total_cost" do
      expect(report.total_cost).to eq(0.025)
    end

    it "sums input_cost" do
      expect(report.input_cost).to be_within(0.0001).of(0.009)
    end

    it "sums output_cost" do
      expect(report.output_cost).to eq(0.016)
    end

    it "handles nil costs gracefully" do
      results_with_nil = [
        build_result(total_cost: 0.01, input_cost: 0.005, output_cost: 0.005),
        build_result(total_cost: nil, input_cost: nil, output_cost: nil)
      ]
      r = described_class.new(
        value: nil, error: nil, results: results_with_nil,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.total_cost).to eq(0.01)
      expect(r.input_cost).to eq(0.005)
      expect(r.output_cost).to eq(0.005)
    end
  end

  describe "token aggregation" do
    it "sums total_tokens" do
      expect(report.total_tokens).to eq(1250)
    end

    it "sums input_tokens" do
      expect(report.input_tokens).to eq(900)
    end

    it "sums output_tokens" do
      expect(report.output_tokens).to eq(350)
    end

    it "handles nil tokens gracefully" do
      results_with_nil = [
        build_result(input_tokens: 100, output_tokens: 50),
        build_result(input_tokens: nil, output_tokens: nil)
      ]
      r = described_class.new(
        value: nil, error: nil, results: results_with_nil,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.input_tokens).to eq(100)
      expect(r.output_tokens).to eq(50)
    end
  end

  describe "#duration_ms" do
    it "calculates wall clock time" do
      expect(report.duration_ms).to be_a(Integer)
      expect(report.duration_ms).to be >= 0
    end

    it "returns nil if timestamps missing" do
      r = described_class.new(
        value: nil, error: nil, results: [],
        request_id: "req_1", started_at: nil, completed_at: nil
      )
      expect(r.duration_ms).to be_nil
    end
  end

  describe "#value" do
    it "returns the block return value" do
      expect(report.value).to eq("done")
    end
  end

  describe "#error" do
    it "returns nil for successful report" do
      expect(report.error).to be_nil
    end

    it "returns the captured error" do
      err = RuntimeError.new("something broke")
      r = described_class.new(
        value: nil, error: err, results: [],
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.error).to eq(err)
    end
  end

  describe "#request_id" do
    it "returns the request_id" do
      expect(report.request_id).to eq("req_123")
    end
  end

  describe "#all_successful?" do
    it "returns true when all results succeeded" do
      expect(report).to be_all_successful
    end

    it "returns false when any result has an error" do
      results_with_error = [
        build_result,
        build_result(error_class: "RuntimeError", error_message: "boom")
      ]
      r = described_class.new(
        value: nil, error: nil, results: results_with_error,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r).not_to be_all_successful
    end
  end

  describe "#any_errors?" do
    it "returns false when all succeeded" do
      expect(report.any_errors?).to be false
    end

    it "returns true when any result has an error" do
      results_with_error = [
        build_result,
        build_result(error_class: "RuntimeError", error_message: "boom")
      ]
      r = described_class.new(
        value: nil, error: nil, results: results_with_error,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.any_errors?).to be true
    end
  end

  describe "#errors" do
    it "returns only error results" do
      error_result = build_result(error_class: "RuntimeError", error_message: "boom")
      results_mixed = [build_result, error_result]
      r = described_class.new(
        value: nil, error: nil, results: results_mixed,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.errors).to eq([error_result])
    end
  end

  describe "#successful" do
    it "returns only successful results" do
      ok_result = build_result
      error_result = build_result(error_class: "RuntimeError", error_message: "boom")
      results_mixed = [ok_result, error_result]
      r = described_class.new(
        value: nil, error: nil, results: results_mixed,
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.successful).to eq([ok_result])
    end
  end

  describe "#models_used" do
    it "returns unique model IDs" do
      expect(report.models_used).to contain_exactly("gpt-4o", "gpt-4o-mini")
    end
  end

  describe "#cost_breakdown" do
    it "returns per-result cost data" do
      breakdown = report.cost_breakdown
      expect(breakdown.size).to eq(3)
      expect(breakdown.first).to include(
        model: "gpt-4o",
        cost: 0.003,
        tokens: 150,
        duration_ms: 400
      )
    end
  end

  describe "#to_h" do
    it "returns a complete hash" do
      hash = report.to_h
      expect(hash).to include(
        successful: true,
        value: "done",
        error: nil,
        request_id: "req_123",
        call_count: 3,
        total_cost: 0.025,
        total_tokens: 1250
      )
    end

    it "includes error message when failed" do
      r = described_class.new(
        value: nil, error: RuntimeError.new("boom"), results: [],
        request_id: "req_1", started_at: started_at, completed_at: completed_at
      )
      expect(r.to_h[:error]).to eq("boom")
    end
  end

  describe "results freezing" do
    it "freezes results array" do
      expect(report.results).to be_frozen
    end
  end
end
