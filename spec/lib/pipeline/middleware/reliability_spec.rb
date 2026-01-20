# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Reliability do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "primary-model"
      end

      def self.reliability_config
        {
          retries: { max: 2, backoff: :exponential, base: 0.1, max_delay: 1.0 },
          fallback_models: ["fallback-model"],
          total_timeout: 30
        }
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }
  let(:config) { instance_double(RubyLLM::Agents::Configuration) }

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      model: "primary-model",
      **options
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:all_retryable_patterns).and_return(["rate limit", "overloaded"])
    allow(config).to receive(:respond_to?).with(:async_context?).and_return(false)
    # Speed up tests by stubbing sleep
    allow(middleware).to receive(:sleep)
  end

  describe "#call" do
    context "when reliability is disabled" do
      let(:agent_class_no_reliability) do
        Class.new do
          def self.name
            "NoReliabilityAgent"
          end

          def self.agent_type
            :embedding
          end

          def self.model
            "test-model"
          end

          def self.reliability_config
            nil
          end
        end
      end

      let(:middleware) { described_class.new(app, agent_class_no_reliability) }

      it "passes through to the next middleware" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: agent_class_no_reliability
        )
        expect(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)
        expect(result).to eq(context)
      end
    end

    context "successful execution" do
      it "returns the result on first attempt success" do
        context = build_context

        expect(app).to receive(:call).once do |ctx|
          ctx.output = "success"
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq("success")
        expect(result.attempts_made).to eq(1)
      end

      it "sets the correct attempt count" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        result = middleware.call(context)

        expect(result.attempts_made).to eq(1)
        expect(result.attempt).to eq(1)
      end
    end

    context "retry behavior" do
      it "retries on retryable errors" do
        context = build_context
        call_count = 0

        allow(app).to receive(:call) do |ctx|
          call_count += 1
          if call_count < 2
            raise Timeout::Error, "Connection timed out"
          end
          ctx.output = "success after retry"
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq("success after retry")
        expect(result.attempts_made).to eq(2)
      end

      it "respects max retry count" do
        context = build_context

        allow(app).to receive(:call).and_raise(Timeout::Error, "Connection timed out")

        # Should fail after max retries (2) on primary model, then try fallback
        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
      end

      it "does not retry non-retryable errors" do
        context = build_context

        # ArgumentError is not retryable
        allow(app).to receive(:call).and_raise(ArgumentError, "Invalid argument")

        expect(app).to receive(:call).exactly(2).times # Once per model

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
      end

      it "retries on message pattern match" do
        context = build_context
        call_count = 0

        allow(app).to receive(:call) do |ctx|
          call_count += 1
          if call_count < 2
            raise StandardError, "rate limit exceeded"
          end
          ctx.output = "success"
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq("success")
      end

      it "uses exponential backoff between retries" do
        context = build_context
        call_count = 0

        allow(app).to receive(:call) do |ctx|
          call_count += 1
          if call_count < 3
            raise Timeout::Error, "timeout"
          end
          ctx.output = "success"
          ctx
        end

        expect(middleware).to receive(:sleep).at_least(:once)

        middleware.call(context)
      end
    end

    context "fallback behavior" do
      it "falls back to secondary model when primary fails" do
        context = build_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "primary-model"
            raise StandardError, "Primary model failed"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        expect(models_tried).to include("primary-model", "fallback-model")
        expect(result.output).to eq("fallback success")
      end

      it "raises AllModelsFailedError when all models fail" do
        context = build_context

        allow(app).to receive(:call).and_raise(StandardError, "All models failed")

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.models_tried).to eq(["primary-model", "fallback-model"])
          expect(error.last_error.message).to eq("All models failed")
        end
      end
    end

    context "circuit breaker" do
      let(:agent_class_with_circuit_breaker) do
        Class.new do
          def self.name
            "CircuitBreakerAgent"
          end

          def self.agent_type
            :embedding
          end

          def self.model
            "primary-model"
          end

          def self.reliability_config
            {
              retries: { max: 0 },
              fallback_models: ["fallback-model"],
              circuit_breaker: { errors: 3, within: 60, cooldown: 300 }
            }
          end
        end
      end

      let(:middleware) { described_class.new(app, agent_class_with_circuit_breaker) }
      let(:breaker) { instance_double(RubyLLM::Agents::CircuitBreaker) }

      before do
        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config).and_return(breaker)
        allow(breaker).to receive(:record_success!)
        allow(breaker).to receive(:record_failure!)
      end

      it "skips models with open circuit breakers" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: agent_class_with_circuit_breaker,
          model: "primary-model"
        )

        primary_breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        fallback_breaker = instance_double(RubyLLM::Agents::CircuitBreaker)

        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("CircuitBreakerAgent", "primary-model", anything, tenant_id: nil)
          .and_return(primary_breaker)
        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("CircuitBreakerAgent", "fallback-model", anything, tenant_id: nil)
          .and_return(fallback_breaker)

        allow(primary_breaker).to receive(:open?).and_return(true)
        allow(fallback_breaker).to receive(:open?).and_return(false)
        allow(fallback_breaker).to receive(:record_success!)

        allow(app).to receive(:call) do |ctx|
          ctx.output = "fallback result"
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq("fallback result")
      end

      it "records success in circuit breaker" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: agent_class_with_circuit_breaker,
          model: "primary-model"
        )

        allow(breaker).to receive(:open?).and_return(false)
        allow(app).to receive(:call) do |ctx|
          ctx.output = "success"
          ctx
        end

        expect(breaker).to receive(:record_success!)

        middleware.call(context)
      end

      it "records failure in circuit breaker" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: agent_class_with_circuit_breaker,
          model: "primary-model"
        )

        allow(breaker).to receive(:open?).and_return(false)
        allow(app).to receive(:call).and_raise(StandardError, "error")

        expect(breaker).to receive(:record_failure!).at_least(:once)

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
      end
    end

    context "total timeout" do
      it "raises TotalTimeoutError when total timeout is exceeded" do
        context = build_context

        allow(Time).to receive(:current).and_return(
          Time.new(2024, 1, 1, 12, 0, 0),   # Start
          Time.new(2024, 1, 1, 12, 0, 31)   # After timeout
        )

        allow(app).to receive(:call).and_raise(Timeout::Error, "timeout")

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)
      end
    end

    context "attempt tracking" do
      it "tracks total attempts across models and retries" do
        context = build_context
        attempts_seen = []

        allow(app).to receive(:call) do |ctx|
          attempts_seen << { model: ctx.model, attempt: ctx.attempt }
          if attempts_seen.length < 4 # Fail first 3 attempts
            raise Timeout::Error, "timeout"
          end
          ctx.output = "success"
          ctx
        end

        result = middleware.call(context)

        expect(result.attempts_made).to eq(4)
      end
    end
  end
end
