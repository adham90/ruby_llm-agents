# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Eval::EvalResult do
  let(:test_case) do
    RubyLLM::Agents::Eval::TestCase.new(
      name: "billing case",
      input: {message: "charged twice"},
      expected: {route: :billing},
      scorer: nil,
      options: {}
    )
  end

  let(:passing_score) { RubyLLM::Agents::Eval::Score.new(value: 1.0) }
  let(:failing_score) { RubyLLM::Agents::Eval::Score.new(value: 0.0, reason: "Mismatch") }

  describe "#initialize" do
    it "stores all attributes" do
      result = described_class.new(
        test_case: test_case,
        agent_result: OpenStruct.new(content: "response"),
        score: passing_score,
        execution_id: 42,
        error: nil
      )

      expect(result.test_case).to eq(test_case)
      expect(result.score).to eq(passing_score)
      expect(result.execution_id).to eq(42)
      expect(result.error).to be_nil
    end
  end

  describe "#test_case_name" do
    it "returns the test case name" do
      result = described_class.new(test_case: test_case, agent_result: nil, score: passing_score)
      expect(result.test_case_name).to eq("billing case")
    end
  end

  describe "#input and #expected" do
    it "delegates to test case" do
      result = described_class.new(test_case: test_case, agent_result: nil, score: passing_score)
      expect(result.input).to eq({message: "charged twice"})
      expect(result.expected).to eq({route: :billing})
    end
  end

  describe "#actual" do
    it "extracts route from routing results as a hash" do
      agent_result = OpenStruct.new(route: :billing)
      result = described_class.new(test_case: test_case, agent_result: agent_result, score: passing_score)
      expect(result.actual).to eq({route: :billing})
    end

    it "extracts content from standard results" do
      agent_result = OpenStruct.new(content: "hello world")
      result = described_class.new(test_case: test_case, agent_result: agent_result, score: passing_score)
      expect(result.actual).to eq("hello world")
    end

    it "returns nil when agent_result is nil" do
      result = described_class.new(test_case: test_case, agent_result: nil, score: failing_score)
      expect(result.actual).to be_nil
    end

    it "returns the object itself for unknown result types" do
      agent_result = "plain string"
      result = described_class.new(test_case: test_case, agent_result: agent_result, score: passing_score)
      expect(result.actual).to eq("plain string")
    end
  end

  describe "#passed? and #failed?" do
    it "delegates to score" do
      result = described_class.new(test_case: test_case, agent_result: nil, score: passing_score)
      expect(result.passed?).to be true
      expect(result.failed?).to be false
    end

    it "supports custom threshold" do
      score = RubyLLM::Agents::Eval::Score.new(value: 0.7)
      result = described_class.new(test_case: test_case, agent_result: nil, score: score)
      expect(result.passed?(0.9)).to be false
      expect(result.passed?(0.5)).to be true
    end
  end

  describe "#errored?" do
    it "returns false when no error" do
      result = described_class.new(test_case: test_case, agent_result: nil, score: passing_score)
      expect(result.errored?).to be false
    end

    it "returns true when error is present" do
      result = described_class.new(
        test_case: test_case,
        agent_result: nil,
        score: failing_score,
        error: RuntimeError.new("boom")
      )
      expect(result.errored?).to be true
    end
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      agent_result = OpenStruct.new(content: "response text")
      result = described_class.new(
        test_case: test_case,
        agent_result: agent_result,
        score: failing_score,
        execution_id: 99,
        error: RuntimeError.new("something broke")
      )

      hash = result.to_h
      expect(hash[:name]).to eq("billing case")
      expect(hash[:score]).to eq(0.0)
      expect(hash[:reason]).to eq("Mismatch")
      expect(hash[:passed]).to be false
      expect(hash[:actual]).to eq("response text")
      expect(hash[:execution_id]).to eq(99)
      expect(hash[:error]).to eq("something broke")
    end
  end
end
