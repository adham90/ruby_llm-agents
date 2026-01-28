# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability do
  describe "error classes" do
    describe RubyLLM::Agents::Reliability::CircuitBreakerOpenError do
      it "is a subclass of Reliability::Error" do
        expect(described_class.superclass).to eq(RubyLLM::Agents::Reliability::Error)
      end

      it "accepts agent_type and model_id" do
        error = described_class.new("TestAgent", "gpt-4o")
        expect(error.message).to include("TestAgent")
        expect(error.message).to include("gpt-4o")
        expect(error.agent_type).to eq("TestAgent")
        expect(error.model_id).to eq("gpt-4o")
      end
    end

    describe RubyLLM::Agents::Reliability::BudgetExceededError do
      it "is a subclass of Reliability::Error" do
        expect(described_class.superclass).to eq(RubyLLM::Agents::Reliability::Error)
      end

      it "accepts scope, limit, and current" do
        error = described_class.new(:global_daily, 10.0, 15.0)
        expect(error.message).to include("global_daily")
        expect(error.message).to include("10")
        expect(error.scope).to eq(:global_daily)
        expect(error.limit).to eq(10.0)
        expect(error.current).to eq(15.0)
      end
    end

    describe RubyLLM::Agents::Reliability::TotalTimeoutError do
      it "is a subclass of Reliability::Error" do
        expect(described_class.superclass).to eq(RubyLLM::Agents::Reliability::Error)
      end

      it "accepts timeout and elapsed durations" do
        error = described_class.new(30, 35.5)
        expect(error.message).to include("30")
        expect(error.timeout_seconds).to eq(30)
        expect(error.elapsed_seconds).to eq(35.5)
      end
    end

    describe RubyLLM::Agents::Reliability::AllModelsExhaustedError do
      it "is a subclass of Reliability::Error" do
        expect(described_class.superclass).to eq(RubyLLM::Agents::Reliability::Error)
      end

      it "accepts models array and last error" do
        last_error = StandardError.new("API error")
        error = described_class.new(%w[gpt-4o claude-3], last_error)
        expect(error.message).to include("gpt-4o")
        expect(error.message).to include("claude-3")
        expect(error.models_tried).to eq(%w[gpt-4o claude-3])
        expect(error.last_error).to eq(last_error)
      end

      it "accepts optional attempts data" do
        last_error = StandardError.new("API error")
        attempts_data = [
          { "model_id" => "gpt-4o", "error_class" => "StandardError" },
          { "model_id" => "claude-3", "error_class" => "StandardError" }
        ]
        error = described_class.new(%w[gpt-4o claude-3], last_error, attempts: attempts_data)
        expect(error.attempts).to eq(attempts_data)
      end

      it "defaults attempts to nil when not provided" do
        last_error = StandardError.new("API error")
        error = described_class.new(%w[gpt-4o claude-3], last_error)
        expect(error.attempts).to be_nil
      end
    end
  end

  describe ".default_retryable_errors" do
    it "returns an array of error classes" do
      errors = described_class.default_retryable_errors
      expect(errors).to be_an(Array)
      expect(errors).to all(be_a(Class))
    end

    it "includes timeout errors" do
      errors = described_class.default_retryable_errors
      expect(errors).to include(Timeout::Error)
    end

    it "includes network errors" do
      errors = described_class.default_retryable_errors
      expect(errors).to include(Errno::ECONNREFUSED)
      expect(errors).to include(Errno::ETIMEDOUT)
    end
  end

  describe ".retryable_error?" do
    it "returns true for default retryable errors" do
      expect(described_class.retryable_error?(Timeout::Error.new)).to be true
    end

    it "returns true for subclasses of retryable errors" do
      expect(described_class.retryable_error?(Net::ReadTimeout.new)).to be true
    end

    it "returns false for non-retryable errors" do
      expect(described_class.retryable_error?(ArgumentError.new)).to be false
    end

    it "accepts custom error classes" do
      custom_error = Class.new(StandardError)
      expect(described_class.retryable_error?(custom_error.new, custom_errors: [custom_error])).to be true
    end

    it "accepts custom patterns for message matching" do
      error = StandardError.new("custom quota exceeded error")
      expect(described_class.retryable_error?(error, custom_patterns: ["quota"])).to be true
    end
  end

  describe ".retryable_by_message?" do
    it "returns true for rate limit errors" do
      error = StandardError.new("rate limit exceeded")
      expect(described_class.retryable_by_message?(error)).to be true
    end

    it "returns true for 429 errors" do
      error = StandardError.new("HTTP 429: Too Many Requests")
      expect(described_class.retryable_by_message?(error)).to be true
    end

    it "returns true for server errors (500, 502, 503, 504)" do
      %w[500 502 503 504].each do |code|
        error = StandardError.new("HTTP #{code} error")
        expect(described_class.retryable_by_message?(error)).to be true
      end
    end

    it "returns true for overloaded errors" do
      error = StandardError.new("Service overloaded, try again later")
      expect(described_class.retryable_by_message?(error)).to be true
    end

    it "returns false for non-retryable error messages" do
      error = StandardError.new("Invalid argument provided")
      expect(described_class.retryable_by_message?(error)).to be false
    end

    context "with quota errors (Gemini rate limiting)" do
      let(:gemini_quota_error_message) do
        "You exceeded your current quota, please check your plan and billing details. " \
        "For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. " \
        "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests"
      end

      it "returns true for quota exceeded errors" do
        error = StandardError.new(gemini_quota_error_message)
        expect(described_class.retryable_by_message?(error)).to be true
      end

      it "returns true for simple quota errors" do
        error = StandardError.new("quota exceeded")
        expect(described_class.retryable_by_message?(error)).to be true
      end

      it "returns true for exceeded quota errors" do
        error = StandardError.new("You exceeded your quota")
        expect(described_class.retryable_by_message?(error)).to be true
      end
    end

    context "with custom patterns" do
      it "matches custom patterns" do
        error = StandardError.new("custom_retry_pattern occurred")
        expect(described_class.retryable_by_message?(error, custom_patterns: ["custom_retry_pattern"])).to be true
      end

      it "combines default and custom patterns" do
        # Should still match default patterns
        rate_limit_error = StandardError.new("rate limit exceeded")
        expect(described_class.retryable_by_message?(rate_limit_error, custom_patterns: ["custom"])).to be true

        # Should also match custom patterns
        custom_error = StandardError.new("custom error message")
        expect(described_class.retryable_by_message?(custom_error, custom_patterns: ["custom"])).to be true
      end
    end
  end

  describe ".non_fallback_error?" do
    it "returns true for ArgumentError" do
      expect(described_class.non_fallback_error?(ArgumentError.new("wrong args"))).to be true
    end

    it "returns true for TypeError" do
      expect(described_class.non_fallback_error?(TypeError.new("no implicit conversion"))).to be true
    end

    it "returns true for NameError" do
      expect(described_class.non_fallback_error?(NameError.new("undefined local variable"))).to be true
    end

    it "returns true for NoMethodError" do
      expect(described_class.non_fallback_error?(NoMethodError.new("undefined method"))).to be true
    end

    it "returns true for NotImplementedError" do
      expect(described_class.non_fallback_error?(NotImplementedError.new("not implemented"))).to be true
    end

    it "returns false for StandardError" do
      expect(described_class.non_fallback_error?(StandardError.new("API error"))).to be false
    end

    it "returns false for RuntimeError" do
      expect(described_class.non_fallback_error?(RuntimeError.new("invalid API key"))).to be false
    end

    it "returns false for Timeout::Error" do
      expect(described_class.non_fallback_error?(Timeout::Error.new("timeout"))).to be false
    end

    it "returns false for IOError" do
      expect(described_class.non_fallback_error?(IOError.new("connection reset"))).to be false
    end

    it "accepts custom non-fallback error classes" do
      custom_error = Class.new(StandardError)
      expect(described_class.non_fallback_error?(custom_error.new, custom_errors: [custom_error])).to be true
    end
  end

  describe ".calculate_backoff" do
    context "with exponential backoff" do
      it "increases delay exponentially" do
        delay1 = described_class.calculate_backoff(strategy: :exponential, base: 0.5, max_delay: 30, attempt: 0)
        delay2 = described_class.calculate_backoff(strategy: :exponential, base: 0.5, max_delay: 30, attempt: 1)
        delay3 = described_class.calculate_backoff(strategy: :exponential, base: 0.5, max_delay: 30, attempt: 2)

        # Base delays without jitter: 0.5, 1.0, 2.0
        # With jitter (0-50%), ranges: [0.5, 0.75], [1.0, 1.5], [2.0, 3.0]
        expect(delay1).to be >= 0.5
        expect(delay2).to be >= 1.0
        expect(delay3).to be >= 2.0
      end

      it "respects max_delay" do
        delay = described_class.calculate_backoff(strategy: :exponential, base: 0.5, max_delay: 5, attempt: 10)
        # Even with jitter, should not exceed max_delay + 50% jitter
        expect(delay).to be <= 7.5
      end

      it "adds jitter" do
        delays = 10.times.map do
          described_class.calculate_backoff(strategy: :exponential, base: 0.5, max_delay: 30, attempt: 2)
        end

        # With jitter, we should see some variation
        expect(delays.uniq.size).to be > 1
      end
    end

    context "with constant backoff" do
      it "returns base delay plus jitter" do
        delays = 10.times.map do
          described_class.calculate_backoff(strategy: :constant, base: 2.0, max_delay: 30, attempt: 5)
        end

        # All delays should be at least 2.0 (base) and at most 3.0 (base + 50% jitter)
        delays.each do |delay|
          expect(delay).to be >= 2.0
          expect(delay).to be <= 3.0
        end
      end
    end
  end
end
