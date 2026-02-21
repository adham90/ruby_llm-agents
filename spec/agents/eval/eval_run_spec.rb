# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Eval::EvalRun do
  let(:test_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "TestAgent"
      end

      model "gpt-4o-mini"
    end
  end

  let(:suite_class) do
    agent = test_agent
    Class.new(RubyLLM::Agents::Eval::EvalSuite) do
      agent agent
      test_case "a", input: {q: "1"}, expected: "a"
    end
  end

  def build_eval_result(score_value:, errored: false)
    tc = RubyLLM::Agents::Eval::TestCase.new(
      name: "case", input: {q: "test"}, expected: "expected",
      scorer: nil, options: {}
    )
    score = RubyLLM::Agents::Eval::Score.new(value: score_value)
    RubyLLM::Agents::Eval::EvalResult.new(
      test_case: tc,
      agent_result: OpenStruct.new(content: "result"),
      score: score,
      error: errored ? RuntimeError.new("boom") : nil
    )
  end

  describe "score calculation" do
    it "calculates average score across all results" do
      results = [
        build_eval_result(score_value: 1.0),
        build_eval_result(score_value: 0.5),
        build_eval_result(score_value: 0.0)
      ]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: 1.minute.ago,
        completed_at: Time.current
      )

      expect(run.score).to eq(0.5)
      expect(run.score_pct).to eq(50.0)
    end

    it "returns 0.0 for empty results" do
      run = described_class.new(
        suite: suite_class,
        results: [],
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      expect(run.score).to eq(0.0)
    end
  end

  describe "pass/fail counting" do
    it "counts passed and failed based on threshold" do
      results = [
        build_eval_result(score_value: 1.0),
        build_eval_result(score_value: 0.8),
        build_eval_result(score_value: 0.5),
        build_eval_result(score_value: 0.3),
        build_eval_result(score_value: 0.0)
      ]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: 1.minute.ago,
        completed_at: Time.current
      )

      expect(run.total_cases).to eq(5)
      expect(run.passed).to eq(3)  # 1.0, 0.8, 0.5 >= 0.5
      expect(run.failed).to eq(2)  # 0.3, 0.0 < 0.5
    end

    it "returns failures list" do
      results = [
        build_eval_result(score_value: 1.0),
        build_eval_result(score_value: 0.0)
      ]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: 1.minute.ago,
        completed_at: Time.current
      )

      expect(run.failures.size).to eq(1)
      expect(run.failures.first.score.value).to eq(0.0)
    end
  end

  describe "#errors" do
    it "returns results with errors" do
      results = [
        build_eval_result(score_value: 1.0),
        build_eval_result(score_value: 0.0, errored: true)
      ]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: 1.minute.ago,
        completed_at: Time.current
      )

      expect(run.errors.size).to eq(1)
      expect(run.errors.first.error.message).to eq("boom")
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      started = Time.current
      completed = started + 2.5.seconds

      run = described_class.new(
        suite: suite_class,
        results: [],
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: started,
        completed_at: completed
      )

      expect(run.duration_ms).to eq(2500)
    end

    it "returns 0 when timestamps are missing" do
      run = described_class.new(
        suite: suite_class,
        results: [],
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: nil,
        completed_at: nil
      )

      expect(run.duration_ms).to eq(0)
    end
  end

  describe "#agent_class" do
    it "returns the suite agent class" do
      run = described_class.new(
        suite: suite_class,
        results: [],
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      expect(run.agent_class).to eq(test_agent)
    end
  end

  describe "#summary" do
    it "includes agent name, model, score, and pass count" do
      results = [
        build_eval_result(score_value: 1.0),
        build_eval_result(score_value: 0.0)
      ]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      summary = run.summary
      expect(summary).to include("TestAgent")
      expect(summary).to include("gpt-4o")
      expect(summary).to include("50.0%")
      expect(summary).to include("1/2 passed")
      expect(summary).to include("Failures:")
    end

    it "includes errors section when present" do
      results = [build_eval_result(score_value: 0.0, errored: true)]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      expect(run.summary).to include("Errors:")
      expect(run.summary).to include("boom")
    end
  end

  describe "#to_h" do
    it "returns a serializable hash" do
      results = [build_eval_result(score_value: 1.0)]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      hash = run.to_h
      expect(hash[:agent]).to eq("TestAgent")
      expect(hash[:model]).to eq("gpt-4o")
      expect(hash[:score]).to eq(1.0)
      expect(hash[:total_cases]).to eq(1)
      expect(hash[:passed]).to eq(1)
      expect(hash[:results]).to be_an(Array)
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      results = [build_eval_result(score_value: 1.0)]

      run = described_class.new(
        suite: suite_class,
        results: results,
        model: "gpt-4o",
        pass_threshold: 0.5,
        started_at: Time.current,
        completed_at: Time.current
      )

      parsed = JSON.parse(run.to_json)
      expect(parsed["agent"]).to eq("TestAgent")
      expect(parsed["score"]).to eq(1.0)
    end
  end
end
