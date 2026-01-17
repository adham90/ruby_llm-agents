# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::BreakerManager do
  let(:agent_type) { "TestAgent" }
  let(:config) { { errors: 3, within: 60, cooldown: 30 } }
  let(:tenant_id) { nil }

  subject(:manager) do
    described_class.new(agent_type, config: config, tenant_id: tenant_id)
  end

  # Clear cache before each test to ensure isolation
  before do
    Rails.cache.clear
  end

  describe "#initialize" do
    it "stores agent_type" do
      expect(manager.instance_variable_get(:@agent_type)).to eq("TestAgent")
    end

    it "stores config" do
      expect(manager.instance_variable_get(:@config)).to eq(config)
    end

    it "initializes empty breakers hash" do
      expect(manager.instance_variable_get(:@breakers)).to eq({})
    end

    context "with tenant_id" do
      let(:tenant_id) { "tenant-123" }

      it "stores tenant_id" do
        expect(manager.instance_variable_get(:@tenant_id)).to eq("tenant-123")
      end
    end
  end

  describe "#for_model" do
    context "without config" do
      let(:config) { nil }

      it "returns nil" do
        expect(manager.for_model("gpt-4o")).to be_nil
      end
    end

    context "with config" do
      it "returns a circuit breaker" do
        breaker = manager.for_model("gpt-4o")
        # CircuitBreaker is in RubyLLM::Agents namespace, not Reliability
        expect(breaker).to be_a(RubyLLM::Agents::CircuitBreaker)
      end

      it "caches circuit breakers per model" do
        breaker1 = manager.for_model("gpt-4o")
        breaker2 = manager.for_model("gpt-4o")
        expect(breaker1).to be(breaker2)
      end

      it "creates separate breakers for different models" do
        breaker1 = manager.for_model("gpt-4o")
        breaker2 = manager.for_model("claude-3")
        expect(breaker1).not_to be(breaker2)
      end

      it "passes agent_type to circuit breaker" do
        # CircuitBreaker is in RubyLLM::Agents namespace
        expect(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with(agent_type, "gpt-4o", config, tenant_id: nil)
          .and_call_original

        manager.for_model("gpt-4o")
      end

      context "with tenant_id" do
        let(:tenant_id) { "tenant-123" }

        it "passes tenant_id to circuit breaker" do
          expect(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
            .with(agent_type, "gpt-4o", config, tenant_id: "tenant-123")
            .and_call_original

          manager.for_model("gpt-4o")
        end
      end
    end
  end

  describe "#open?" do
    context "without config" do
      let(:config) { nil }

      it "returns false" do
        expect(manager.open?("gpt-4o")).to be false
      end
    end

    context "with config" do
      it "returns false initially" do
        expect(manager.open?("gpt-4o")).to be false
      end

      it "returns true when circuit is open" do
        breaker = manager.for_model("gpt-4o")
        allow(breaker).to receive(:open?).and_return(true)

        expect(manager.open?("gpt-4o")).to be true
      end

      it "delegates to the circuit breaker" do
        breaker = manager.for_model("gpt-4o")
        expect(breaker).to receive(:open?).and_return(false)

        manager.open?("gpt-4o")
      end
    end
  end

  describe "#record_success!" do
    context "without config" do
      let(:config) { nil }

      it "does nothing (no error)" do
        expect { manager.record_success!("gpt-4o") }.not_to raise_error
      end
    end

    context "with config" do
      it "delegates to the circuit breaker" do
        breaker = manager.for_model("gpt-4o")
        expect(breaker).to receive(:record_success!)

        manager.record_success!("gpt-4o")
      end

      it "creates breaker if not exists" do
        expect(manager.instance_variable_get(:@breakers)).to be_empty
        manager.record_success!("gpt-4o")
        expect(manager.instance_variable_get(:@breakers)).to have_key("gpt-4o")
      end
    end
  end

  describe "#record_failure!" do
    context "without config" do
      let(:config) { nil }

      it "returns false" do
        expect(manager.record_failure!("gpt-4o")).to be false
      end
    end

    context "with config" do
      it "delegates to the circuit breaker" do
        breaker = manager.for_model("gpt-4o")
        expect(breaker).to receive(:record_failure!)

        manager.record_failure!("gpt-4o")
      end

      it "returns true if breaker becomes open" do
        breaker = manager.for_model("gpt-4o")
        allow(breaker).to receive(:record_failure!)
        allow(breaker).to receive(:open?).and_return(true)

        expect(manager.record_failure!("gpt-4o")).to be true
      end

      it "returns false if breaker stays closed" do
        breaker = manager.for_model("gpt-4o")
        allow(breaker).to receive(:record_failure!)
        allow(breaker).to receive(:open?).and_return(false)

        expect(manager.record_failure!("gpt-4o")).to be false
      end
    end
  end

  describe "#enabled?" do
    context "with config" do
      it "returns true" do
        expect(manager.enabled?).to be true
      end
    end

    context "without config" do
      let(:config) { nil }

      it "returns false" do
        expect(manager.enabled?).to be false
      end
    end

    context "with empty config" do
      let(:config) { {} }

      # Empty hash is blank? == true in Rails, so present? == false
      it "returns false (empty hash is not present)" do
        expect({}.present?).to be false
        expect(manager.enabled?).to be false
      end
    end
  end

  describe "multi-model isolation" do
    # Skip integration tests that require actual cache operations
    # as they need proper Rails cache setup
    it "maintains separate breakers per model" do
      breaker1 = manager.for_model("gpt-4o")
      breaker2 = manager.for_model("claude-3")

      # Verify they are different objects
      expect(breaker1).not_to equal(breaker2)
      expect(breaker1.model_id).to eq("gpt-4o")
      expect(breaker2.model_id).to eq("claude-3")
    end

    it "tracks successes independently per model" do
      # Get both breakers
      manager.for_model("gpt-4o")
      manager.for_model("claude-3")

      # Record success on one model
      manager.record_success!("gpt-4o")

      # Other model should have its own state
      expect { manager.record_success!("claude-3") }.not_to raise_error
    end
  end

  describe "integration with CircuitBreaker" do
    # These tests require a working Rails cache with increment support
    # For unit tests, we mock the circuit breaker behavior
    it "opens circuit after threshold failures" do
      breaker = manager.for_model("gpt-4o")
      allow(breaker).to receive(:record_failure!)
      allow(breaker).to receive(:open?).and_return(false, false, true)

      3.times { manager.record_failure!("gpt-4o") }

      expect(manager.open?("gpt-4o")).to be true
    end

    it "resets on success" do
      breaker = manager.for_model("gpt-4o")
      allow(breaker).to receive(:record_failure!)
      allow(breaker).to receive(:record_success!)
      allow(breaker).to receive(:open?).and_return(false)

      2.times { manager.record_failure!("gpt-4o") }
      manager.record_success!("gpt-4o")

      expect(manager.open?("gpt-4o")).to be false
    end
  end

  describe "edge cases" do
    context "with empty string model_id" do
      it "handles empty string model" do
        expect { manager.for_model("") }.not_to raise_error
        expect(manager.open?("")).to be false
      end
    end

    context "with nil model_id" do
      it "handles nil model" do
        expect { manager.for_model(nil) }.not_to raise_error
      end
    end
  end
end
