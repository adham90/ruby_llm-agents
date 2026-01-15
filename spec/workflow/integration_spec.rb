# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Integration" do
  # Silence deprecation warnings for tests
  before do
    RubyLLM::Agents::Deprecations.silenced = true
  end

  after do
    RubyLLM::Agents::Deprecations.silenced = false
  end

  describe "Reliability module classes" do
    describe RubyLLM::Agents::Reliability::RetryStrategy do
      it "calculates exponential backoff correctly" do
        strategy = described_class.new(
          max: 3,
          backoff: :exponential,
          base: 1.0,
          max_delay: 10.0
        )

        # First attempt: base * 2^0 = 1.0 (+ jitter)
        delay0 = strategy.delay_for(0)
        expect(delay0).to be >= 1.0
        expect(delay0).to be < 1.5

        # Second attempt: base * 2^1 = 2.0 (+ jitter)
        delay1 = strategy.delay_for(1)
        expect(delay1).to be >= 2.0
        expect(delay1).to be < 3.0

        # Third attempt: base * 2^2 = 4.0 (+ jitter)
        delay2 = strategy.delay_for(2)
        expect(delay2).to be >= 4.0
        expect(delay2).to be < 6.0
      end

      it "respects max_delay cap" do
        strategy = described_class.new(
          max: 10,
          backoff: :exponential,
          base: 1.0,
          max_delay: 5.0
        )

        # 2^5 = 32, but should be capped at 5.0
        delay = strategy.delay_for(5)
        expect(delay).to be >= 5.0
        expect(delay).to be < 7.5 # 5.0 + 50% jitter
      end

      it "constant backoff returns same delay" do
        strategy = described_class.new(
          max: 3,
          backoff: :constant,
          base: 2.0,
          max_delay: 10.0
        )

        # All attempts should have base delay (+ jitter)
        10.times do |i|
          delay = strategy.delay_for(i)
          expect(delay).to be >= 2.0
          expect(delay).to be < 3.0
        end
      end

      it "should_retry? returns correct values" do
        strategy = described_class.new(max: 2)

        expect(strategy.should_retry?(0)).to be true
        expect(strategy.should_retry?(1)).to be true
        expect(strategy.should_retry?(2)).to be false
        expect(strategy.should_retry?(3)).to be false
      end
    end

    describe RubyLLM::Agents::Reliability::FallbackRouting do
      it "iterates through models in order" do
        routing = described_class.new("gpt-4o", fallback_models: ["gpt-4o-mini", "gpt-3.5-turbo"])

        expect(routing.current_model).to eq("gpt-4o")

        routing.advance!
        expect(routing.current_model).to eq("gpt-4o-mini")

        routing.advance!
        expect(routing.current_model).to eq("gpt-3.5-turbo")

        routing.advance!
        expect(routing.current_model).to be_nil
        expect(routing.exhausted?).to be true
      end

      it "deduplicates models" do
        routing = described_class.new("gpt-4o", fallback_models: ["gpt-4o", "gpt-4o-mini"])

        expect(routing.models).to eq(["gpt-4o", "gpt-4o-mini"])
      end

      it "has_more? returns correct values" do
        routing = described_class.new("gpt-4o", fallback_models: ["gpt-4o-mini"])

        expect(routing.has_more?).to be true

        routing.advance!
        expect(routing.has_more?).to be false
      end

      it "reset! returns to first model" do
        routing = described_class.new("gpt-4o", fallback_models: ["gpt-4o-mini"])

        routing.advance!
        expect(routing.current_model).to eq("gpt-4o-mini")

        routing.reset!
        expect(routing.current_model).to eq("gpt-4o")
      end
    end

    describe RubyLLM::Agents::Reliability::ExecutionConstraints do
      it "tracks elapsed time" do
        constraints = described_class.new(total_timeout: 10)

        sleep(0.1)

        expect(constraints.elapsed).to be >= 0.1
      end

      it "timeout_exceeded? returns false when within timeout" do
        constraints = described_class.new(total_timeout: 10)

        expect(constraints.timeout_exceeded?).to be false
      end

      it "timeout_exceeded? returns true when past deadline" do
        constraints = described_class.new(total_timeout: 0.1)

        sleep(0.15)

        expect(constraints.timeout_exceeded?).to be true
      end

      it "enforce_timeout! raises TotalTimeoutError when exceeded" do
        constraints = described_class.new(total_timeout: 0.1)

        sleep(0.15)

        expect { constraints.enforce_timeout! }.to raise_error(
          RubyLLM::Agents::Reliability::TotalTimeoutError
        )
      end

      it "remaining returns correct time" do
        constraints = described_class.new(total_timeout: 10)

        expect(constraints.remaining).to be > 9.5
        expect(constraints.remaining).to be <= 10.0
      end

      it "remaining returns nil when no timeout" do
        constraints = described_class.new(total_timeout: nil)

        expect(constraints.remaining).to be_nil
      end
    end

    describe RubyLLM::Agents::Reliability::BreakerManager do
      let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

      before do
        allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
        allow(RubyLLM::Agents.configuration).to receive(:alerts_enabled?).and_return(false)
        cache_store.clear
      end

      it "returns nil when not configured" do
        manager = described_class.new("TestAgent", config: nil)

        expect(manager.for_model("gpt-4o")).to be_nil
        expect(manager.open?("gpt-4o")).to be false
      end

      it "creates breakers when configured" do
        manager = described_class.new("TestAgent", config: { errors: 3, within: 60, cooldown: 300 })

        expect(manager.for_model("gpt-4o")).to be_a(RubyLLM::Agents::CircuitBreaker)
      end

      it "tracks failures and opens breaker" do
        manager = described_class.new("TestAgent", config: { errors: 2, within: 60, cooldown: 300 })

        2.times { manager.record_failure!("gpt-4o") }

        expect(manager.open?("gpt-4o")).to be true
      end

      it "resets on success" do
        manager = described_class.new("TestAgent", config: { errors: 3, within: 60, cooldown: 300 })

        2.times { manager.record_failure!("gpt-4o") }
        manager.record_success!("gpt-4o")

        # Should not be open, and counter should be reset
        expect(manager.open?("gpt-4o")).to be false
      end
    end
  end

  describe "type validation" do
    it "validates Integer type" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :limit, type: Integer

        def user_prompt
          "test"
        end
      end

      expect { klass.new(limit: "not an integer") }.to raise_error(
        ArgumentError,
        /expected Integer for :limit, got String/
      )
    end

    it "validates String type" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :name, type: String

        def user_prompt
          "test"
        end
      end

      expect { klass.new(name: 123) }.to raise_error(
        ArgumentError,
        /expected String for :name, got Integer/
      )
    end

    it "validates Array type" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :tags, type: Array

        def user_prompt
          "test"
        end
      end

      expect { klass.new(tags: "not an array") }.to raise_error(
        ArgumentError,
        /expected Array for :tags, got String/
      )
    end

    it "allows nil when type is specified" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :optional, type: String

        def user_prompt
          "test"
        end
      end

      # Should not raise - nil is allowed
      expect { klass.new(optional: nil) }.not_to raise_error
    end

    it "allows any type when type not specified" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :data

        def user_prompt
          "test"
        end
      end

      # Should not raise - no type restriction
      expect { klass.new(data: "string") }.not_to raise_error
      expect { klass.new(data: 123) }.not_to raise_error
      expect { klass.new(data: [1, 2, 3]) }.not_to raise_error
    end

    it "validates type with required param" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :query, required: true, type: String

        def user_prompt
          query
        end
      end

      expect { klass.new(query: 123) }.to raise_error(
        ArgumentError,
        /expected String for :query, got Integer/
      )

      expect { klass.new(query: "valid") }.not_to raise_error
    end
  end
end
