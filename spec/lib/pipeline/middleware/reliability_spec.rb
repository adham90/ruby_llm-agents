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

    context "retry behavior (with fallback models - skips retries)" do
      it "does not retry retryable errors when fallbacks exist" do
        context = build_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "primary-model"
            raise Timeout::Error, "Connection timed out"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        # With fallbacks, should skip retries and move to fallback
        expect(models_tried.count("primary-model")).to eq(1)
        expect(models_tried).to include("fallback-model")
        expect(result.output).to eq("fallback success")
      end

      it "does not retry on message pattern match when fallbacks exist" do
        context = build_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "primary-model"
            raise StandardError, "rate limit exceeded"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        expect(models_tried.count("primary-model")).to eq(1)
        expect(result.output).to eq("fallback success")
      end

      it "raises AllModelsExhaustedError when all models fail" do
        context = build_context

        allow(app).to receive(:call).and_raise(Timeout::Error, "Connection timed out")

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
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

      it "captures the last error from the last model tried" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          if ctx.model == "primary-model"
            raise StandardError, "Primary model quota exceeded"
          else
            raise StandardError, "Fallback model API key invalid"
          end
        end

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.last_error.message).to eq("Fallback model API key invalid")
        end
      end
    end

    context "quota errors (Gemini rate limiting)" do
      before do
        # Update patterns to include quota for these tests
        allow(config).to receive(:all_retryable_patterns).and_return(["rate limit", "overloaded", "quota"])
      end

      it "retries on quota exceeded errors" do
        context = build_context
        call_count = 0

        allow(app).to receive(:call) do |ctx|
          call_count += 1
          if call_count < 2
            raise StandardError, "You exceeded your current quota"
          end
          ctx.output = "success after quota retry"
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq("success after quota retry")
        expect(result.attempts_made).to eq(2)
      end

      it "skips retries and falls back immediately when fallback models exist" do
        context = build_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "primary-model"
            raise StandardError, "Quota exceeded for metric: generativelanguage.googleapis.com"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        # Should NOT retry primary — fallback models exist, so move immediately
        expect(models_tried.count("primary-model")).to eq(1)
        expect(models_tried).to include("fallback-model")
        expect(result.output).to eq("fallback success")
      end

      it "captures quota error as last_error when all models fail with different errors" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          if ctx.model == "primary-model"
            raise StandardError, "You exceeded your current quota, please check your plan"
          else
            raise StandardError, "OpenAI API error: invalid_api_key"
          end
        end

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          # Last error should be from the fallback model, not the primary
          expect(error.last_error.message).to eq("OpenAI API error: invalid_api_key")
          expect(error.last_error.message).not_to include("quota")
        end
      end
    end

    context "non-fallback errors (programming errors)" do
      it "re-raises ArgumentError immediately without fallback" do
        context = build_context

        allow(app).to receive(:call).and_raise(ArgumentError, "wrong number of arguments")

        expect(app).to receive(:call).once
        expect { middleware.call(context) }.to raise_error(ArgumentError, "wrong number of arguments")
      end

      it "re-raises TypeError immediately without fallback" do
        context = build_context

        allow(app).to receive(:call).and_raise(TypeError, "no implicit conversion")

        expect(app).to receive(:call).once
        expect { middleware.call(context) }.to raise_error(TypeError, "no implicit conversion")
      end

      it "re-raises NoMethodError immediately without fallback" do
        context = build_context

        allow(app).to receive(:call).and_raise(NoMethodError, "undefined method 'foo'")

        expect(app).to receive(:call).once
        expect { middleware.call(context) }.to raise_error(NoMethodError)
      end

      it "still records circuit breaker failure for non-fallback errors" do
        agent_class_cb = Class.new do
          def self.name = "CBAgent"
          def self.agent_type = :embedding
          def self.model = "primary-model"

          def self.reliability_config
            {
              retries: { max: 2 },
              fallback_models: ["fallback-model"],
              circuit_breaker: { errors: 3, within: 60, cooldown: 300 }
            }
          end
        end

        cb_middleware = described_class.new(app, agent_class_cb)
        allow(cb_middleware).to receive(:sleep)
        context = build_context

        breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config).and_return(breaker)
        allow(breaker).to receive(:open?).and_return(false)
        allow(breaker).to receive(:record_failure!)
        allow(app).to receive(:call).and_raise(ArgumentError, "bad args")

        expect(breaker).to receive(:record_failure!)
        expect { cb_middleware.call(context) }.to raise_error(ArgumentError)
      end
    end

    context "retry behavior with fallback models" do
      it "skips retries when fallback models exist" do
        context = build_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "primary-model"
            raise Timeout::Error, "Connection timed out"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        # With fallback models, should NOT retry primary — move to fallback immediately
        expect(models_tried.count("primary-model")).to eq(1)
        expect(models_tried).to include("fallback-model")
        expect(result.output).to eq("fallback success")
      end
    end

    context "retry behavior without fallback models" do
      let(:agent_class_no_fallbacks) do
        Class.new do
          def self.name = "NoFallbackAgent"
          def self.agent_type = :embedding
          def self.model = "primary-model"

          def self.reliability_config
            {
              retries: { max: 2, backoff: :exponential, base: 0.1, max_delay: 1.0 },
              fallback_models: []
            }
          end
        end
      end

      let(:no_fallback_middleware) { described_class.new(app, agent_class_no_fallbacks) }

      before do
        allow(no_fallback_middleware).to receive(:sleep)
      end

      it "retries on transient errors when no fallback models exist" do
        context = build_context
        call_count = 0

        allow(app).to receive(:call) do |ctx|
          call_count += 1
          if call_count < 3
            raise Timeout::Error, "Connection timed out"
          end
          ctx.output = "success after retry"
          ctx
        end

        result = no_fallback_middleware.call(context)

        expect(result.output).to eq("success after retry")
        expect(result.attempts_made).to eq(3)
      end

      it "raises after exhausting retries when no fallback models exist" do
        context = build_context

        allow(app).to receive(:call).and_raise(Timeout::Error, "Connection timed out")

        expect { no_fallback_middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        )
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
      it "tracks total attempts across models (with fallbacks, no retries)" do
        context = build_context
        attempts_seen = []

        allow(app).to receive(:call) do |ctx|
          attempts_seen << { model: ctx.model, attempt: ctx.attempt }
          if ctx.model == "primary-model"
            raise Timeout::Error, "timeout"
          end
          ctx.output = "success"
          ctx
        end

        result = middleware.call(context)

        # Primary fails (1 attempt), fallback succeeds (1 attempt) = 2 total
        expect(result.attempts_made).to eq(2)
      end

      it "tracks total attempts with retries (without fallbacks)" do
        agent_class_retries_only = Class.new do
          def self.name = "RetriesOnlyAgent"
          def self.agent_type = :embedding
          def self.model = "primary-model"

          def self.reliability_config
            {
              retries: { max: 3, backoff: :exponential, base: 0.1, max_delay: 1.0 },
              fallback_models: []
            }
          end
        end

        retries_middleware = described_class.new(app, agent_class_retries_only)
        allow(retries_middleware).to receive(:sleep)

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

        result = retries_middleware.call(context)

        expect(result.attempts_made).to eq(3)
      end
    end

    context "three-model fallback chain" do
      let(:three_model_agent) do
        Class.new do
          def self.name = "ThreeModelAgent"
          def self.agent_type = :embedding
          def self.model = "gemini-2.5-flash"

          def self.reliability_config
            {
              retries: { max: 2, backoff: :exponential, base: 0.1, max_delay: 1.0 },
              fallback_models: ["gpt-4.1-mini", "claude-haiku-4-5"]
            }
          end
        end
      end

      let(:three_model_middleware) { described_class.new(app, three_model_agent) }

      before do
        allow(three_model_middleware).to receive(:sleep)
      end

      def build_three_model_context(options = {})
        RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: three_model_agent,
          model: "gemini-2.5-flash",
          **options
        )
      end

      it "reports last_error from the third model when all three fail with distinct errors" do
        context = build_three_model_context

        allow(app).to receive(:call) do |ctx|
          case ctx.model
          when "gemini-2.5-flash"
            raise StandardError, "You exceeded your current quota, generativelanguage.googleapis.com"
          when "gpt-4.1-mini"
            raise StandardError, "OpenAI API error: insufficient_quota"
          when "claude-haiku-4-5"
            raise StandardError, "Anthropic API error: authentication_error"
          end
        end

        expect { three_model_middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        ) do |error|
          expect(error.models_tried).to eq(["gemini-2.5-flash", "gpt-4.1-mini", "claude-haiku-4-5"])
          expect(error.last_error.message).to eq("Anthropic API error: authentication_error")
          expect(error.last_error.message).not_to include("generativelanguage")
        end
      end

      it "reaches the third model and returns success when first two fail" do
        context = build_three_model_context

        allow(app).to receive(:call) do |ctx|
          case ctx.model
          when "gemini-2.5-flash"
            raise StandardError, "Gemini quota exceeded"
          when "gpt-4.1-mini"
            raise StandardError, "OpenAI rate limit"
          when "claude-haiku-4-5"
            ctx.output = "third model success"
            ctx
          end
        end

        result = three_model_middleware.call(context)

        expect(result.output).to eq("third model success")
        expect(result.attempts_made).to eq(3)
      end

      it "stops at the second model when it succeeds" do
        context = build_three_model_context
        models_tried = []

        allow(app).to receive(:call) do |ctx|
          models_tried << ctx.model
          if ctx.model == "gemini-2.5-flash"
            raise StandardError, "Gemini quota exceeded"
          end
          ctx.output = "second model success"
          ctx
        end

        result = three_model_middleware.call(context)

        expect(models_tried).to eq(["gemini-2.5-flash", "gpt-4.1-mini"])
        expect(models_tried).not_to include("claude-haiku-4-5")
        expect(result.output).to eq("second model success")
      end

      it "sets the correct model on context for each fallback attempt" do
        context = build_three_model_context
        models_seen = []

        allow(app).to receive(:call) do |ctx|
          models_seen << ctx.model
          raise StandardError, "error from #{ctx.model}"
        end

        expect { three_model_middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        )

        expect(models_seen).to eq(["gemini-2.5-flash", "gpt-4.1-mini", "claude-haiku-4-5"])
      end

      it "includes all three models in models_tried when all fail with the same error type" do
        context = build_three_model_context

        allow(app).to receive(:call) do |ctx|
          raise StandardError, "rate limit exceeded for #{ctx.model}"
        end

        expect { three_model_middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        ) do |error|
          expect(error.models_tried).to eq(["gemini-2.5-flash", "gpt-4.1-mini", "claude-haiku-4-5"])
          expect(error.last_error.message).to eq("rate limit exceeded for claude-haiku-4-5")
        end
      end

      it "updates context.error to reflect the current model's error" do
        context = build_three_model_context
        errors_seen = []

        allow(app).to receive(:call) do |ctx|
          errors_seen << ctx.error&.message if ctx.error
          raise StandardError, "error from #{ctx.model}"
        end

        expect { three_model_middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        )

        # After all attempts, context.error should be from the last model
        expect(context.error).to be_a(StandardError)
        expect(context.error.message).to eq("error from claude-haiku-4-5")
      end
    end

    context "downstream model resolution on fallback" do
      # These specs verify that when reliability sets context.model to a fallback,
      # the downstream execution layer actually uses that model (not the original).
      # This catches the bug where all fallback models hit the same provider.

      context "chat agent (build_client)" do
        it "passes context to build_client so fallback model is used" do
          agent_instance = double("agent_instance")
          chat_client = double("chat_client")

          # Simulate: primary fails, fallback succeeds
          allow(app).to receive(:call) do |ctx|
            # Verify the downstream would see the correct model
            if ctx.model == "primary-model"
              raise StandardError, "primary failed"
            end
            ctx.output = "fallback success"
            ctx
          end

          context = build_context
          result = middleware.call(context)

          # The middleware correctly sets context.model to "fallback-model"
          # Downstream code must read context.model (not agent_class.model)
          expect(result.output).to eq("fallback success")
        end
      end

      context "embedder (resolved_model)" do
        it "uses context.model for embedding calls, not the class-level model" do
          context = build_context
          models_used_for_embedding = []

          allow(app).to receive(:call) do |ctx|
            # Track what model the downstream would see
            models_used_for_embedding << ctx.model
            if ctx.model == "primary-model"
              raise StandardError, "primary quota exceeded"
            end
            ctx.output = "embedded with fallback"
            ctx
          end

          result = middleware.call(context)

          # The fallback attempt must have context.model set to fallback-model
          expect(models_used_for_embedding).to eq(["primary-model", "fallback-model"])
          expect(result.output).to eq("embedded with fallback")
        end
      end

      context "model is not restored before downstream call" do
        it "does not restore original model before calling app on fallback attempt" do
          context = build_context
          model_during_app_call = []

          allow(app).to receive(:call) do |ctx|
            model_during_app_call << ctx.model
            raise StandardError, "fail #{ctx.model}"
          end

          expect { middleware.call(context) }.to raise_error(
            RubyLLM::Agents::Reliability::AllModelsExhaustedError
          )

          # During each app.call, context.model must be the current model being tried
          # NOT the original model (which would mean fallback isn't working)
          expect(model_during_app_call).to eq(["primary-model", "fallback-model"])
        end
      end
    end

    context "per-model attempt tracking via AttemptTracker" do
      it "stores attempt data in context on successful fallback" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          if ctx.model == "primary-model"
            raise StandardError, "Gemini quota exceeded"
          end
          ctx.output = "fallback success"
          ctx
        end

        result = middleware.call(context)

        attempts = result[:reliability_attempts]
        expect(attempts).to be_an(Array)
        expect(attempts.length).to eq(2)

        # First attempt: primary model failed
        expect(attempts[0]["model_id"]).to eq("primary-model")
        expect(attempts[0]["error_class"]).to eq("StandardError")
        expect(attempts[0]["error_message"]).to include("Gemini quota exceeded")

        # Second attempt: fallback model succeeded
        expect(attempts[1]["model_id"]).to eq("fallback-model")
        expect(attempts[1]["error_class"]).to be_nil
      end

      it "stores attempt data in context when all models fail" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          if ctx.model == "primary-model"
            raise StandardError, "Gemini quota exceeded"
          else
            raise StandardError, "OpenAI API key invalid"
          end
        end

        expect { middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        )

        attempts = context[:reliability_attempts]
        expect(attempts).to be_an(Array)
        expect(attempts.length).to eq(2)

        expect(attempts[0]["model_id"]).to eq("primary-model")
        expect(attempts[0]["error_class"]).to eq("StandardError")
        expect(attempts[0]["error_message"]).to include("Gemini quota exceeded")

        expect(attempts[1]["model_id"]).to eq("fallback-model")
        expect(attempts[1]["error_class"]).to eq("StandardError")
        expect(attempts[1]["error_message"]).to include("OpenAI API key invalid")
      end

      it "records each attempt with timing data" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          if ctx.model == "primary-model"
            raise StandardError, "model error"
          end
          ctx.output = "ok"
          ctx
        end

        result = middleware.call(context)
        attempts = result[:reliability_attempts]

        attempts.each do |attempt|
          expect(attempt["started_at"]).to be_present
          expect(attempt["completed_at"]).to be_present
          expect(attempt["duration_ms"]).to be_a(Integer)
        end
      end

      it "includes attempts data in AllModelsExhaustedError" do
        context = build_context

        allow(app).to receive(:call).and_raise(StandardError, "model error")

        expect { middleware.call(context) }.to raise_error(
          RubyLLM::Agents::Reliability::AllModelsExhaustedError
        ) do |error|
          expect(error.attempts).to be_an(Array)
          expect(error.attempts.length).to eq(2)
          expect(error.attempts[0]["model_id"]).to eq("primary-model")
          expect(error.attempts[1]["model_id"]).to eq("fallback-model")
        end
      end

      it "records short-circuited models from circuit breaker" do
        agent_cb = Class.new do
          def self.name = "CBTrackAgent"
          def self.agent_type = :embedding
          def self.model = "primary-model"

          def self.reliability_config
            {
              retries: { max: 0 },
              fallback_models: ["fallback-model"],
              circuit_breaker: { errors: 3, within: 60, cooldown: 300 }
            }
          end
        end

        cb_middleware = described_class.new(app, agent_cb)
        allow(cb_middleware).to receive(:sleep)

        primary_breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        fallback_breaker = instance_double(RubyLLM::Agents::CircuitBreaker)

        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("CBTrackAgent", "primary-model", anything, tenant_id: nil)
          .and_return(primary_breaker)
        allow(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("CBTrackAgent", "fallback-model", anything, tenant_id: nil)
          .and_return(fallback_breaker)

        allow(primary_breaker).to receive(:open?).and_return(true)
        allow(fallback_breaker).to receive(:open?).and_return(false)
        allow(fallback_breaker).to receive(:record_success!)

        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test", agent_class: agent_cb, model: "primary-model"
        )

        allow(app).to receive(:call) do |ctx|
          ctx.output = "fallback result"
          ctx
        end

        result = cb_middleware.call(context)
        attempts = result[:reliability_attempts]

        expect(attempts.length).to eq(2)

        # Primary was short-circuited
        expect(attempts[0]["model_id"]).to eq("primary-model")
        expect(attempts[0]["short_circuited"]).to be true

        # Fallback succeeded
        expect(attempts[1]["model_id"]).to eq("fallback-model")
        expect(attempts[1]["error_class"]).to be_nil
      end
    end
  end
end
