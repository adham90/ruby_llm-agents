# frozen_string_literal: true

require "rails_helper"

# When every model is short-circuited by an open breaker, nothing was ever
# attempted — a distinct condition from "we tried them all and they failed".
# Raising AllModelsExhaustedError for it handed back a nil last_error and left
# CircuitBreakerOpenError, which the gem defines and documents, impossible to
# rescue from the pipeline.
RSpec.describe "open circuit breaker" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure { |c| c.cache_store = ActiveSupport::Cache::MemoryStore.new }
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:breaker_config) { {errors: 1, within: 60, cooldown: 300} }

  let(:agent_class) do
    config = breaker_config
    Class.new do
      define_singleton_method(:name) { "BreakerAgent" }

      def self.agent_type = :conversation

      def self.model = "primary-model"

      define_singleton_method(:reliability_config) do
        {retries: {max: 0}, circuit_breaker: config}
      end
    end
  end

  def trip_breaker!(model)
    breaker = RubyLLM::Agents::CircuitBreaker.from_config(
      "BreakerAgent", model, breaker_config, tenant_id: nil
    )
    2.times { breaker.record_failure! }
    breaker
  end

  def build_context
    RubyLLM::Agents::Pipeline::Context.new(
      input: "x", agent_class: agent_class, model: "primary-model"
    )
  end

  it "raises CircuitBreakerOpenError when nothing could be attempted" do
    trip_breaker!("primary-model")
    mw = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(
      ->(ctx) {
        ctx.output = "unreachable"
        ctx
      }, agent_class
    )

    expect { mw.call(build_context) }
      .to raise_error(RubyLLM::Agents::Reliability::CircuitBreakerOpenError) { |error|
        expect(error.agent_type).to eq("BreakerAgent")
        expect(error.model_id).to include("primary-model")
      }
  end

  it "never calls downstream when the breaker is open" do
    trip_breaker!("primary-model")
    called = false
    mw = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(
      ->(ctx) {
        called = true
        ctx
      }, agent_class
    )

    expect { mw.call(build_context) }.to raise_error(RubyLLM::Agents::Reliability::CircuitBreakerOpenError)
    expect(called).to be false
  end

  it "still raises AllModelsExhaustedError when models were actually tried" do
    mw = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(
      ->(_ctx) { raise StandardError, "provider down" }, agent_class
    )

    expect { mw.call(build_context) }
      .to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) { |error|
        expect(error.last_error.message).to eq("provider down")
      }
  end

  it "falls through to a model whose breaker is closed" do
    fallback_agent = Class.new do
      define_singleton_method(:name) { "BreakerAgent" }

      def self.agent_type = :conversation

      def self.model = "primary-model"

      def self.reliability_config
        {retries: {max: 0}, fallback_models: ["fallback-model"],
         circuit_breaker: {errors: 1, within: 60, cooldown: 300}}
      end
    end
    trip_breaker!("primary-model")

    seen = []
    mw = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(
      ->(ctx) {
        seen << ctx.model
        ctx.output = "ok"
        ctx
      }, fallback_agent
    )
    context = RubyLLM::Agents::Pipeline::Context.new(
      input: "x", agent_class: fallback_agent, model: "primary-model"
    )

    mw.call(context)

    expect(seen).to eq(["fallback-model"])
    expect(context.output).to eq("ok")
  end
end
