# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::CircuitBreaker do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
    cache_store.clear
  end

  describe "#initialize" do
    it "accepts positional arguments and keyword options" do
      breaker = described_class.new("TestAgent", "gpt-4o", errors: 5, within: 30, cooldown: 120)

      expect(breaker.agent_type).to eq("TestAgent")
      expect(breaker.model_id).to eq("gpt-4o")
      expect(breaker.errors_threshold).to eq(5)
      expect(breaker.window_seconds).to eq(30)
      expect(breaker.cooldown_seconds).to eq(120)
    end

    it "uses defaults for optional parameters" do
      breaker = described_class.new("TestAgent", "gpt-4o")

      expect(breaker.errors_threshold).to eq(10)
      expect(breaker.window_seconds).to eq(60)
      expect(breaker.cooldown_seconds).to eq(300)
    end
  end

  describe ".from_config" do
    it "creates a breaker from config hash" do
      config = { errors: 5, within: 30, cooldown: 120 }
      breaker = described_class.from_config("TestAgent", "gpt-4o", config)

      expect(breaker.errors_threshold).to eq(5)
      expect(breaker.window_seconds).to eq(30)
      expect(breaker.cooldown_seconds).to eq(120)
    end

    it "returns nil for non-hash config" do
      expect(described_class.from_config("TestAgent", "gpt-4o", nil)).to be_nil
      expect(described_class.from_config("TestAgent", "gpt-4o", "invalid")).to be_nil
    end
  end

  describe "#open?" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 3) }

    it "returns false when no failures recorded" do
      expect(breaker.open?).to be false
    end

    it "returns false when failures below threshold" do
      2.times { breaker.record_failure! }
      expect(breaker.open?).to be false
    end

    it "returns true after threshold exceeded" do
      3.times { breaker.record_failure! }
      expect(breaker.open?).to be true
    end
  end

  describe "#record_failure!" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 3, cooldown: 60) }

    it "increments failure count" do
      expect { breaker.record_failure! }.to change { breaker.failure_count }.from(0).to(1)
    end

    it "opens the breaker at threshold" do
      2.times { breaker.record_failure! }
      expect(breaker.open?).to be false

      breaker.record_failure!
      expect(breaker.open?).to be true
    end

    it "returns true when breaker opens" do
      2.times { breaker.record_failure! }
      expect(breaker.record_failure!).to be true
    end

    it "returns false when breaker already open" do
      3.times { breaker.record_failure! }
      expect(breaker.record_failure!).to be true # already open
    end
  end

  describe "#record_success!" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 5) }

    it "resets failure count by default" do
      3.times { breaker.record_failure! }
      expect(breaker.failure_count).to eq(3)

      breaker.record_success!
      expect(breaker.failure_count).to eq(0)
    end

    it "preserves failure count when reset_counter: false" do
      3.times { breaker.record_failure! }

      breaker.record_success!(reset_counter: false)
      expect(breaker.failure_count).to eq(3)
    end
  end

  describe "#reset!" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 3) }

    it "clears open state and failure count" do
      3.times { breaker.record_failure! }
      expect(breaker.open?).to be true
      expect(breaker.failure_count).to be > 0

      breaker.reset!
      expect(breaker.open?).to be false
      expect(breaker.failure_count).to eq(0)
    end
  end

  describe "#failure_count" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o") }

    it "returns 0 when no failures" do
      expect(breaker.failure_count).to eq(0)
    end

    it "returns current failure count" do
      5.times { breaker.record_failure! }
      expect(breaker.failure_count).to eq(5)
    end
  end

  describe "#status" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 5, within: 30, cooldown: 120) }

    it "returns status hash" do
      2.times { breaker.record_failure! }
      status = breaker.status

      expect(status[:agent_type]).to eq("TestAgent")
      expect(status[:model_id]).to eq("gpt-4o")
      expect(status[:open]).to be false
      expect(status[:failure_count]).to eq(2)
      expect(status[:errors_threshold]).to eq(5)
      expect(status[:window_seconds]).to eq(30)
      expect(status[:cooldown_seconds]).to eq(120)
    end
  end

  describe "isolation between agents and models" do
    it "isolates breakers per agent-model combination" do
      breaker1 = described_class.new("Agent1", "gpt-4o", errors: 2)
      breaker2 = described_class.new("Agent1", "claude-3", errors: 2)
      breaker3 = described_class.new("Agent2", "gpt-4o", errors: 2)

      2.times { breaker1.record_failure! }

      expect(breaker1.open?).to be true
      expect(breaker2.open?).to be false
      expect(breaker3.open?).to be false
    end
  end

  describe "alerts" do
    let(:breaker) { described_class.new("TestAgent", "gpt-4o", errors: 2) }

    it "fires alert when breaker opens" do
      expect(RubyLLM::Agents::AlertManager).to receive(:notify).with(:breaker_open, hash_including(
        agent_type: "TestAgent",
        model_id: "gpt-4o"
      ))

      2.times { breaker.record_failure! }
    end
  end
end
