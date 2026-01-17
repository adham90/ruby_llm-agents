# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::ExecutionConstraints do
  include ActiveSupport::Testing::TimeHelpers

  describe "#initialize" do
    context "with total_timeout" do
      subject(:constraints) { described_class.new(total_timeout: 30) }

      it "stores the total_timeout" do
        expect(constraints.total_timeout).to eq(30)
      end

      it "records started_at" do
        travel_to Time.current do
          constraints = described_class.new(total_timeout: 30)
          expect(constraints.started_at).to be_within(0.1).of(Time.current)
        end
      end

      it "calculates deadline from started_at and timeout" do
        travel_to Time.current do
          constraints = described_class.new(total_timeout: 30)
          expect(constraints.deadline).to be_within(0.1).of(Time.current + 30)
        end
      end
    end

    context "without total_timeout" do
      subject(:constraints) { described_class.new }

      it "has nil total_timeout" do
        expect(constraints.total_timeout).to be_nil
      end

      it "has nil deadline" do
        expect(constraints.deadline).to be_nil
      end

      it "still records started_at" do
        expect(constraints.started_at).to be_present
      end
    end
  end

  describe "#timeout_exceeded?" do
    context "with timeout configured" do
      it "returns false before deadline" do
        constraints = described_class.new(total_timeout: 10)
        expect(constraints.timeout_exceeded?).to be false
      end

      it "returns true after deadline" do
        constraints = described_class.new(total_timeout: 1)
        travel 2.seconds do
          expect(constraints.timeout_exceeded?).to be true
        end
      end

      it "returns true when past deadline" do
        # Create constraints with 1 second timeout, wait past deadline
        constraints = described_class.new(total_timeout: 0.01)
        sleep(0.02) # Wait past the deadline
        expect(constraints.timeout_exceeded?).to be true
      end
    end

    context "without timeout configured" do
      it "returns falsey (nil deadline)" do
        constraints = described_class.new
        travel 1.hour do
          # Returns nil when no deadline (short-circuit evaluation)
          expect(constraints.timeout_exceeded?).to be_falsey
        end
      end
    end
  end

  describe "#elapsed" do
    it "returns elapsed time since start" do
      constraints = described_class.new
      sleep(0.05)
      expect(constraints.elapsed).to be >= 0.04
    end

    it "starts at zero" do
      constraints = described_class.new
      expect(constraints.elapsed).to be_within(0.1).of(0)
    end

    it "increases over time" do
      constraints = described_class.new
      elapsed1 = constraints.elapsed
      sleep(0.01)
      elapsed2 = constraints.elapsed
      expect(elapsed2).to be > elapsed1
    end
  end

  describe "#enforce_timeout!" do
    context "with timeout configured" do
      it "does nothing before deadline" do
        constraints = described_class.new(total_timeout: 10)
        expect { constraints.enforce_timeout! }.not_to raise_error
      end

      it "raises TotalTimeoutError after deadline" do
        constraints = described_class.new(total_timeout: 0.01)
        sleep(0.02)
        expect { constraints.enforce_timeout! }.to raise_error(
          RubyLLM::Agents::Reliability::TotalTimeoutError
        ) do |error|
          expect(error.timeout_seconds).to eq(0.01)
          expect(error.elapsed_seconds).to be >= 0.01
        end
      end
    end

    context "without timeout configured" do
      it "never raises" do
        constraints = described_class.new
        # Even with elapsed time, no timeout means no error
        sleep(0.01)
        expect { constraints.enforce_timeout! }.not_to raise_error
      end
    end
  end

  describe "#remaining" do
    context "with timeout configured" do
      it "returns remaining time before deadline" do
        constraints = described_class.new(total_timeout: 1.0)
        # Remaining should be close to total_timeout initially
        expect(constraints.remaining).to be_within(0.1).of(1.0)
        sleep(0.1)
        # Remaining should decrease
        expect(constraints.remaining).to be < 1.0
      end

      it "returns zero after deadline" do
        constraints = described_class.new(total_timeout: 0.01)
        sleep(0.02)
        expect(constraints.remaining).to eq(0)
      end

      it "never returns negative" do
        constraints = described_class.new(total_timeout: 0.01)
        sleep(0.05)
        expect(constraints.remaining).to be >= 0
      end

      it "equals total_timeout at start" do
        constraints = described_class.new(total_timeout: 10)
        expect(constraints.remaining).to be_within(0.1).of(10.0)
      end
    end

    context "without timeout configured" do
      subject(:constraints) { described_class.new }

      it "returns nil" do
        expect(constraints.remaining).to be_nil
      end
    end
  end

  describe "#has_timeout?" do
    context "with timeout configured" do
      subject(:constraints) { described_class.new(total_timeout: 30) }

      it "returns true" do
        expect(constraints.has_timeout?).to be true
      end
    end

    context "without timeout configured" do
      subject(:constraints) { described_class.new }

      it "returns false" do
        expect(constraints.has_timeout?).to be false
      end
    end

    context "with zero timeout" do
      subject(:constraints) { described_class.new(total_timeout: 0) }

      # In Rails, 0.present? actually returns true (only nil, false, empty string/array/hash are blank)
      it "returns true (0 is present in Rails)" do
        expect(0.present?).to be true
        expect(constraints.has_timeout?).to be true
      end
    end
  end

  describe "edge cases" do
    context "with very small timeout" do
      it "handles millisecond timeouts" do
        constraints = described_class.new(total_timeout: 0.001) # 1ms
        sleep(0.002)
        expect(constraints.timeout_exceeded?).to be true
      end
    end

    context "with very large timeout" do
      subject(:constraints) { described_class.new(total_timeout: 86400 * 365) }

      it "handles year-long timeouts" do
        expect(constraints.timeout_exceeded?).to be false
        expect(constraints.remaining).to be_within(1).of(86400 * 365)
      end
    end

    context "concurrent timing" do
      it "provides consistent state within same instant" do
        travel_to Time.current do
          constraints = described_class.new(total_timeout: 10)

          exceeded = constraints.timeout_exceeded?
          remaining = constraints.remaining
          elapsed = constraints.elapsed

          # All should be consistent at the same frozen time
          expect(exceeded).to be false
          expect(remaining + elapsed).to be_within(0.1).of(10.0)
        end
      end
    end
  end
end
