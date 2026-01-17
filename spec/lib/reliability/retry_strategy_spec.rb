# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::RetryStrategy do
  describe "#initialize" do
    context "with default values" do
      subject(:strategy) { described_class.new }

      it "has zero max retries" do
        expect(strategy.max).to eq(0)
      end

      it "uses exponential backoff" do
        expect(strategy.backoff).to eq(:exponential)
      end

      it "has 0.4s base delay" do
        expect(strategy.base).to eq(0.4)
      end

      it "has 3.0s max delay" do
        expect(strategy.max_delay).to eq(3.0)
      end

      it "has empty custom errors" do
        expect(strategy.custom_errors).to eq([])
      end
    end

    context "with custom values" do
      subject(:strategy) do
        described_class.new(
          max: 5,
          backoff: :constant,
          base: 1.0,
          max_delay: 10.0,
          on: [ArgumentError, RuntimeError]
        )
      end

      it "stores custom max" do
        expect(strategy.max).to eq(5)
      end

      it "stores custom backoff" do
        expect(strategy.backoff).to eq(:constant)
      end

      it "stores custom base" do
        expect(strategy.base).to eq(1.0)
      end

      it "stores custom max_delay" do
        expect(strategy.max_delay).to eq(10.0)
      end

      it "stores custom errors as array" do
        expect(strategy.custom_errors).to eq([ArgumentError, RuntimeError])
      end
    end

    context "with single custom error (not array)" do
      subject(:strategy) { described_class.new(on: ArgumentError) }

      it "converts to array" do
        expect(strategy.custom_errors).to eq([ArgumentError])
      end
    end
  end

  describe "#should_retry?" do
    context "with max: 3" do
      subject(:strategy) { described_class.new(max: 3) }

      it "returns true for attempts 0, 1, 2" do
        expect(strategy.should_retry?(0)).to be true
        expect(strategy.should_retry?(1)).to be true
        expect(strategy.should_retry?(2)).to be true
      end

      it "returns false for attempt 3 and beyond" do
        expect(strategy.should_retry?(3)).to be false
        expect(strategy.should_retry?(4)).to be false
        expect(strategy.should_retry?(10)).to be false
      end
    end

    context "with max: 0" do
      subject(:strategy) { described_class.new(max: 0) }

      it "never allows retries" do
        expect(strategy.should_retry?(0)).to be false
      end
    end

    context "with max: 1" do
      subject(:strategy) { described_class.new(max: 1) }

      it "allows exactly one retry" do
        expect(strategy.should_retry?(0)).to be true
        expect(strategy.should_retry?(1)).to be false
      end
    end
  end

  describe "#delay_for" do
    context "with exponential backoff" do
      subject(:strategy) do
        described_class.new(backoff: :exponential, base: 1.0, max_delay: 10.0)
      end

      it "calculates exponential delays" do
        # Stub rand to return 0 for predictable tests (no jitter)
        allow_any_instance_of(Object).to receive(:rand).and_return(0)

        expect(strategy.delay_for(0)).to eq(1.0)   # 1.0 * 2^0 = 1.0
        expect(strategy.delay_for(1)).to eq(2.0)   # 1.0 * 2^1 = 2.0
        expect(strategy.delay_for(2)).to eq(4.0)   # 1.0 * 2^2 = 4.0
        expect(strategy.delay_for(3)).to eq(8.0)   # 1.0 * 2^3 = 8.0
      end

      it "respects max_delay" do
        allow_any_instance_of(Object).to receive(:rand).and_return(0)

        expect(strategy.delay_for(10)).to eq(10.0) # Would be 1024, capped at 10
      end

      it "adds jitter up to 50% of base delay" do
        # With full jitter (rand returns 1.0), should add 50%
        allow_any_instance_of(Object).to receive(:rand).and_return(1.0)

        delay = strategy.delay_for(0)
        expect(delay).to eq(1.5) # 1.0 + (1.0 * 1.0 * 0.5) = 1.5
      end

      it "varies with jitter" do
        # Collect delays with varying random values
        delays = []
        [0, 0.25, 0.5, 0.75, 1.0].each do |rand_val|
          allow_any_instance_of(Object).to receive(:rand).and_return(rand_val)
          delays << strategy.delay_for(1)
        end

        expect(delays.uniq.size).to be > 1
        expect(delays.min).to eq(2.0)
        expect(delays.max).to eq(3.0) # 2.0 + 50% jitter
      end
    end

    context "with constant backoff" do
      subject(:strategy) do
        described_class.new(backoff: :constant, base: 2.0, max_delay: 10.0)
      end

      it "returns constant base delay plus jitter" do
        allow_any_instance_of(Object).to receive(:rand).and_return(0)

        expect(strategy.delay_for(0)).to eq(2.0)
        expect(strategy.delay_for(5)).to eq(2.0)
        expect(strategy.delay_for(100)).to eq(2.0)
      end

      it "ignores max_delay since constant never exceeds it" do
        strategy = described_class.new(backoff: :constant, base: 5.0, max_delay: 3.0)
        allow_any_instance_of(Object).to receive(:rand).and_return(0)

        # Constant backoff doesn't cap at max_delay
        expect(strategy.delay_for(0)).to eq(5.0)
      end
    end

    context "with unknown backoff" do
      subject(:strategy) do
        described_class.new(backoff: :unknown, base: 1.5, max_delay: 10.0)
      end

      it "falls back to base delay" do
        allow_any_instance_of(Object).to receive(:rand).and_return(0)

        expect(strategy.delay_for(0)).to eq(1.5)
        expect(strategy.delay_for(5)).to eq(1.5)
      end
    end
  end

  describe "#retryable?" do
    subject(:strategy) { described_class.new(on: [ArgumentError]) }

    it "returns true for default retryable errors" do
      expect(strategy.retryable?(Timeout::Error.new)).to be true
    end

    it "returns true for custom error classes" do
      expect(strategy.retryable?(ArgumentError.new("test"))).to be true
    end

    it "returns false for non-retryable errors" do
      expect(strategy.retryable?(NoMethodError.new)).to be false
    end

    it "returns true for subclasses of retryable errors" do
      expect(strategy.retryable?(Net::ReadTimeout.new)).to be true
    end

    it "delegates to Reliability.retryable_error?" do
      error = StandardError.new
      expect(RubyLLM::Agents::Reliability).to receive(:retryable_error?)
        .with(error, custom_errors: [ArgumentError])
        .and_return(true)

      strategy.retryable?(error)
    end
  end

  describe "#retryable_errors" do
    context "without custom errors" do
      subject(:strategy) { described_class.new }

      it "returns default retryable errors" do
        errors = strategy.retryable_errors
        expect(errors).to include(Timeout::Error)
      end
    end

    context "with custom errors" do
      subject(:strategy) { described_class.new(on: [ArgumentError, RuntimeError]) }

      it "includes both default and custom errors" do
        errors = strategy.retryable_errors
        expect(errors).to include(Timeout::Error)
        expect(errors).to include(ArgumentError)
        expect(errors).to include(RuntimeError)
      end
    end
  end

  describe "jitter behavior" do
    subject(:strategy) do
      described_class.new(backoff: :exponential, base: 1.0, max_delay: 100.0)
    end

    it "produces variable delays across multiple calls" do
      # Without stubbing rand, delays should vary
      delays = 20.times.map { strategy.delay_for(2) }

      # Should have variation due to jitter
      expect(delays.min).to be >= 4.0  # Base exponential delay
      expect(delays.max).to be <= 6.0  # Max with 50% jitter
      expect(delays.uniq.size).to be > 1
    end

    it "jitter range is 0% to 50% of base delay" do
      1000.times do
        delay = strategy.delay_for(0) # Base delay is 1.0
        expect(delay).to be >= 1.0
        expect(delay).to be <= 1.5
      end
    end
  end

  describe "edge cases" do
    context "with zero base delay" do
      subject(:strategy) do
        described_class.new(base: 0, max_delay: 10.0)
      end

      it "returns zero delay" do
        allow_any_instance_of(Object).to receive(:rand).and_return(0.5)
        expect(strategy.delay_for(0)).to eq(0)
      end
    end

    context "with very large attempt number" do
      subject(:strategy) do
        described_class.new(base: 0.1, max_delay: 5.0)
      end

      it "caps at max_delay" do
        allow_any_instance_of(Object).to receive(:rand).and_return(0)
        expect(strategy.delay_for(1000)).to eq(5.0)
      end
    end

    context "with negative attempt (invalid input)" do
      subject(:strategy) { described_class.new(max: 3) }

      it "treats as should retry" do
        expect(strategy.should_retry?(-1)).to be true
      end
    end
  end
end
