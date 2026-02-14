# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DSL::Reliability do
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Reliability

      def self.name
        "TestAgent"
      end
    end
  end

  describe "#retries" do
    it "returns default retry config when not set" do
      config = test_class.retries
      expect(config[:max]).to eq(0)
      expect(config[:backoff]).to eq(:exponential)
    end

    it "sets max retries" do
      test_class.retries(max: 3)
      expect(test_class.retries[:max]).to eq(3)
    end

    it "sets backoff strategy" do
      test_class.retries(backoff: :constant, base: 1.0)
      config = test_class.retries
      expect(config[:backoff]).to eq(:constant)
      expect(config[:base]).to eq(1.0)
    end

    it "sets max delay" do
      test_class.retries(max: 2, max_delay: 10.0)
      expect(test_class.retries[:max_delay]).to eq(10.0)
    end

    it "sets custom error classes" do
      test_class.retries(on: [Timeout::Error, Net::ReadTimeout])
      expect(test_class.retries[:on]).to eq([Timeout::Error, Net::ReadTimeout])
    end
  end

  describe "#fallback_models" do
    it "returns empty array when not set" do
      expect(test_class.fallback_models).to eq([])
    end

    it "sets fallback models with splat args" do
      test_class.fallback_models("gpt-4o-mini", "gpt-3.5-turbo")
      expect(test_class.fallback_models).to eq(["gpt-4o-mini", "gpt-3.5-turbo"])
    end

    it "sets fallback models with array" do
      test_class.fallback_models(["claude-3-haiku", "claude-3-sonnet"])
      expect(test_class.fallback_models).to eq(["claude-3-haiku", "claude-3-sonnet"])
    end
  end

  describe "#total_timeout" do
    it "returns nil when not set" do
      expect(test_class.total_timeout).to be_nil
    end

    it "sets total timeout" do
      test_class.total_timeout(30)
      expect(test_class.total_timeout).to eq(30)
    end
  end

  describe "#circuit_breaker" do
    it "returns nil when not set" do
      expect(test_class.circuit_breaker_config).to be_nil
    end

    it "sets circuit breaker with defaults" do
      test_class.circuit_breaker(errors: 5)
      config = test_class.circuit_breaker_config
      expect(config[:errors]).to eq(5)
      expect(config[:within]).to eq(60) # default
      expect(config[:cooldown]).to eq(300) # default
    end

    it "sets all circuit breaker options" do
      test_class.circuit_breaker(errors: 10, within: 120, cooldown: 600)
      config = test_class.circuit_breaker_config
      expect(config[:errors]).to eq(10)
      expect(config[:within]).to eq(120)
      expect(config[:cooldown]).to eq(600)
    end
  end

  describe "#retryable_patterns" do
    it "returns nil when not set" do
      expect(test_class.retryable_patterns).to be_nil
    end

    it "sets retryable patterns" do
      test_class.retryable_patterns("rate limit", "overloaded")
      expect(test_class.retryable_patterns).to eq(["rate limit", "overloaded"])
    end
  end

  describe "#non_fallback_errors" do
    it "returns nil when not set" do
      expect(test_class.non_fallback_errors).to be_nil
    end

    it "sets non-fallback error classes" do
      custom_error = Class.new(StandardError)
      test_class.non_fallback_errors(custom_error)
      expect(test_class.non_fallback_errors).to eq([custom_error])
    end

    it "sets multiple non-fallback error classes" do
      error1 = Class.new(StandardError)
      error2 = Class.new(StandardError)
      test_class.non_fallback_errors(error1, error2)
      expect(test_class.non_fallback_errors).to eq([error1, error2])
    end

    it "appears in reliability_config" do
      custom_error = Class.new(StandardError)
      test_class.fallback_models("backup")
      test_class.non_fallback_errors(custom_error)
      config = test_class.reliability_config
      expect(config[:non_fallback_errors]).to eq([custom_error])
    end
  end

  describe "#reliability block syntax" do
    it "configures all options in a block" do
      test_class.reliability do
        retries max: 3, backoff: :exponential, base: 0.5
        fallback_models "gpt-4o-mini"
        total_timeout 60
        circuit_breaker errors: 5, within: 30
        retryable_patterns "custom_error"
      end

      expect(test_class.retries_config[:max]).to eq(3)
      expect(test_class.retries_config[:base]).to eq(0.5)
      expect(test_class.fallback_models).to eq(["gpt-4o-mini"])
      expect(test_class.total_timeout).to eq(60)
      expect(test_class.circuit_breaker_config[:errors]).to eq(5)
      expect(test_class.retryable_patterns).to eq(["custom_error"])
    end

    it "configures non_fallback_errors in a block" do
      custom_error = Class.new(StandardError)
      test_class.reliability do
        retries max: 1
        non_fallback_errors custom_error
      end

      expect(test_class.non_fallback_errors).to eq([custom_error])
    end
  end

  describe "#reliability_config" do
    it "returns nil when nothing is configured" do
      expect(test_class.reliability_config).to be_nil
    end

    it "returns config hash when reliability is configured" do
      test_class.retries(max: 2)
      test_class.fallback_models("backup-model")

      config = test_class.reliability_config
      expect(config).to include(:retries, :fallback_models)
      expect(config[:retries][:max]).to eq(2)
      expect(config[:fallback_models]).to eq(["backup-model"])
    end
  end

  describe "#reliability_configured?" do
    it "returns false when nothing is configured" do
      expect(test_class.reliability_configured?).to be false
    end

    it "returns true when retries are configured" do
      test_class.retries(max: 1)
      expect(test_class.reliability_configured?).to be true
    end

    it "returns true when fallback models are configured" do
      test_class.fallback_models("backup")
      expect(test_class.reliability_configured?).to be true
    end

    it "returns true when circuit breaker is configured" do
      test_class.circuit_breaker(errors: 5)
      expect(test_class.reliability_configured?).to be true
    end
  end

  describe "inheritance" do
    it "inherits retry config from parent" do
      test_class.retries(max: 3)

      child_class = Class.new(test_class)
      expect(child_class.retries_config[:max]).to eq(3)
    end

    it "allows child to override parent config" do
      test_class.retries(max: 3)

      child_class = Class.new(test_class) do
        extend RubyLLM::Agents::DSL::Reliability
        retries max: 5
      end
      expect(child_class.retries_config[:max]).to eq(5)
    end

    it "inherits fallback models from parent" do
      test_class.fallback_models("parent-backup")

      child_class = Class.new(test_class)
      expect(child_class.fallback_models).to eq(["parent-backup"])
    end

    it "inherits non_fallback_errors from parent" do
      custom_error = Class.new(StandardError)
      test_class.non_fallback_errors(custom_error)

      child_class = Class.new(test_class)
      expect(child_class.non_fallback_errors).to eq([custom_error])
    end
  end

  describe "#on_failure (simplified DSL)" do
    it "configures retries with times: syntax" do
      test_class.on_failure do
        retries times: 3, backoff: :exponential
      end

      expect(test_class.retries_config[:max]).to eq(3)
      expect(test_class.retries_config[:backoff]).to eq(:exponential)
    end

    it "configures fallback with to: syntax" do
      test_class.on_failure do
        fallback to: "gpt-4o-mini"
      end

      expect(test_class.fallback_models).to eq(["gpt-4o-mini"])
    end

    it "accepts array for fallback to:" do
      test_class.on_failure do
        fallback to: ["gpt-4o-mini", "gpt-3.5-turbo"]
      end

      expect(test_class.fallback_models).to eq(["gpt-4o-mini", "gpt-3.5-turbo"])
    end

    it "configures timeout" do
      test_class.on_failure do
        timeout 30
      end

      expect(test_class.total_timeout).to eq(30)
    end

    it "handles ActiveSupport::Duration for timeout" do
      test_class.on_failure do
        timeout 30.seconds
      end

      expect(test_class.total_timeout).to eq(30)
    end

    it "configures circuit_breaker with after: syntax" do
      test_class.on_failure do
        circuit_breaker after: 5, cooldown: 300
      end

      expect(test_class.circuit_breaker_config[:errors]).to eq(5)
      expect(test_class.circuit_breaker_config[:cooldown]).to eq(300)
    end

    it "handles ActiveSupport::Duration for cooldown" do
      test_class.on_failure do
        circuit_breaker after: 5, cooldown: 5.minutes
      end

      expect(test_class.circuit_breaker_config[:cooldown]).to eq(300)
    end

    it "configures all options together" do
      custom_error = Class.new(StandardError)

      test_class.on_failure do
        retries times: 2, backoff: :constant, base: 1.0
        fallback to: ["backup-1", "backup-2"]
        timeout 60
        circuit_breaker after: 10, within: 120, cooldown: 600
        non_fallback_errors custom_error
      end

      expect(test_class.retries_config[:max]).to eq(2)
      expect(test_class.retries_config[:backoff]).to eq(:constant)
      expect(test_class.retries_config[:base]).to eq(1.0)
      expect(test_class.fallback_models).to eq(["backup-1", "backup-2"])
      expect(test_class.total_timeout).to eq(60)
      expect(test_class.circuit_breaker_config[:errors]).to eq(10)
      expect(test_class.circuit_breaker_config[:within]).to eq(120)
      expect(test_class.circuit_breaker_config[:cooldown]).to eq(600)
      expect(test_class.non_fallback_errors).to eq([custom_error])
    end

    it "supports fallback_models for backward compatibility" do
      test_class.on_failure do
        fallback_models "backup-1", "backup-2"
      end

      expect(test_class.fallback_models).to eq(["backup-1", "backup-2"])
    end

    it "supports retries with times: syntax" do
      test_class.on_failure do
        retries times: 3
      end

      expect(test_class.retries_config[:max]).to eq(3)
    end

    it "supports total_timeout alias for timeout" do
      test_class.on_failure do
        total_timeout 45
      end

      expect(test_class.total_timeout).to eq(45)
    end

    it "supports errors: syntax for circuit_breaker (backward compatibility)" do
      test_class.on_failure do
        circuit_breaker errors: 8, within: 60, cooldown: 300
      end

      expect(test_class.circuit_breaker_config[:errors]).to eq(8)
    end
  end
end
