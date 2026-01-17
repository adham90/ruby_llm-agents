# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::FallbackRouting do
  let(:primary_model) { "gpt-4o" }
  let(:fallback_models) { ["gpt-4o-mini", "claude-3-haiku"] }

  subject(:routing) { described_class.new(primary_model, fallback_models: fallback_models) }

  describe "#initialize" do
    it "stores all models in order" do
      expect(routing.models).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end

    it "removes duplicate models" do
      routing = described_class.new("gpt-4o", fallback_models: ["gpt-4o", "gpt-4o-mini"])
      expect(routing.models).to eq(["gpt-4o", "gpt-4o-mini"])
    end

    context "with empty fallback models" do
      subject(:routing) { described_class.new(primary_model, fallback_models: []) }

      it "only contains primary model" do
        expect(routing.models).to eq(["gpt-4o"])
      end
    end

    context "with nil fallback models" do
      it "handles nil gracefully" do
        # Splat of nil becomes nothing
        routing = described_class.new(primary_model, fallback_models: nil)
        expect(routing.models).to include(primary_model)
      end
    end
  end

  describe "#current_model" do
    it "returns the first model initially" do
      expect(routing.current_model).to eq("gpt-4o")
    end

    it "returns nil when exhausted" do
      3.times { routing.advance! }
      expect(routing.current_model).to be_nil
    end
  end

  describe "#advance!" do
    it "moves to the next model" do
      routing.advance!
      expect(routing.current_model).to eq("gpt-4o-mini")
    end

    it "returns the new current model" do
      result = routing.advance!
      expect(result).to eq("gpt-4o-mini")
    end

    it "advances through all models in order" do
      expect(routing.current_model).to eq("gpt-4o")
      routing.advance!
      expect(routing.current_model).to eq("gpt-4o-mini")
      routing.advance!
      expect(routing.current_model).to eq("claude-3-haiku")
    end

    it "returns nil after exhausting all models" do
      3.times { routing.advance! }
      expect(routing.advance!).to be_nil
    end

    it "can advance beyond exhaustion" do
      10.times { routing.advance! }
      expect(routing.current_model).to be_nil
      expect(routing.exhausted?).to be true
    end
  end

  describe "#has_more?" do
    it "returns true when more models available" do
      expect(routing.has_more?).to be true
    end

    it "returns true when on second-to-last model" do
      routing.advance!
      expect(routing.has_more?).to be true
    end

    it "returns false when on last model" do
      2.times { routing.advance! }
      expect(routing.has_more?).to be false
    end

    it "returns false when exhausted" do
      3.times { routing.advance! }
      expect(routing.has_more?).to be false
    end

    context "with single model" do
      subject(:routing) { described_class.new(primary_model, fallback_models: []) }

      it "returns false initially" do
        expect(routing.has_more?).to be false
      end
    end
  end

  describe "#exhausted?" do
    it "returns false initially" do
      expect(routing.exhausted?).to be false
    end

    it "returns false while models remain" do
      routing.advance!
      expect(routing.exhausted?).to be false
      routing.advance!
      expect(routing.exhausted?).to be false
    end

    it "returns true after all models tried" do
      3.times { routing.advance! }
      expect(routing.exhausted?).to be true
    end

    context "with single model" do
      subject(:routing) { described_class.new(primary_model, fallback_models: []) }

      it "returns false initially" do
        expect(routing.exhausted?).to be false
      end

      it "returns true after one advance" do
        routing.advance!
        expect(routing.exhausted?).to be true
      end
    end
  end

  describe "#reset!" do
    before { 2.times { routing.advance! } }

    it "returns to the first model" do
      routing.reset!
      expect(routing.current_model).to eq("gpt-4o")
    end

    it "clears exhausted state" do
      3.times { routing.advance! }
      expect(routing.exhausted?).to be true

      routing.reset!
      expect(routing.exhausted?).to be false
    end

    it "allows iterating through models again" do
      routing.reset!
      models = []
      until routing.exhausted?
        models << routing.current_model
        routing.advance!
      end

      expect(models).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end
  end

  describe "#tried_models" do
    it "returns only the first model initially" do
      expect(routing.tried_models).to eq(["gpt-4o"])
    end

    it "includes tried models after advancing" do
      routing.advance!
      expect(routing.tried_models).to eq(["gpt-4o", "gpt-4o-mini"])
    end

    it "includes all models when exhausted" do
      3.times { routing.advance! }
      expect(routing.tried_models).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end

    it "resets with reset!" do
      2.times { routing.advance! }
      routing.reset!
      expect(routing.tried_models).to eq(["gpt-4o"])
    end
  end

  describe "edge cases" do
    context "with duplicate primary in fallbacks" do
      subject(:routing) do
        described_class.new("gpt-4o", fallback_models: ["gpt-4o", "gpt-4o-mini", "gpt-4o"])
      end

      it "deduplicates models" do
        expect(routing.models).to eq(["gpt-4o", "gpt-4o-mini"])
      end
    end

    context "with many fallback models" do
      let(:fallback_models) { (1..100).map { |i| "model-#{i}" } }

      it "handles large fallback chains" do
        expect(routing.models.length).to eq(101)

        100.times { routing.advance! }
        expect(routing.current_model).to eq("model-100")
        expect(routing.exhausted?).to be false

        routing.advance!
        expect(routing.exhausted?).to be true
      end
    end

    context "with empty string model" do
      subject(:routing) { described_class.new("", fallback_models: ["gpt-4o"]) }

      it "includes empty string as a model" do
        expect(routing.models).to eq(["", "gpt-4o"])
      end
    end
  end

  describe "iteration pattern" do
    it "supports common iteration pattern" do
      models_tried = []

      until routing.exhausted?
        models_tried << routing.current_model
        routing.advance!
      end

      expect(models_tried).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end
  end
end
