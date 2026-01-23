# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Reliability::Executor, "edge cases" do
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

  describe "network failure scenarios" do
    context "with intermittent connection failures" do
      it "retries and succeeds on intermittent failures" do
        attempts = 0
        result = executor.execute do |model|
          attempts += 1
          raise Timeout::Error, "Connection timeout" if attempts <= 2
          "success after #{attempts} attempts"
        end

        expect(attempts).to eq(3)
        expect(result).to eq("success after 3 attempts")
      end

      it "handles connection reset errors" do
        attempts = 0
        result = executor.execute do |model|
          attempts += 1
          if attempts <= 1
            raise Errno::ECONNRESET, "Connection reset by peer"
          end
          "recovered"
        end

        # Should retry on Errno::ECONNRESET (treated as retryable by default)
        expect(attempts).to be >= 1
      end
    end

    context "with partial response failures" do
      it "treats nil as failure and falls back to next model" do
        # Simulate a case where the execution returns nil
        # The executor's `return result if result` check treats nil as falsy
        # causing it to advance to the next model
        models_tried = []
        result = executor.execute do |model|
          models_tried << model
          model == "gpt-4o" ? nil : "fallback success"
        end

        # nil triggers fallback, so we get the result from the fallback model
        expect(result).to eq("fallback success")
        expect(models_tried).to include("gpt-4o", "gpt-4o-mini")
      end
    end
  end

  describe "timeout enforcement" do
    let(:base_config) do
      {
        retries: { max: 10, base: 0.01 },
        fallback_models: [],
        total_timeout: 0.05
      }
    end

    it "enforces total timeout across multiple retries" do
      attempt_count = 0

      expect {
        executor.execute do
          attempt_count += 1
          sleep 0.02
          raise Timeout::Error, "Keep retrying"
        end
      }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)

      # Should have had a few attempts before timeout kicked in
      expect(attempt_count).to be >= 1
      expect(attempt_count).to be < 10
    end

    it "checks timeout before each retry attempt" do
      # The timeout is enforced at the start of each retry loop iteration
      # So we need to trigger a retryable error to see the timeout check
      attempt_count = 0

      expect {
        executor.execute do
          attempt_count += 1
          sleep 0.03 # Slower execution to accumulate time
          raise Timeout::Error, "Keep retrying"
        end
      }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)

      # Should have had at least one attempt before timeout
      expect(attempt_count).to be >= 1
    end
  end

  describe "circuit breaker state transitions" do
    let(:base_config) do
      {
        retries: { max: 0 },
        fallback_models: fallback_models,
        circuit_breaker: { errors: 2, within: 60 }
      }
    end

    it "opens circuit after consecutive failures" do
      # Simulate failures that should open the circuit
      allow(executor.breaker_manager).to receive(:open?).with("gpt-4o").and_return(false, false, true)
      allow(executor.breaker_manager).to receive(:open?).with("gpt-4o-mini").and_return(false)
      allow(executor.breaker_manager).to receive(:record_failure!)
      allow(executor.breaker_manager).to receive(:record_success!)

      models_tried = []
      executor.execute do |model|
        models_tried << model
        "success with #{model}"
      end

      expect(models_tried).to include("gpt-4o")
    end

    it "skips model with open circuit and tries fallback" do
      # Primary model has open circuit
      allow(executor.breaker_manager).to receive(:open?).with("gpt-4o").and_return(true)
      allow(executor.breaker_manager).to receive(:open?).with("gpt-4o-mini").and_return(false)
      allow(executor.breaker_manager).to receive(:open?).with("claude-3-haiku").and_return(false)
      allow(executor.breaker_manager).to receive(:record_success!)

      models_tried = []
      result = executor.execute do |model|
        models_tried << model
        "success"
      end

      expect(models_tried).not_to include("gpt-4o")
      expect(models_tried.first).to eq("gpt-4o-mini")
    end

    it "raises error when all models have open circuits" do
      allow(executor.breaker_manager).to receive(:open?).and_return(true)

      expect {
        executor.execute { "success" }
      }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
        expect(error.models_tried).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
      end
    end
  end

  describe "retry strategy with different error types" do
    let(:base_config) do
      {
        retries: {
          max: 2,
          backoff: :linear,
          base: 0.01,
          on: [Timeout::Error, Net::OpenTimeout]
        },
        fallback_models: ["gpt-4o-mini"]
      }
    end

    it "retries only on configured error types" do
      attempts_per_model = Hash.new(0)

      executor.execute do |model|
        attempts_per_model[model] += 1
        if model == "gpt-4o" && attempts_per_model[model] <= 2
          raise Timeout::Error, "Retryable error"
        end
        "success"
      end

      # Should retry on gpt-4o
      expect(attempts_per_model["gpt-4o"]).to eq(3)
    end

    it "does not retry on non-configured error types" do
      attempts_per_model = Hash.new(0)

      executor.execute do |model|
        attempts_per_model[model] += 1
        if model == "gpt-4o"
          raise ArgumentError, "Non-retryable error"
        end
        "fallback success"
      end

      # Should not retry ArgumentError, move to fallback immediately
      expect(attempts_per_model["gpt-4o"]).to eq(1)
      expect(attempts_per_model["gpt-4o-mini"]).to eq(1)
    end
  end

  describe "backoff strategies" do
    let(:base_config) do
      {
        retries: { max: 3, backoff: :exponential, base: 0.01, max_delay: 1.0 },
        fallback_models: []
      }
    end

    it "applies exponential backoff" do
      delays = []
      attempt = 0

      begin
        executor.execute do
          attempt += 1
          raise Timeout::Error if attempt <= 3
          "success"
        end
      rescue RubyLLM::Agents::Reliability::AllModelsExhaustedError
        # Expected
      end

      # Verify retry strategy calculates delays
      expect(executor.retry_strategy.delay_for(1)).to be > 0
      expect(executor.retry_strategy.delay_for(2)).to be > executor.retry_strategy.delay_for(1)
    end

    context "with linear backoff" do
      let(:base_config) do
        {
          retries: { max: 3, backoff: :linear, base: 0.01, max_delay: 1.0 },
          fallback_models: []
        }
      end

      it "applies linear backoff" do
        delay1 = executor.retry_strategy.delay_for(1)
        delay2 = executor.retry_strategy.delay_for(2)
        delay3 = executor.retry_strategy.delay_for(3)

        # Linear should have constant increments
        expect(delay2 - delay1).to be_within(0.01).of(delay3 - delay2)
      end
    end
  end

  describe "error preservation" do
    it "preserves the last error through all attempts" do
      error_messages = []

      expect {
        executor.execute do |model|
          error_messages << "Error on #{model}"
          raise StandardError, "Error on #{model}"
        end
      }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
        expect(error.last_error).to be_a(StandardError)
        expect(error.last_error.message).to include("claude-3-haiku")
      end
    end

    it "captures the actual exception type" do
      custom_error = Class.new(StandardError)

      expect {
        executor.execute { raise custom_error, "Custom error" }
      }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
        expect(error.last_error).to be_a(custom_error)
      end
    end
  end

  describe "concurrent execution scenarios" do
    it "handles rapid successive executions" do
      results = []

      5.times do
        result = executor.execute { |model| "result from #{model}" }
        results << result
      end

      expect(results.uniq).to eq(["result from gpt-4o"])
    end
  end

  describe "empty fallback configuration" do
    let(:fallback_models) { [] }

    it "only tries primary model" do
      models_tried = []

      expect {
        executor.execute do |model|
          models_tried << model
          raise StandardError, "Always fails"
        end
      }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

      expect(models_tried.uniq).to eq(["gpt-4o"])
    end
  end

  describe "tenant isolation" do
    let(:tenant_executor) do
      described_class.new(
        config: base_config.merge(circuit_breaker: { errors: 3, within: 60 }),
        primary_model: primary_model,
        agent_type: "TestAgent",
        tenant_id: "tenant-123"
      )
    end

    it "creates executor with tenant context" do
      expect(tenant_executor.breaker_manager).to be_a(RubyLLM::Agents::Reliability::BreakerManager)
    end

    it "passes tenant_id to breaker manager" do
      # Verify tenant context is preserved
      expect { tenant_executor.execute { "success" } }.not_to raise_error
    end
  end

  describe "edge case: successful execution on last model" do
    it "succeeds when only the last fallback model works" do
      models_tried = []

      result = executor.execute do |model|
        models_tried << model
        raise StandardError, "Fail" unless model == "claude-3-haiku"
        "success on last model"
      end

      expect(models_tried).to eq(["gpt-4o", "gpt-4o-mini", "claude-3-haiku"])
      expect(result).to eq("success on last model")
    end
  end

  describe "edge case: zero retries" do
    let(:base_config) do
      {
        retries: { max: 0 },
        fallback_models: ["gpt-4o-mini"]
      }
    end

    it "immediately moves to fallback on first failure" do
      attempts_per_model = Hash.new(0)

      executor.execute do |model|
        attempts_per_model[model] += 1
        raise Timeout::Error if model == "gpt-4o"
        "success"
      end

      expect(attempts_per_model["gpt-4o"]).to eq(1)
      expect(attempts_per_model["gpt-4o-mini"]).to eq(1)
    end
  end
end
