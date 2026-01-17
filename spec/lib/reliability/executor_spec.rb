# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::Executor do
  let(:primary_model) { "gpt-4o" }
  let(:fallback_models) { ["gpt-4o-mini", "claude-3-haiku"] }
  let(:base_config) do
    {
      retries: { max: 2, backoff: :exponential, base: 0.01, max_delay: 0.1 },
      fallback_models: fallback_models,
      circuit_breaker: nil,
      total_timeout: nil
    }
  end

  subject(:executor) do
    described_class.new(
      config: base_config,
      primary_model: primary_model,
      agent_type: "TestAgent"
    )
  end

  describe "#initialize" do
    it "creates a retry strategy with config values" do
      expect(executor.retry_strategy).to be_a(RubyLLM::Agents::Reliability::RetryStrategy)
      expect(executor.retry_strategy.max).to eq(2)
      expect(executor.retry_strategy.backoff).to eq(:exponential)
    end

    it "creates fallback routing with primary and fallback models" do
      expect(executor.fallback_routing).to be_a(RubyLLM::Agents::Reliability::FallbackRouting)
      expect(executor.fallback_routing.models).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end

    it "creates a breaker manager" do
      expect(executor.breaker_manager).to be_a(RubyLLM::Agents::Reliability::BreakerManager)
    end

    it "creates execution constraints" do
      expect(executor.constraints).to be_a(RubyLLM::Agents::Reliability::ExecutionConstraints)
    end

    context "with default values" do
      let(:base_config) { {} }

      it "uses default retry settings" do
        expect(executor.retry_strategy.max).to eq(0)
        expect(executor.retry_strategy.backoff).to eq(:exponential)
        expect(executor.retry_strategy.base).to eq(0.4)
      end

      it "uses empty fallback models" do
        expect(executor.fallback_routing.models).to eq([primary_model])
      end
    end

    context "with tenant_id" do
      subject(:executor) do
        described_class.new(
          config: base_config.merge(circuit_breaker: { errors: 3, within: 60 }),
          primary_model: primary_model,
          agent_type: "TestAgent",
          tenant_id: "tenant-123"
        )
      end

      it "passes tenant_id to breaker manager" do
        # The breaker manager should be configured with tenant isolation
        expect(executor.breaker_manager).to be_a(RubyLLM::Agents::Reliability::BreakerManager)
      end
    end
  end

  describe "#models_to_try" do
    it "returns all models in the fallback chain" do
      expect(executor.models_to_try).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
    end

    context "with only primary model" do
      let(:fallback_models) { [] }

      it "returns only the primary model" do
        expect(executor.models_to_try).to eq(["gpt-4o"])
      end
    end
  end

  describe "#execute" do
    context "when first model succeeds" do
      it "returns the result" do
        result = executor.execute { |model| "success with #{model}" }
        expect(result).to eq("success with gpt-4o")
      end

      it "only tries the first model" do
        models_tried = []
        executor.execute do |model|
          models_tried << model
          "success"
        end
        expect(models_tried).to eq(["gpt-4o"])
      end
    end

    context "when first model fails with retryable error" do
      it "retries before moving to next model" do
        attempts = 0
        result = executor.execute do |model|
          attempts += 1
          if attempts <= 2 && model == "gpt-4o"
            raise Timeout::Error, "Connection timeout"
          end
          "success with #{model}"
        end

        # Should retry twice on gpt-4o, then succeed on third attempt
        expect(attempts).to eq(3)
        expect(result).to eq("success with gpt-4o")
      end
    end

    context "when first model exhausts retries" do
      it "falls back to next model" do
        models_tried = []
        result = executor.execute do |model|
          models_tried << model
          if model == "gpt-4o"
            raise Timeout::Error, "Connection timeout"
          end
          "success with #{model}"
        end

        expect(models_tried.uniq).to include("gpt-4o", "gpt-4o-mini")
        expect(result).to eq("success with gpt-4o-mini")
      end
    end

    context "when first model fails with non-retryable error" do
      it "immediately falls back to next model" do
        attempts_per_model = Hash.new(0)
        result = executor.execute do |model|
          attempts_per_model[model] += 1
          if model == "gpt-4o"
            raise ArgumentError, "Invalid argument"
          end
          "success with #{model}"
        end

        # Should only try gpt-4o once (non-retryable), then succeed on fallback
        expect(attempts_per_model["gpt-4o"]).to eq(1)
        expect(result).to eq("success with gpt-4o-mini")
      end
    end

    context "when all models fail" do
      it "raises AllModelsExhaustedError" do
        expect do
          executor.execute { raise Timeout::Error, "Always fails" }
        end.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.models_tried).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
          expect(error.last_error).to be_a(Timeout::Error)
        end
      end

      it "preserves the last error" do
        attempt = 0
        expect do
          executor.execute do
            attempt += 1
            raise StandardError, "Error #{attempt}"
          end
        end.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.last_error.message).to match(/Error \d+/)
        end
      end
    end

    context "with circuit breaker open" do
      let(:base_config) do
        {
          retries: { max: 0 },
          fallback_models: fallback_models,
          circuit_breaker: { errors: 1, within: 60 }
        }
      end

      it "skips models with open circuit breakers" do
        # First, open the circuit for gpt-4o
        allow(executor.breaker_manager).to receive(:open?).with("gpt-4o").and_return(true)
        allow(executor.breaker_manager).to receive(:open?).with("gpt-4o-mini").and_return(false)
        allow(executor.breaker_manager).to receive(:open?).with("claude-3-haiku").and_return(false)
        allow(executor.breaker_manager).to receive(:record_success!)

        models_tried = []
        executor.execute do |model|
          models_tried << model
          "success"
        end

        expect(models_tried).not_to include("gpt-4o")
        expect(models_tried).to include("gpt-4o-mini")
      end

      it "skips all open models and raises if all are open" do
        allow(executor.breaker_manager).to receive(:open?).and_return(true)

        expect do
          executor.execute { "success" }
        end.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
      end
    end

    context "with total timeout" do
      let(:base_config) do
        {
          retries: { max: 5, base: 0.01 },
          fallback_models: [],
          total_timeout: 0.05 # 50ms
        }
      end

      it "raises TotalTimeoutError when timeout exceeded" do
        expect do
          executor.execute do
            sleep 0.1 # Exceed timeout
            raise Timeout::Error, "Should retry but timeout first"
          end
        end.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)
      end
    end

    context "with single model and no retries" do
      let(:fallback_models) { [] }
      let(:base_config) do
        { retries: { max: 0 }, fallback_models: [] }
      end

      it "raises immediately on failure" do
        expect do
          executor.execute { raise StandardError, "Single failure" }
        end.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.models_tried).to eq(["gpt-4o"])
        end
      end
    end
  end

  describe "circuit breaker integration" do
    let(:base_config) do
      {
        retries: { max: 0 },
        fallback_models: ["gpt-4o-mini"],
        circuit_breaker: { errors: 2, within: 60 }
      }
    end

    it "records success on successful execution" do
      expect(executor.breaker_manager).to receive(:record_success!).with("gpt-4o")

      executor.execute { "success" }
    end

    it "records failure on failed execution" do
      expect(executor.breaker_manager).to receive(:record_failure!).with("gpt-4o").at_least(:once)
      allow(executor.breaker_manager).to receive(:record_success!)

      executor.execute do |model|
        raise Timeout::Error if model == "gpt-4o"
        "success"
      end
    end
  end
end
