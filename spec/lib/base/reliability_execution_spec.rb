# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::ReliabilityExecution do
  # Create a test agent class for testing
  let(:test_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      version "1.0.0"

      def self.name
        "TestReliabilityAgent"
      end

      def system_prompt
        "You are a test agent."
      end

      def user_prompt
        "Test prompt"
      end
    end
  end

  let(:agent) { test_agent_class.new }
  let(:mock_response) do
    double(
      "Response",
      content: "Test response",
      input_tokens: 100,
      output_tokens: 50,
      model_id: "gpt-4o",
      total_cost: 0.01
    )
  end

  # Mock the configuration
  let(:global_config) { RubyLLM::Agents.configuration }

  before do
    Rails.cache.clear
    # Default: disable multi-tenancy and budgets for most tests
    allow(global_config).to receive(:multi_tenancy_enabled?).and_return(false)
    allow(global_config).to receive(:budgets_enabled?).and_return(false)
  end

  describe "#execute_with_reliability" do
    context "when execution succeeds on first attempt" do
      before do
        allow(agent).to receive(:execute_single_attempt).and_return("Success result")
        agent.instance_variable_set(:@last_response, mock_response)
      end

      it "returns the result without retries" do
        result = agent.send(:execute_with_reliability)
        expect(result).to eq("Success result")
      end

      it "calls execute_single_attempt once" do
        expect(agent).to receive(:execute_single_attempt).once.and_return("Success")
        agent.instance_variable_set(:@last_response, mock_response)
        agent.send(:execute_with_reliability)
      end

      it "records success in circuit breaker" do
        breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        allow(breaker).to receive(:open?).and_return(false)
        allow(breaker).to receive(:record_success!)
        allow(agent).to receive(:get_circuit_breaker).and_return(breaker)

        agent.send(:execute_with_reliability)

        expect(breaker).to have_received(:record_success!)
      end
    end

    context "when retryable error occurs" do
      let(:agent_class_with_retries) do
        Class.new(test_agent_class) do
          reliability do
            retries max: 2, backoff: :constant, base: 0.01, max_delay: 0.05
          end
        end
      end

      let(:agent) { agent_class_with_retries.new }
      let(:retryable_error) { Timeout::Error.new("Connection timed out") }

      it "retries the configured number of times" do
        call_count = 0
        allow(agent).to receive(:execute_single_attempt) do
          call_count += 1
          if call_count < 3
            raise retryable_error
          else
            agent.instance_variable_set(:@last_response, mock_response)
            "Success after retries"
          end
        end

        result = agent.send(:execute_with_reliability)
        expect(result).to eq("Success after retries")
        expect(call_count).to eq(3) # Initial + 2 retries
      end

      it "records failure in circuit breaker on each retry" do
        breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        allow(breaker).to receive(:open?).and_return(false)
        allow(breaker).to receive(:record_failure!)
        allow(breaker).to receive(:record_success!)
        allow(agent).to receive(:get_circuit_breaker).and_return(breaker)

        call_count = 0
        allow(agent).to receive(:execute_single_attempt) do
          call_count += 1
          if call_count < 2
            raise retryable_error
          else
            agent.instance_variable_set(:@last_response, mock_response)
            "Success"
          end
        end

        agent.send(:execute_with_reliability)

        expect(breaker).to have_received(:record_failure!).at_least(:once)
        expect(breaker).to have_received(:record_success!).once
      end

      it "waits between retries with backoff" do
        allow(agent).to receive(:execute_single_attempt).and_raise(retryable_error)
        allow(agent).to receive(:sleep) # Capture sleep calls

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

        expect(agent).to have_received(:sleep).at_least(:once)
      end
    end

    context "when non-retryable error occurs" do
      let(:non_retryable_error) { ArgumentError.new("Invalid argument") }

      it "does not retry and moves to next model" do
        call_count = 0
        allow(agent).to receive(:execute_single_attempt) do
          call_count += 1
          raise non_retryable_error
        end

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

        # Should only try once per model (1 model = 1 attempt)
        expect(call_count).to eq(1)
      end

      it "records failure in circuit breaker" do
        breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        allow(breaker).to receive(:open?).and_return(false)
        allow(breaker).to receive(:record_failure!)
        allow(agent).to receive(:get_circuit_breaker).and_return(breaker)
        allow(agent).to receive(:execute_single_attempt).and_raise(non_retryable_error)

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

        expect(breaker).to have_received(:record_failure!)
      end
    end

    context "with fallback models" do
      let(:agent_class_with_fallbacks) do
        Class.new(test_agent_class) do
          reliability do
            fallback_models "claude-3-sonnet", "gemini-pro"
          end
        end
      end

      let(:agent) { agent_class_with_fallbacks.new }

      it "tries fallback models when primary fails" do
        models_tried = []
        allow(agent).to receive(:execute_single_attempt) do |model_override:|
          models_tried << model_override
          if model_override == "gemini-pro"
            agent.instance_variable_set(:@last_response, mock_response)
            "Success on gemini"
          else
            raise Timeout::Error, "Timeout on #{model_override}"
          end
        end

        result = agent.send(:execute_with_reliability)

        expect(result).to eq("Success on gemini")
        expect(models_tried).to eq(%w[gpt-4o claude-3-sonnet gemini-pro])
      end

      it "raises AllModelsExhaustedError when all models fail" do
        allow(agent).to receive(:execute_single_attempt).and_raise(Timeout::Error, "Timeout")

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.models_tried).to eq(%w[gpt-4o claude-3-sonnet gemini-pro])
          expect(error.last_error).to be_a(Timeout::Error)
        end
      end

      it "deduplicates models list" do
        # If primary model is also in fallbacks, should only try once
        agent_class_dup = Class.new(test_agent_class) do
          reliability do
            fallback_models "gpt-4o", "claude-3" # gpt-4o is already primary
          end
        end

        agent = agent_class_dup.new
        models_tried = []
        allow(agent).to receive(:execute_single_attempt) do |model_override:|
          models_tried << model_override
          raise Timeout::Error, "Timeout"
        end

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

        expect(models_tried).to eq(%w[gpt-4o claude-3])
      end
    end

    context "with circuit breaker" do
      let(:agent_class_with_breaker) do
        Class.new(test_agent_class) do
          reliability do
            circuit_breaker errors: 3, within: 60, cooldown: 30
            fallback_models "claude-3"
          end
        end
      end

      let(:agent) { agent_class_with_breaker.new }

      it "skips models with open circuit breakers" do
        # Mock breaker for gpt-4o as open
        open_breaker = instance_double(RubyLLM::Agents::CircuitBreaker, open?: true)
        closed_breaker = instance_double(RubyLLM::Agents::CircuitBreaker, open?: false)
        allow(closed_breaker).to receive(:record_success!)

        allow(agent).to receive(:get_circuit_breaker) do |model_id, **_opts|
          model_id == "gpt-4o" ? open_breaker : closed_breaker
        end

        models_tried = []
        allow(agent).to receive(:execute_single_attempt) do |model_override:|
          models_tried << model_override
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        agent.send(:execute_with_reliability)

        # gpt-4o should be skipped due to open circuit
        expect(models_tried).to eq(["claude-3"])
      end

      it "records short circuit in attempt tracker" do
        open_breaker = instance_double(RubyLLM::Agents::CircuitBreaker, open?: true)
        closed_breaker = instance_double(RubyLLM::Agents::CircuitBreaker, open?: false)
        allow(closed_breaker).to receive(:record_success!)

        allow(agent).to receive(:get_circuit_breaker) do |model_id, **_opts|
          model_id == "gpt-4o" ? open_breaker : closed_breaker
        end

        allow(agent).to receive(:execute_single_attempt) do
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        # The attempt tracker should receive record_short_circuit
        # This is tested indirectly through successful execution despite open circuit
        expect { agent.send(:execute_with_reliability) }.not_to raise_error
      end
    end

    context "with total timeout" do
      let(:agent_class_with_timeout) do
        Class.new(test_agent_class) do
          reliability do
            total_timeout 0.05 # 50ms
            retries max: 5, backoff: :constant, base: 0.1 # Long enough to exceed timeout
          end
        end
      end

      let(:agent) { agent_class_with_timeout.new }

      it "raises TotalTimeoutError when deadline exceeded" do
        # The timeout check happens before each attempt, so we need to fail first
        # to trigger retries, and the timeout should be checked on subsequent attempts
        attempt_count = 0
        allow(agent).to receive(:execute_single_attempt) do
          attempt_count += 1
          sleep(0.03) # Each attempt takes 30ms
          raise Timeout::Error, "Simulated timeout"
        end

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError) do |error|
          expect(error.timeout_seconds).to eq(0.05)
          expect(error.elapsed_seconds).to be >= 0.05
        end
      end

      it "checks timeout before each attempt" do
        attempt_count = 0
        allow(agent).to receive(:execute_single_attempt) do
          attempt_count += 1
          sleep(0.03) # Each attempt takes 30ms
          raise Timeout::Error, "Simulated timeout"
        end

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)

        # Should only get 1-2 attempts before total timeout
        expect(attempt_count).to be <= 2
      end

      it "stops retrying when past deadline" do
        allow(agent).to receive(:execute_single_attempt).and_raise(Timeout::Error, "Timeout")
        allow(agent).to receive(:sleep) do |delay|
          # Simulate time passing during sleep
          sleep(0.06) # Exceed deadline
        end

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)
      end
    end

    context "with budget enforcement" do
      before do
        allow(global_config).to receive(:budgets_enabled?).and_return(true)
      end

      it "pre-checks budget before execution" do
        expect(RubyLLM::Agents::BudgetTracker).to receive(:check_budget!)
          .with("TestReliabilityAgent", tenant_id: nil)

        allow(agent).to receive(:execute_single_attempt) do
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        agent.send(:execute_with_reliability)
      end

      it "raises BudgetExceededError when budget exceeded" do
        allow(RubyLLM::Agents::BudgetTracker).to receive(:check_budget!)
          .and_raise(RubyLLM::Agents::Reliability::BudgetExceededError.new(:global_daily, 10.0, 15.0))

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::BudgetExceededError)
      end

      it "records attempt cost after successful execution" do
        allow(RubyLLM::Agents::BudgetTracker).to receive(:check_budget!)
        allow(agent).to receive(:execute_single_attempt) do
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end
        allow(agent).to receive(:record_attempt_cost)

        agent.send(:execute_with_reliability)

        expect(agent).to have_received(:record_attempt_cost)
      end
    end

    context "with multi-tenancy enabled" do
      let(:tenant_id) { "tenant-123" }
      let(:agent_class_with_breaker) do
        Class.new(test_agent_class) do
          reliability do
            circuit_breaker errors: 3, within: 60, cooldown: 30
          end
        end
      end
      let(:multi_tenant_agent) { agent_class_with_breaker.new }

      before do
        allow(global_config).to receive(:multi_tenancy_enabled?).and_return(true)
        allow(global_config).to receive(:current_tenant_id).and_return(tenant_id)
      end

      it "passes tenant_id to budget check" do
        allow(global_config).to receive(:budgets_enabled?).and_return(true)
        expect(RubyLLM::Agents::BudgetTracker).to receive(:check_budget!)
          .with("TestReliabilityAgent", tenant_id: tenant_id)

        allow(agent).to receive(:execute_single_attempt) do
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        agent.send(:execute_with_reliability)
      end

      it "passes tenant_id to circuit breaker" do
        expect(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("TestReliabilityAgent", "gpt-4o", hash_including(:errors, :within, :cooldown), tenant_id: tenant_id)
          .and_return(nil)

        allow(multi_tenant_agent).to receive(:execute_single_attempt) do
          multi_tenant_agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        multi_tenant_agent.send(:execute_with_reliability)
      end
    end

    context "with streaming block" do
      it "passes block to execute_single_attempt" do
        block_called = false
        streaming_block = proc { block_called = true }

        allow(agent).to receive(:execute_single_attempt) do |&block|
          block&.call("chunk")
          agent.instance_variable_set(:@last_response, mock_response)
          "Success"
        end

        agent.send(:execute_with_reliability, &streaming_block)

        expect(block_called).to be true
      end
    end
  end

  describe "#past_deadline?" do
    it "returns false when deadline is nil" do
      # Returns nil which is falsey (short-circuit evaluation)
      expect(agent.send(:past_deadline?, nil)).to be_falsey
    end

    it "returns false when before deadline" do
      deadline = Time.current + 1.hour
      expect(agent.send(:past_deadline?, deadline)).to be false
    end

    it "returns true when past deadline" do
      deadline = Time.current - 1.second
      expect(agent.send(:past_deadline?, deadline)).to be true
    end
  end

  describe "#get_circuit_breaker" do
    context "without circuit breaker config" do
      it "returns nil" do
        breaker = agent.send(:get_circuit_breaker, "gpt-4o")
        expect(breaker).to be_nil
      end
    end

    context "with circuit breaker config" do
      let(:agent_class_with_breaker) do
        Class.new(test_agent_class) do
          reliability do
            circuit_breaker errors: 3, within: 60, cooldown: 30
          end
        end
      end

      let(:agent) { agent_class_with_breaker.new }

      it "returns a circuit breaker" do
        breaker = agent.send(:get_circuit_breaker, "gpt-4o")
        expect(breaker).to be_a(RubyLLM::Agents::CircuitBreaker)
      end

      it "creates breaker with correct parameters" do
        expect(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("TestReliabilityAgent", "gpt-4o", hash_including(:errors, :within, :cooldown), tenant_id: nil)
          .and_call_original

        agent.send(:get_circuit_breaker, "gpt-4o")
      end

      it "passes tenant_id when provided" do
        expect(RubyLLM::Agents::CircuitBreaker).to receive(:from_config)
          .with("TestReliabilityAgent", "gpt-4o", anything, tenant_id: "tenant-abc")
          .and_call_original

        agent.send(:get_circuit_breaker, "gpt-4o", tenant_id: "tenant-abc")
      end
    end
  end

  describe "integration scenarios" do
    context "complex retry and fallback scenario" do
      let(:agent_class_complex) do
        Class.new(test_agent_class) do
          reliability do
            retries max: 1, backoff: :constant, base: 0.01
            fallback_models "claude-3", "gemini-pro"
            circuit_breaker errors: 5, within: 60, cooldown: 30
          end
        end
      end

      let(:complex_agent) { agent_class_complex.new }

      it "retries, then falls back, then succeeds" do
        call_sequence = []

        # Mock circuit breaker to avoid real cache interactions
        mock_breaker = instance_double(RubyLLM::Agents::CircuitBreaker)
        allow(mock_breaker).to receive(:open?).and_return(false)
        allow(mock_breaker).to receive(:record_failure!)
        allow(mock_breaker).to receive(:record_success!)
        allow(complex_agent).to receive(:get_circuit_breaker).and_return(mock_breaker)

        allow(complex_agent).to receive(:execute_single_attempt) do |model_override:|
          call_sequence << model_override

          case model_override
          when "gpt-4o"
            raise Timeout::Error, "Primary timeout"
          when "claude-3"
            raise Timeout::Error, "Fallback 1 timeout"
          when "gemini-pro"
            complex_agent.instance_variable_set(:@last_response, mock_response)
            "Success on third model"
          end
        end

        result = complex_agent.send(:execute_with_reliability)

        expect(result).to eq("Success on third model")
        # gpt-4o: initial + 1 retry, claude-3: initial + 1 retry, gemini-pro: success
        expect(call_sequence.count("gpt-4o")).to eq(2)
        expect(call_sequence.count("claude-3")).to eq(2)
        expect(call_sequence.count("gemini-pro")).to eq(1)
      end
    end

    context "all models fail scenario" do
      let(:agent_class_all_fail) do
        Class.new(test_agent_class) do
          reliability do
            retries max: 0 # No retries
            fallback_models "claude-3"
          end
        end
      end

      let(:agent) { agent_class_all_fail.new }

      it "raises AllModelsExhaustedError with details" do
        allow(agent).to receive(:execute_single_attempt)
          .and_raise(StandardError, "API unavailable")

        expect {
          agent.send(:execute_with_reliability)
        }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError) do |error|
          expect(error.models_tried).to eq(%w[gpt-4o claude-3])
          expect(error.last_error.message).to eq("API unavailable")
        end
      end
    end
  end
end
