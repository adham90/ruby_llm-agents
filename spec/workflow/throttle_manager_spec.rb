# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::ThrottleManager do
  let(:manager) { described_class.new }

  describe "#throttle" do
    it "returns 0 on first call (no wait)" do
      waited = manager.throttle("test-key", 1.0)
      expect(waited).to eq(0)
    end

    it "waits on subsequent calls within duration" do
      manager.throttle("test-key", 0.1)

      start = Time.now
      waited = manager.throttle("test-key", 0.1)
      elapsed = Time.now - start

      expect(waited).to be > 0
      expect(elapsed).to be >= 0.05 # Allow tolerance
    end

    it "does not wait if duration has passed" do
      manager.throttle("test-key", 0.01)
      sleep(0.02)

      start = Time.now
      waited = manager.throttle("test-key", 0.01)
      elapsed = Time.now - start

      expect(waited).to eq(0)
      expect(elapsed).to be < 0.01
    end

    it "handles different keys independently" do
      manager.throttle("key-1", 0.5)

      # Second key should not wait
      waited = manager.throttle("key-2", 0.5)
      expect(waited).to eq(0)
    end

    it "normalizes duration to float" do
      # Integer duration
      manager.throttle("int-key", 1)
      expect(manager.throttle_remaining("int-key", 1)).to be > 0

      # Float duration
      manager.throttle("float-key", 0.1)
      expect(manager.throttle_remaining("float-key", 0.1)).to be > 0
    end

    it "is thread-safe" do
      results = Concurrent::Array.new

      threads = 5.times.map do
        Thread.new do
          result = manager.throttle("shared-key", 0.05)
          results << result
        end
      end
      threads.each(&:join)

      # At least one should have waited
      expect(results.count { |r| r > 0 }).to be >= 1
    end
  end

  describe "#throttle_remaining" do
    it "returns 0 for first call (no previous execution)" do
      remaining = manager.throttle_remaining("new-key", 1.0)
      expect(remaining).to eq(0)
    end

    it "returns remaining time after throttle call" do
      manager.throttle("test-key", 1.0)
      remaining = manager.throttle_remaining("test-key", 1.0)

      expect(remaining).to be > 0
      expect(remaining).to be <= 1.0
    end

    it "returns 0 after duration has passed" do
      manager.throttle("test-key", 0.01)
      sleep(0.02)

      remaining = manager.throttle_remaining("test-key", 0.01)
      expect(remaining).to eq(0)
    end

    it "does not update last_execution (non-destructive)" do
      manager.throttle("test-key", 1.0)

      # Multiple calls should return decreasing values
      first = manager.throttle_remaining("test-key", 1.0)
      sleep(0.01)
      second = manager.throttle_remaining("test-key", 1.0)

      expect(second).to be < first
    end
  end

  describe "#rate_limit" do
    it "allows calls within rate limit" do
      5.times do
        waited = manager.rate_limit("api", calls: 10, per: 1.0)
        expect(waited).to eq(0)
      end
    end

    it "returns wait time when rate limit exceeded" do
      # Exhaust the bucket quickly
      10.times { manager.rate_limit("api", calls: 10, per: 1.0) }

      # Next call should wait
      waited = manager.rate_limit("api", calls: 10, per: 1.0)
      expect(waited).to be > 0
    end

    it "refills tokens over time" do
      # Exhaust the bucket
      10.times { manager.rate_limit("api", calls: 10, per: 0.1) }

      # Wait for refill
      sleep(0.05)

      # Should have some tokens back
      waited = manager.rate_limit("api", calls: 10, per: 0.1)
      expect(waited).to be < 0.01
    end

    it "handles different keys independently" do
      # Exhaust one bucket
      10.times { manager.rate_limit("api-1", calls: 10, per: 1.0) }

      # Other bucket should be available
      waited = manager.rate_limit("api-2", calls: 10, per: 1.0)
      expect(waited).to eq(0)
    end
  end

  describe "#rate_limit_available?" do
    it "returns true when tokens are available" do
      available = manager.rate_limit_available?("api", calls: 10, per: 1.0)
      expect(available).to be true
    end

    it "returns false when bucket is empty" do
      # Exhaust the bucket
      10.times { manager.rate_limit("api", calls: 10, per: 10.0) }

      available = manager.rate_limit_available?("api", calls: 10, per: 10.0)
      expect(available).to be false
    end

    it "does not consume tokens (non-destructive)" do
      # Check availability twice
      first = manager.rate_limit_available?("api", calls: 10, per: 1.0)
      second = manager.rate_limit_available?("api", calls: 10, per: 1.0)

      expect(first).to be true
      expect(second).to be true

      # Actually consume tokens now
      10.times { manager.rate_limit("api", calls: 10, per: 10.0) }

      # Should now be unavailable
      third = manager.rate_limit_available?("api", calls: 10, per: 10.0)
      expect(third).to be false
    end
  end

  describe "#reset_throttle" do
    it "clears throttle state for a specific key" do
      manager.throttle("test-key", 1.0)
      expect(manager.throttle_remaining("test-key", 1.0)).to be > 0

      manager.reset_throttle("test-key")

      # Should be able to call immediately
      waited = manager.throttle("test-key", 1.0)
      expect(waited).to eq(0)
    end

    it "does not affect other keys" do
      manager.throttle("key-1", 1.0)
      manager.throttle("key-2", 1.0)

      manager.reset_throttle("key-1")

      # key-1 should be reset
      expect(manager.throttle_remaining("key-1", 1.0)).to eq(0)
      # key-2 should still be throttled
      expect(manager.throttle_remaining("key-2", 1.0)).to be > 0
    end
  end

  describe "#reset_rate_limit" do
    it "clears rate limit state for a specific key" do
      # Exhaust the bucket
      10.times { manager.rate_limit("api", calls: 10, per: 10.0) }
      expect(manager.rate_limit_available?("api", calls: 10, per: 10.0)).to be false

      manager.reset_rate_limit("api")

      # Should be available again
      expect(manager.rate_limit_available?("api", calls: 10, per: 10.0)).to be true
    end

    it "does not affect other keys" do
      # Exhaust both buckets
      10.times { manager.rate_limit("api-1", calls: 10, per: 10.0) }
      10.times { manager.rate_limit("api-2", calls: 10, per: 10.0) }

      manager.reset_rate_limit("api-1")

      # api-1 should be available
      expect(manager.rate_limit_available?("api-1", calls: 10, per: 10.0)).to be true
      # api-2 should still be exhausted
      expect(manager.rate_limit_available?("api-2", calls: 10, per: 10.0)).to be false
    end
  end

  describe "#reset_all!" do
    it "clears all throttle state" do
      manager.throttle("key-1", 1.0)
      manager.throttle("key-2", 1.0)

      manager.reset_all!

      expect(manager.throttle_remaining("key-1", 1.0)).to eq(0)
      expect(manager.throttle_remaining("key-2", 1.0)).to eq(0)
    end

    it "clears all rate limit state" do
      10.times { manager.rate_limit("api-1", calls: 10, per: 10.0) }
      10.times { manager.rate_limit("api-2", calls: 10, per: 10.0) }

      manager.reset_all!

      expect(manager.rate_limit_available?("api-1", calls: 10, per: 10.0)).to be true
      expect(manager.rate_limit_available?("api-2", calls: 10, per: 10.0)).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent throttle calls" do
      results = Concurrent::Array.new

      threads = 10.times.map do
        Thread.new do
          5.times do
            result = manager.throttle("concurrent-key", 0.01)
            results << result
          end
        end
      end
      threads.each(&:join)

      expect(results.size).to eq(50)
    end

    it "handles concurrent rate_limit calls" do
      results = Concurrent::Array.new

      threads = 5.times.map do
        Thread.new do
          10.times do
            result = manager.rate_limit("concurrent-api", calls: 50, per: 1.0)
            results << result
          end
        end
      end
      threads.each(&:join)

      expect(results.size).to eq(50)
    end
  end

  describe RubyLLM::Agents::Workflow::ThrottleManager::TokenBucket do
    describe "#initialize" do
      it "creates a bucket with specified capacity" do
        bucket = described_class.new(10, 1.0)
        expect(bucket.available?).to be true
      end
    end

    describe "#acquire" do
      it "returns 0 when tokens available" do
        bucket = described_class.new(10, 1.0)
        waited = bucket.acquire
        expect(waited).to eq(0)
      end

      it "decrements token count" do
        bucket = described_class.new(2, 1.0)
        bucket.acquire
        bucket.acquire

        # Next acquire should wait
        expect(bucket.available?).to be false
      end

      it "waits and returns wait time when empty" do
        bucket = described_class.new(1, 0.1) # 1 token, refills in 0.1s
        bucket.acquire # Consume the token

        start = Time.now
        waited = bucket.acquire
        elapsed = Time.now - start

        expect(waited).to be > 0
        expect(elapsed).to be >= waited * 0.9 # Allow some tolerance
      end

      it "refills tokens over time" do
        bucket = described_class.new(10, 0.1) # 10 tokens, full refill in 0.1s
        10.times { bucket.acquire }
        expect(bucket.available?).to be false

        sleep(0.05) # Wait for half refill

        # Should have some tokens back
        expect(bucket.available?).to be true
      end
    end

    describe "#available?" do
      it "returns true when tokens available" do
        bucket = described_class.new(5, 1.0)
        expect(bucket.available?).to be true
      end

      it "returns false when no tokens" do
        bucket = described_class.new(1, 10.0) # 1 token, slow refill
        bucket.acquire

        expect(bucket.available?).to be false
      end

      it "accounts for partial tokens" do
        bucket = described_class.new(2, 0.1)
        2.times { bucket.acquire }

        # Wait for partial refill
        sleep(0.03)

        # Still less than 1 full token
        expect(bucket.available?).to be false

        # Wait more
        sleep(0.04)

        # Should have at least 1 token now
        expect(bucket.available?).to be true
      end
    end
  end

  describe "real-world scenarios" do
    it "handles API rate limiting pattern" do
      # Simulate 10 requests per second limit
      request_times = []

      5.times do
        manager.rate_limit("api", calls: 10, per: 0.1)
        request_times << Time.now
      end

      # Requests should be spread out when limit exceeded
      expect(request_times.size).to eq(5)
    end

    it "handles step throttling pattern" do
      # Ensure at least 0.05s between step executions
      execution_times = []

      3.times do
        manager.throttle("step:process", 0.05)
        execution_times << Time.now
      end

      # Check timing between executions
      (1...execution_times.size).each do |i|
        gap = execution_times[i] - execution_times[i - 1]
        expect(gap).to be >= 0.04 # Allow some tolerance
      end
    end
  end
end
