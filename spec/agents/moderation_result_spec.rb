# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ModerationResult do
  let(:raw_result) do
    double(
      "RawModerationResult",
      flagged?: true,
      flagged_categories: ["hate", "violence"],
      category_scores: { "hate" => 0.85, "violence" => 0.6, "sexual" => 0.1 },
      id: "modr-123",
      model: "text-moderation-007"
    )
  end

  describe "#initialize" do
    it "sets raw_result" do
      result = described_class.new(result: raw_result)
      expect(result.raw_result).to eq(raw_result)
    end

    it "sets threshold" do
      result = described_class.new(result: raw_result, threshold: 0.8)
      expect(result.threshold).to eq(0.8)
    end

    it "sets filter_categories and normalizes to symbols" do
      result = described_class.new(result: raw_result, categories: ["hate", :violence])
      expect(result.filter_categories).to eq([:hate, :violence])
    end

    it "handles nil categories" do
      result = described_class.new(result: raw_result, categories: nil)
      expect(result.filter_categories).to be_nil
    end
  end

  describe "#flagged?" do
    context "when raw result is not flagged" do
      let(:unflagged_result) do
        double("UnflaggedResult", flagged?: false)
      end

      it "returns false" do
        result = described_class.new(result: unflagged_result)
        expect(result.flagged?).to be false
      end
    end

    context "when no threshold or category filter" do
      it "returns true if raw result is flagged" do
        result = described_class.new(result: raw_result)
        expect(result.flagged?).to be true
      end
    end

    context "with threshold filter" do
      it "returns true when max score meets threshold" do
        result = described_class.new(result: raw_result, threshold: 0.8)
        expect(result.flagged?).to be true
      end

      it "returns false when max score is below threshold" do
        result = described_class.new(result: raw_result, threshold: 0.9)
        expect(result.flagged?).to be false
      end
    end

    context "with category filter" do
      it "returns true when flagged category matches filter" do
        result = described_class.new(result: raw_result, categories: [:hate])
        expect(result.flagged?).to be true
      end

      it "returns false when flagged categories don't match filter" do
        result = described_class.new(result: raw_result, categories: [:sexual])
        expect(result.flagged?).to be false
      end
    end

    context "with both threshold and category filters" do
      it "returns true when both conditions met" do
        result = described_class.new(result: raw_result, threshold: 0.8, categories: [:hate])
        expect(result.flagged?).to be true
      end

      it "returns false when threshold not met" do
        result = described_class.new(result: raw_result, threshold: 0.9, categories: [:hate])
        expect(result.flagged?).to be false
      end

      it "returns false when category not matched" do
        result = described_class.new(result: raw_result, threshold: 0.5, categories: [:sexual])
        expect(result.flagged?).to be false
      end
    end
  end

  describe "#passed?" do
    it "returns true when not flagged" do
      result = described_class.new(result: raw_result, threshold: 0.9)
      expect(result.passed?).to be true
    end

    it "returns false when flagged" do
      result = described_class.new(result: raw_result)
      expect(result.passed?).to be false
    end
  end

  describe "#flagged_categories" do
    context "without category filter" do
      it "returns all flagged categories from raw result" do
        result = described_class.new(result: raw_result)
        expect(result.flagged_categories).to eq(["hate", "violence"])
      end
    end

    context "with category filter" do
      it "returns only categories matching the filter" do
        result = described_class.new(result: raw_result, categories: [:hate])
        expect(result.flagged_categories).to eq(["hate"])
      end

      it "normalizes category names for comparison" do
        raw_with_special_categories = double(
          "RawResult",
          flagged?: true,
          flagged_categories: ["hate/speech", "sexual-content"],
          category_scores: { "hate/speech" => 0.9 }
        )
        result = described_class.new(
          result: raw_with_special_categories,
          categories: [:hate_speech]
        )
        expect(result.flagged_categories).to eq(["hate/speech"])
      end

      it "returns empty array when no categories match filter" do
        result = described_class.new(result: raw_result, categories: [:harassment])
        expect(result.flagged_categories).to eq([])
      end
    end

    context "when raw result has nil flagged_categories" do
      it "returns empty array" do
        raw_nil_categories = double(
          "RawResult",
          flagged?: true,
          flagged_categories: nil,
          category_scores: {}
        )
        result = described_class.new(result: raw_nil_categories)
        expect(result.flagged_categories).to eq([])
      end
    end
  end

  describe "#category_scores" do
    it "returns category scores from raw result" do
      result = described_class.new(result: raw_result)
      expect(result.category_scores).to eq({
        "hate" => 0.85,
        "violence" => 0.6,
        "sexual" => 0.1
      })
    end

    it "returns empty hash when raw result has nil scores" do
      raw_nil_scores = double("RawResult", category_scores: nil)
      result = described_class.new(result: raw_nil_scores)
      expect(result.category_scores).to eq({})
    end
  end

  describe "#id" do
    it "returns the raw result id" do
      result = described_class.new(result: raw_result)
      expect(result.id).to eq("modr-123")
    end
  end

  describe "#model" do
    it "returns the raw result model" do
      result = described_class.new(result: raw_result)
      expect(result.model).to eq("text-moderation-007")
    end
  end

  describe "#max_score" do
    it "returns the maximum category score" do
      result = described_class.new(result: raw_result)
      expect(result.max_score).to eq(0.85)
    end

    it "returns 0.0 when no scores exist" do
      raw_no_scores = double("RawResult", category_scores: {})
      result = described_class.new(result: raw_no_scores)
      expect(result.max_score).to eq(0.0)
    end

    it "returns 0.0 when category_scores is nil" do
      raw_nil_scores = double("RawResult", category_scores: nil)
      result = described_class.new(result: raw_nil_scores)
      expect(result.max_score).to eq(0.0)
    end
  end

  describe "#raw_flagged?" do
    it "returns true when raw result is flagged" do
      result = described_class.new(result: raw_result)
      expect(result.raw_flagged?).to be true
    end

    it "returns false when raw result is not flagged" do
      unflagged = double("RawResult", flagged?: false)
      result = described_class.new(result: unflagged)
      expect(result.raw_flagged?).to be false
    end
  end

  describe "#to_h" do
    it "returns all attributes as a hash" do
      result = described_class.new(
        result: raw_result,
        threshold: 0.8,
        categories: [:hate]
      )

      hash = result.to_h

      expect(hash[:flagged]).to be true
      expect(hash[:raw_flagged]).to be true
      expect(hash[:flagged_categories]).to eq(["hate"])
      expect(hash[:category_scores]).to eq({ "hate" => 0.85, "violence" => 0.6, "sexual" => 0.1 })
      expect(hash[:max_score]).to eq(0.85)
      expect(hash[:threshold]).to eq(0.8)
      expect(hash[:filter_categories]).to eq([:hate])
      expect(hash[:model]).to eq("text-moderation-007")
      expect(hash[:id]).to eq("modr-123")
    end
  end

  describe "category normalization" do
    it "normalizes slashes to underscores" do
      raw = double(
        "RawResult",
        flagged?: true,
        flagged_categories: ["hate/speech", "self-harm/intent"],
        category_scores: { "hate/speech" => 0.9 }
      )
      result = described_class.new(result: raw, categories: [:hate_speech, :self_harm_intent])
      expect(result.flagged_categories).to contain_exactly("hate/speech", "self-harm/intent")
    end

    it "normalizes dashes to underscores" do
      raw = double(
        "RawResult",
        flagged?: true,
        flagged_categories: ["sexual-content"],
        category_scores: { "sexual-content" => 0.9 }
      )
      result = described_class.new(result: raw, categories: [:sexual_content])
      expect(result.flagged_categories).to eq(["sexual-content"])
    end

    it "handles case-insensitive comparison" do
      raw = double(
        "RawResult",
        flagged?: true,
        flagged_categories: ["HATE", "Violence"],
        category_scores: { "HATE" => 0.9 }
      )
      result = described_class.new(result: raw, categories: [:hate, :violence])
      expect(result.flagged_categories).to contain_exactly("HATE", "Violence")
    end
  end
end
