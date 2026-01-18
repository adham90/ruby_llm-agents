# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::ReliabilityDSL do
  let(:dsl) { described_class.new }

  describe "#initialize" do
    it "sets retries_config to nil" do
      expect(dsl.retries_config).to be_nil
    end

    it "sets fallback_models_list to empty array" do
      expect(dsl.fallback_models_list).to eq([])
    end

    it "sets total_timeout_value to nil" do
      expect(dsl.total_timeout_value).to be_nil
    end

    it "sets circuit_breaker_config to nil" do
      expect(dsl.circuit_breaker_config).to be_nil
    end
  end

  describe "#retries" do
    context "with default values" do
      before { dsl.retries }

      it "sets max to 0" do
        expect(dsl.retries_config[:max]).to eq(0)
      end

      it "sets backoff to :exponential" do
        expect(dsl.retries_config[:backoff]).to eq(:exponential)
      end

      it "sets base to 0.4" do
        expect(dsl.retries_config[:base]).to eq(0.4)
      end

      it "sets max_delay to 3.0" do
        expect(dsl.retries_config[:max_delay]).to eq(3.0)
      end

      it "sets on to empty array" do
        expect(dsl.retries_config[:on]).to eq([])
      end
    end

    context "with custom values" do
      before do
        dsl.retries(
          max: 5,
          backoff: :constant,
          base: 1.0,
          max_delay: 10.0,
          on: [Timeout::Error, Net::ReadTimeout]
        )
      end

      it "sets max to custom value" do
        expect(dsl.retries_config[:max]).to eq(5)
      end

      it "sets backoff to custom value" do
        expect(dsl.retries_config[:backoff]).to eq(:constant)
      end

      it "sets base to custom value" do
        expect(dsl.retries_config[:base]).to eq(1.0)
      end

      it "sets max_delay to custom value" do
        expect(dsl.retries_config[:max_delay]).to eq(10.0)
      end

      it "sets on to custom error classes" do
        expect(dsl.retries_config[:on]).to eq([Timeout::Error, Net::ReadTimeout])
      end
    end

    context "with partial custom values" do
      before do
        dsl.retries(max: 3, backoff: :constant)
      end

      it "uses provided values" do
        expect(dsl.retries_config[:max]).to eq(3)
        expect(dsl.retries_config[:backoff]).to eq(:constant)
      end

      it "uses defaults for unspecified values" do
        expect(dsl.retries_config[:base]).to eq(0.4)
        expect(dsl.retries_config[:max_delay]).to eq(3.0)
        expect(dsl.retries_config[:on]).to eq([])
      end
    end

    it "overwrites previous configuration when called again" do
      dsl.retries(max: 3)
      dsl.retries(max: 5)

      expect(dsl.retries_config[:max]).to eq(5)
    end
  end

  describe "#fallback_models" do
    context "with single model" do
      before { dsl.fallback_models("gpt-4o-mini") }

      it "stores the model in an array" do
        expect(dsl.fallback_models_list).to eq(["gpt-4o-mini"])
      end
    end

    context "with multiple models as arguments" do
      before { dsl.fallback_models("gpt-4o-mini", "claude-3-haiku") }

      it "stores all models" do
        expect(dsl.fallback_models_list).to eq(["gpt-4o-mini", "claude-3-haiku"])
      end
    end

    context "with array of models" do
      before { dsl.fallback_models(["gpt-4o-mini", "claude-3-haiku"]) }

      it "flattens and stores all models" do
        expect(dsl.fallback_models_list).to eq(["gpt-4o-mini", "claude-3-haiku"])
      end
    end

    context "with mixed array and single models" do
      before { dsl.fallback_models("gpt-4o", ["gpt-4o-mini", "claude-3-haiku"]) }

      it "flattens and stores all models" do
        expect(dsl.fallback_models_list).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
      end
    end

    it "overwrites previous configuration when called again" do
      dsl.fallback_models("gpt-4o-mini")
      dsl.fallback_models("claude-3-haiku")

      expect(dsl.fallback_models_list).to eq(["claude-3-haiku"])
    end

    context "with no models" do
      before { dsl.fallback_models }

      it "sets to empty array" do
        expect(dsl.fallback_models_list).to eq([])
      end
    end
  end

  describe "#total_timeout" do
    it "stores the timeout value" do
      dsl.total_timeout(30)
      expect(dsl.total_timeout_value).to eq(30)
    end

    it "accepts float values" do
      dsl.total_timeout(45.5)
      expect(dsl.total_timeout_value).to eq(45.5)
    end

    it "accepts zero" do
      dsl.total_timeout(0)
      expect(dsl.total_timeout_value).to eq(0)
    end

    it "overwrites previous configuration when called again" do
      dsl.total_timeout(30)
      dsl.total_timeout(60)

      expect(dsl.total_timeout_value).to eq(60)
    end
  end

  describe "#circuit_breaker" do
    context "with default values" do
      before { dsl.circuit_breaker }

      it "sets errors to 10" do
        expect(dsl.circuit_breaker_config[:errors]).to eq(10)
      end

      it "sets within to 60" do
        expect(dsl.circuit_breaker_config[:within]).to eq(60)
      end

      it "sets cooldown to 300" do
        expect(dsl.circuit_breaker_config[:cooldown]).to eq(300)
      end
    end

    context "with custom values" do
      before do
        dsl.circuit_breaker(
          errors: 5,
          within: 120,
          cooldown: 600
        )
      end

      it "sets errors to custom value" do
        expect(dsl.circuit_breaker_config[:errors]).to eq(5)
      end

      it "sets within to custom value" do
        expect(dsl.circuit_breaker_config[:within]).to eq(120)
      end

      it "sets cooldown to custom value" do
        expect(dsl.circuit_breaker_config[:cooldown]).to eq(600)
      end
    end

    context "with partial custom values" do
      before do
        dsl.circuit_breaker(errors: 3)
      end

      it "uses provided values" do
        expect(dsl.circuit_breaker_config[:errors]).to eq(3)
      end

      it "uses defaults for unspecified values" do
        expect(dsl.circuit_breaker_config[:within]).to eq(60)
        expect(dsl.circuit_breaker_config[:cooldown]).to eq(300)
      end
    end

    it "overwrites previous configuration when called again" do
      dsl.circuit_breaker(errors: 5)
      dsl.circuit_breaker(errors: 10)

      expect(dsl.circuit_breaker_config[:errors]).to eq(10)
    end
  end

  describe "attribute readers" do
    it "exposes retries_config" do
      expect(dsl).to respond_to(:retries_config)
    end

    it "exposes fallback_models_list" do
      expect(dsl).to respond_to(:fallback_models_list)
    end

    it "exposes total_timeout_value" do
      expect(dsl).to respond_to(:total_timeout_value)
    end

    it "exposes circuit_breaker_config" do
      expect(dsl).to respond_to(:circuit_breaker_config)
    end
  end

  describe "full configuration example" do
    it "can configure all options together" do
      dsl.retries(max: 3, backoff: :exponential)
      dsl.fallback_models("gpt-4o-mini", "claude-3-haiku")
      dsl.total_timeout(30)
      dsl.circuit_breaker(errors: 5, within: 60)

      expect(dsl.retries_config).to eq({
        max: 3,
        backoff: :exponential,
        base: 0.4,
        max_delay: 3.0,
        on: []
      })
      expect(dsl.fallback_models_list).to eq(["gpt-4o-mini", "claude-3-haiku"])
      expect(dsl.total_timeout_value).to eq(30)
      expect(dsl.circuit_breaker_config).to eq({
        errors: 5,
        within: 60,
        cooldown: 300
      })
    end
  end

  describe "integration with Base agent" do
    let(:agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        reliability do
          retries max: 3, backoff: :exponential
          fallback_models "gpt-4o-mini"
          total_timeout 30
          circuit_breaker errors: 5
        end

        def self.name
          "TestReliabilityDSLAgent"
        end
      end
    end

    it "applies retries configuration to agent" do
      expect(agent_class.retries_config).to eq({
        max: 3,
        backoff: :exponential,
        base: 0.4,
        max_delay: 3.0,
        on: []
      })
    end

    it "applies fallback_models to agent" do
      expect(agent_class.fallback_models).to eq(["gpt-4o-mini"])
    end

    it "applies total_timeout to agent" do
      expect(agent_class.total_timeout).to eq(30)
    end

    it "applies circuit_breaker configuration to agent" do
      expect(agent_class.circuit_breaker_config).to eq({
        errors: 5,
        within: 60,
        cooldown: 300
      })
    end
  end

  describe "edge cases" do
    describe "retries with empty on array" do
      it "works with explicit empty array" do
        dsl.retries(max: 3, on: [])
        expect(dsl.retries_config[:on]).to eq([])
      end
    end

    describe "fallback_models with nested arrays" do
      it "flattens deeply nested arrays" do
        dsl.fallback_models([["gpt-4o-mini"], ["claude-3-haiku"]])
        expect(dsl.fallback_models_list).to eq(["gpt-4o-mini", "claude-3-haiku"])
      end
    end

    describe "multiple error classes for retries" do
      it "accepts multiple custom error classes" do
        custom_error1 = Class.new(StandardError)
        custom_error2 = Class.new(StandardError)

        dsl.retries(on: [custom_error1, custom_error2, Timeout::Error])

        expect(dsl.retries_config[:on]).to eq([custom_error1, custom_error2, Timeout::Error])
      end
    end

    describe "circuit_breaker with very low values" do
      it "accepts 1 for errors" do
        dsl.circuit_breaker(errors: 1)
        expect(dsl.circuit_breaker_config[:errors]).to eq(1)
      end

      it "accepts 1 for within" do
        dsl.circuit_breaker(within: 1)
        expect(dsl.circuit_breaker_config[:within]).to eq(1)
      end

      it "accepts 0 for cooldown" do
        dsl.circuit_breaker(cooldown: 0)
        expect(dsl.circuit_breaker_config[:cooldown]).to eq(0)
      end
    end

    describe "total_timeout with nil" do
      it "accepts nil" do
        dsl.total_timeout(nil)
        expect(dsl.total_timeout_value).to be_nil
      end
    end
  end
end
