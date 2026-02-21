# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "EvalSuite built-in scorers" do
  # Access private scorer methods via a test subclass
  let(:suite_class) do
    Class.new(RubyLLM::Agents::Eval::EvalSuite)
  end

  describe "score_exact_match" do
    it "scores 1.0 for matching string content" do
      result = OpenStruct.new(content: "hello world")
      score = suite_class.send(:score_exact_match, result, "hello world")
      expect(score.value).to eq(1.0)
    end

    it "scores 0.0 for mismatched string content" do
      result = OpenStruct.new(content: "goodbye")
      score = suite_class.send(:score_exact_match, result, "hello")
      expect(score.value).to eq(0.0)
      expect(score.reason).to include("Expected")
      expect(score.reason).to include("hello")
    end

    it "strips whitespace before comparing strings" do
      result = OpenStruct.new(content: "  hello  ")
      score = suite_class.send(:score_exact_match, result, "hello")
      expect(score.value).to eq(1.0)
    end

    it "matches hash content with symbol keys" do
      result = OpenStruct.new(content: {route: :billing})
      score = suite_class.send(:score_exact_match, result, {route: :billing})
      expect(score.value).to eq(1.0)
    end

    it "normalizes expected hash keys to symbols" do
      result = OpenStruct.new(content: {route: :billing})
      score = suite_class.send(:score_exact_match, result, {"route" => :billing})
      expect(score.value).to eq(1.0)
    end

    it "extracts route from routing results" do
      result = OpenStruct.new(route: :billing)
      score = suite_class.send(:score_exact_match, result, {route: :billing})
      expect(score.value).to eq(1.0)
    end

    it "scores 0.0 when route doesn't match" do
      result = OpenStruct.new(route: :technical)
      score = suite_class.send(:score_exact_match, result, {route: :billing})
      expect(score.value).to eq(0.0)
      expect(score.reason).to include(":technical")
    end
  end

  describe "score_contains" do
    it "scores 1.0 when content contains expected string" do
      result = OpenStruct.new(content: "We offer a 30-day refund policy for all customers")
      score = suite_class.send(:score_contains, result, "refund policy")
      expect(score.value).to eq(1.0)
    end

    it "scores 0.0 when content does not contain expected string" do
      result = OpenStruct.new(content: "Thank you for your purchase")
      score = suite_class.send(:score_contains, result, "refund")
      expect(score.value).to eq(0.0)
      expect(score.reason).to include("Missing")
    end

    it "is case-insensitive" do
      result = OpenStruct.new(content: "Our REFUND POLICY is generous")
      score = suite_class.send(:score_contains, result, "refund policy")
      expect(score.value).to eq(1.0)
    end

    it "checks all expected strings when given an array" do
      result = OpenStruct.new(content: "We offer refunds and exchanges")
      score = suite_class.send(:score_contains, result, ["refund", "exchange"])
      expect(score.value).to eq(1.0)
    end

    it "fails when any expected string is missing from array" do
      result = OpenStruct.new(content: "We offer refunds")
      score = suite_class.send(:score_contains, result, ["refund", "exchange"])
      expect(score.value).to eq(0.0)
      expect(score.reason).to include("exchange")
    end

    it "works with non-content objects by calling to_s" do
      result = "plain string response"
      score = suite_class.send(:score_contains, result, "plain string")
      expect(score.value).to eq(1.0)
    end
  end

  describe "score_llm_judge" do
    it "parses valid judge JSON response" do
      # The mock RubyLLM.chat returns MockClient which returns MockResponse("Mock response")
      # We need to set up a mock that returns valid JSON
      mock_client = RubyLLM::MockClient.new
      allow(mock_client).to receive(:ask).and_return(
        RubyLLM::MockResponse.new('{"score": 8, "reason": "Very helpful response"}')
      )
      allow(RubyLLM).to receive(:chat).and_return(mock_client)

      tc = RubyLLM::Agents::Eval::TestCase.new(
        name: "helpful",
        input: {query: "reset password"},
        expected: nil,
        scorer: :llm_judge,
        options: {criteria: "Should be helpful"}
      )

      result = OpenStruct.new(content: "Here's how to reset your password...")
      score = suite_class.send(:score_llm_judge, result, tc)
      expect(score.value).to eq(0.8)
      expect(score.reason).to eq("Very helpful response")
    end

    it "returns 0.0 with error reason on invalid JSON" do
      mock_client = RubyLLM::MockClient.new
      allow(mock_client).to receive(:ask).and_return(
        RubyLLM::MockResponse.new("not valid json")
      )
      allow(RubyLLM).to receive(:chat).and_return(mock_client)

      tc = RubyLLM::Agents::Eval::TestCase.new(
        name: "test",
        input: {query: "test"},
        expected: nil,
        scorer: :llm_judge,
        options: {criteria: "be good"}
      )

      result = OpenStruct.new(content: "response")
      score = suite_class.send(:score_llm_judge, result, tc)
      expect(score.value).to eq(0.0)
      expect(score.reason).to include("Judge error")
    end

    it "uses custom judge_model when specified" do
      mock_client = RubyLLM::MockClient.new
      allow(mock_client).to receive(:ask).and_return(
        RubyLLM::MockResponse.new('{"score": 10, "reason": "Perfect"}')
      )
      allow(RubyLLM).to receive(:chat).with(model: "claude-sonnet-4-6").and_return(mock_client)

      tc = RubyLLM::Agents::Eval::TestCase.new(
        name: "test",
        input: {query: "test"},
        expected: nil,
        scorer: :llm_judge,
        options: {criteria: "be good", judge_model: "claude-sonnet-4-6"}
      )

      result = OpenStruct.new(content: "response")
      score = suite_class.send(:score_llm_judge, result, tc)
      expect(score.value).to eq(1.0)
    end
  end

  describe "coerce_score" do
    it "passes through Score objects" do
      original = RubyLLM::Agents::Eval::Score.new(value: 0.7, reason: "ok")
      coerced = suite_class.send(:coerce_score, original)
      expect(coerced).to eq(original)
    end

    it "converts numeric to Score" do
      coerced = suite_class.send(:coerce_score, 0.9)
      expect(coerced.value).to eq(0.9)
    end

    it "converts true to Score(1.0)" do
      coerced = suite_class.send(:coerce_score, true)
      expect(coerced.value).to eq(1.0)
    end

    it "converts false to Score(0.0)" do
      coerced = suite_class.send(:coerce_score, false)
      expect(coerced.value).to eq(0.0)
    end

    it "converts unexpected types to Score(0.0) with reason" do
      coerced = suite_class.send(:coerce_score, "unexpected")
      expect(coerced.value).to eq(0.0)
      expect(coerced.reason).to include("String")
    end
  end
end
