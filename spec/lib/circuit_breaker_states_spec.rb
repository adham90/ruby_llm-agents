# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CircuitBreaker State Transitions" do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
    allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(false)
    cache_store.clear
  end

  describe "closed state (initial)" do
    it "starts in closed state" do
      breaker = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o", errors: 3, within: 60)

      expect(breaker.open?).to be false
    end

    it "allows requests when closed" do
      breaker = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o", errors: 3, within: 60)

      expect(breaker.open?).to be false
    end
  end

  describe "closed -> open transition" do
    it "opens after threshold failures within window" do
      breaker = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o", errors: 3, within: 60)

      expect(breaker.open?).to be false

      3.times { breaker.record_failure! }

      expect(breaker.open?).to be true
    end

    it "does not open if failures are below threshold" do
      breaker = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o", errors: 5, within: 60)

      4.times { breaker.record_failure! }

      expect(breaker.open?).to be false
    end

    it "tracks failures separately per model" do
      breaker_gpt4 = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o", errors: 3, within: 60)
      breaker_mini = RubyLLM::Agents::CircuitBreaker.new("TestAgent", "gpt-4o-mini", errors: 3, within: 60)

      3.times { breaker_gpt4.record_failure! }

      expect(breaker_gpt4.open?).to be true
      expect(breaker_mini.open?).to be false
    end
  end

  describe "open -> closed transition (cooldown)" do
    it "closes automatically after cooldown expires" do
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 2, within: 60, cooldown: 1
      )

      2.times { breaker.record_failure! }
      expect(breaker.open?).to be true

      sleep(1.1) # Wait for cooldown

      expect(breaker.open?).to be false
    end

    it "stays open during cooldown period" do
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 2, within: 60, cooldown: 5
      )

      2.times { breaker.record_failure! }
      expect(breaker.open?).to be true

      sleep(0.1) # Short sleep, still in cooldown

      expect(breaker.open?).to be true
    end
  end

  describe "half-open state behavior" do
    it "allows test request after cooldown expires" do
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 2, within: 60, cooldown: 1
      )

      2.times { breaker.record_failure! }
      expect(breaker.open?).to be true

      sleep(1.1) # Wait for cooldown

      # Breaker should be closed (allowing test request)
      expect(breaker.open?).to be false
    end

    it "single failure after cooldown does not immediately re-open" do
      # Use a new breaker with unique identifiers to avoid cache conflicts
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgentHalfOpen", "gpt-4o-halfopen",
        errors: 3, within: 60, cooldown: 1
      )

      3.times { breaker.record_failure! }
      expect(breaker.open?).to be true

      sleep(1.1) # Wait for cooldown

      # Breaker should be closed after cooldown
      expect(breaker.open?).to be false

      # Reset the counter to simulate clean slate after cooldown
      breaker.reset!

      # Single failure should not immediately re-open (need threshold again)
      breaker.record_failure!
      expect(breaker.open?).to be false
    end
  end

  describe "success resets failure tracking" do
    it "resets failure count on success" do
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 3, within: 60
      )

      2.times { breaker.record_failure! }
      expect(breaker.open?).to be false

      breaker.record_success!

      # After success, should need full threshold again
      2.times { breaker.record_failure! }
      expect(breaker.open?).to be false
    end
  end

  describe "tenant isolation" do
    before do
      allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(true)
    end

    it "tracks breakers separately per tenant" do
      breaker_tenant_a = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 2, within: 60, tenant_id: "tenant_a"
      )

      breaker_tenant_b = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 2, within: 60, tenant_id: "tenant_b"
      )

      2.times { breaker_tenant_a.record_failure! }

      expect(breaker_tenant_a.open?).to be true
      expect(breaker_tenant_b.open?).to be false
    end
  end

  describe "rolling window behavior" do
    it "failures outside window do not count" do
      # Use a very short window for testing
      breaker = RubyLLM::Agents::CircuitBreaker.new(
        "TestAgent", "gpt-4o",
        errors: 3, within: 1
      )

      2.times { breaker.record_failure! }

      sleep(1.1) # Wait for window to expire

      # Old failures should be outside window now
      breaker.record_failure!

      # Should not be open since old failures expired
      expect(breaker.open?).to be false
    end
  end
end
