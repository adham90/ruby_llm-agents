# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Eval::Score do
  describe "#initialize" do
    it "sets value and reason" do
      score = described_class.new(value: 0.8, reason: "Good match")
      expect(score.value).to eq(0.8)
      expect(score.reason).to eq("Good match")
    end

    it "defaults reason to nil" do
      score = described_class.new(value: 1.0)
      expect(score.reason).to be_nil
    end

    it "clamps value to 0.0..1.0" do
      expect(described_class.new(value: 1.5).value).to eq(1.0)
      expect(described_class.new(value: -0.5).value).to eq(0.0)
    end

    it "converts value to float" do
      score = described_class.new(value: 1)
      expect(score.value).to eq(1.0)
      expect(score.value).to be_a(Float)
    end
  end

  describe "#passed?" do
    it "returns true when value >= threshold" do
      expect(described_class.new(value: 0.5).passed?).to be true
      expect(described_class.new(value: 1.0).passed?).to be true
    end

    it "returns false when value < threshold" do
      expect(described_class.new(value: 0.49).passed?).to be false
      expect(described_class.new(value: 0.0).passed?).to be false
    end

    it "accepts a custom threshold" do
      score = described_class.new(value: 0.8)
      expect(score.passed?(0.9)).to be false
      expect(score.passed?(0.7)).to be true
    end
  end

  describe "#failed?" do
    it "is the inverse of passed?" do
      score = described_class.new(value: 0.5)
      expect(score.failed?).to be false
      expect(score.failed?(0.9)).to be true
    end
  end
end
