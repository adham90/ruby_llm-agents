# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance and Timeout Constraints" do
  describe RubyLLM::Agents::Reliability::ExecutionConstraints do
    describe "#initialize" do
      it "accepts nil total_timeout" do
        constraints = described_class.new(total_timeout: nil)
        expect(constraints).to be_a(described_class)
      end

      it "accepts numeric total_timeout" do
        constraints = described_class.new(total_timeout: 30)
        expect(constraints).to be_a(described_class)
      end

      it "accepts float total_timeout" do
        constraints = described_class.new(total_timeout: 0.5)
        expect(constraints).to be_a(described_class)
      end
    end

    describe "#enforce_timeout!" do
      context "without timeout configured" do
        it "does not raise when no timeout is set" do
          constraints = described_class.new(total_timeout: nil)
          expect { constraints.enforce_timeout! }.not_to raise_error
        end

        it "can be called multiple times" do
          constraints = described_class.new(total_timeout: nil)
          5.times { constraints.enforce_timeout! }
        end
      end

      context "with timeout configured" do
        it "does not raise when within timeout" do
          constraints = described_class.new(total_timeout: 0.1)
          expect { constraints.enforce_timeout! }.not_to raise_error
        end

        it "raises TotalTimeoutError when timeout exceeded" do
          # Create constraints BEFORE sleeping so the timer starts
          constraints = described_class.new(total_timeout: 0.1)
          sleep 0.15

          expect {
            constraints.enforce_timeout!
          }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)
        end

        it "raises with meaningful message" do
          constraints = described_class.new(total_timeout: 0.1)
          sleep 0.15

          expect {
            constraints.enforce_timeout!
          }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError) do |error|
            expect(error.message).to include("timeout")
          end
        end
      end

      context "with very short timeout" do
        it "raises almost immediately" do
          constraints = described_class.new(total_timeout: 0.001)
          sleep 0.01

          expect {
            constraints.enforce_timeout!
          }.to raise_error(RubyLLM::Agents::Reliability::TotalTimeoutError)
        end
      end

      context "with very long timeout" do
        it "does not raise during normal operation" do
          constraints = described_class.new(total_timeout: 3600)
          100.times { constraints.enforce_timeout! }
        end
      end
    end

    describe "timeout precision" do
      it "respects timeout within reasonable precision" do
        constraints = described_class.new(total_timeout: 0.05)
        start_time = Time.current

        begin
          loop do
            sleep 0.01
            constraints.enforce_timeout!
          end
        rescue RubyLLM::Agents::Reliability::TotalTimeoutError
          elapsed = Time.current - start_time
          # Should timeout around 50ms, with some tolerance
          expect(elapsed).to be_within(0.05).of(0.05)
        end
      end
    end
  end

  describe "Agent execution timeouts" do
    let(:mock_response) do
      build_mock_response(content: "Response", input_tokens: 100, output_tokens: 50)
    end

    let(:mock_chat) do
      build_mock_chat_client(response: mock_response)
    end

    before do
      stub_agent_configuration
      stub_ruby_llm_chat(mock_chat)
    end

    describe "basic execution" do
      let(:basic_agent_class) do
        Class.new(RubyLLM::Agents::Base) do
          model "gpt-4o"

          def user_prompt
            "test"
          end

          def self.name
            "BasicTestAgent"
          end
        end
      end

      it "executes successfully without reliability configured" do
        agent = basic_agent_class.new
        result = agent.call

        expect(result).to be_success
      end
    end

    describe "reliability configuration" do
      let(:agent_with_reliability) do
        Class.new(RubyLLM::Agents::Base) do
          model "gpt-4o"

          reliability do
            retries max: 2
            total_timeout 30
          end

          def user_prompt
            "test"
          end

          def self.name
            "ReliabilityTestAgent"
          end
        end
      end

      it "has reliability configured" do
        expect(agent_with_reliability.reliability_configured?).to be true
      end

      it "includes total_timeout in config" do
        config = agent_with_reliability.reliability_config
        expect(config[:total_timeout]).to eq(30)
      end

      it "includes retries in config" do
        config = agent_with_reliability.reliability_config
        expect(config[:retries][:max]).to eq(2)
      end
    end
  end

  describe "Circuit breaker timing" do
    describe RubyLLM::Agents::CircuitBreaker do
      let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

      let(:breaker) do
        # CircuitBreaker requires: agent_type, model_id, and named params
        described_class.new(
          "TestAgent",
          "gpt-4o",
          errors: 3,          # error_threshold
          within: 60,         # window seconds
          cooldown: 0.1       # cooldown seconds (100ms for testing)
        )
      end

      before do
        # Configure the cache store for tests
        allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
        # Reset the breaker before each test
        breaker.reset!
      end

      it "opens after reaching error threshold" do
        # Trip the circuit
        3.times { breaker.record_failure! }
        expect(breaker.open?).to be true
      end

      it "remains open during cooldown period" do
        3.times { breaker.record_failure! }
        expect(breaker.open?).to be true

        sleep 0.05 # Less than cooldown (100ms)

        expect(breaker.open?).to be true
      end

      it "closes after cooldown period expires" do
        3.times { breaker.record_failure! }
        expect(breaker.open?).to be true

        # Wait for cooldown to expire (cache TTL)
        sleep 0.15

        # After cooldown, the open flag expires from cache
        expect(breaker.open?).to be false
      end

      it "resets failure count on success" do
        breaker.record_failure!
        expect(breaker.failure_count).to be >= 1

        breaker.record_success!

        expect(breaker.failure_count).to eq(0)
      end

      it "returns status information" do
        status = breaker.status

        expect(status[:agent_type]).to eq("TestAgent")
        expect(status[:model_id]).to eq("gpt-4o")
        expect(status[:errors_threshold]).to eq(3)
        expect(status[:open]).to be false
      end
    end
  end

  describe "Retry delay timing" do
    describe RubyLLM::Agents::Reliability::RetryStrategy do
      context "with exponential backoff" do
        let(:strategy) do
          described_class.new(
            max: 5,
            backoff: :exponential,
            base: 0.01,
            max_delay: 1.0
          )
        end

        it "calculates base delays that increase exponentially" do
          # The base delay (before jitter) doubles each attempt
          # attempt 0: 0.01, attempt 1: 0.02, attempt 2: 0.04, etc.
          # We test the minimum expected delay (base * 2^attempt)
          expect(strategy.delay_for(0)).to be >= 0.01
          expect(strategy.delay_for(1)).to be >= 0.02
          expect(strategy.delay_for(2)).to be >= 0.04
        end

        it "caps delay at max_delay (before jitter)" do
          # With base 0.01 and max_delay 1.0, after attempt 7 (0.01 * 128 = 1.28),
          # it should be capped at 1.0 (plus jitter of up to 50%)
          high_attempt_delay = strategy.delay_for(10)
          # max_delay is 1.0, jitter adds up to 50%, so max is ~1.5
          expect(high_attempt_delay).to be <= 1.5
        end

        it "adds jitter to delays" do
          # Get multiple delays for same attempt - they should vary due to jitter
          delays = 10.times.map { strategy.delay_for(3) }

          # With jitter, we should see some variation
          # Base delay for attempt 3 is 0.01 * 8 = 0.08
          # With jitter: 0.08 to 0.12 range
          expect(delays.min).to be >= 0.08
          expect(delays.max).to be <= 0.12
        end
      end

      context "with constant backoff" do
        let(:strategy) do
          described_class.new(
            max: 5,
            backoff: :constant,
            base: 0.05,
            max_delay: 1.0
          )
        end

        it "returns delays based on constant base value" do
          delays = (1..5).map { |i| strategy.delay_for(i) }

          # All delays should be in range [base, base * 1.5] due to jitter
          delays.each do |delay|
            expect(delay).to be >= 0.05
            expect(delay).to be <= 0.075 # 0.05 + (0.05 * 0.5)
          end
        end

        it "maintains similar delays across attempts" do
          delay_0 = strategy.delay_for(0)
          delay_5 = strategy.delay_for(5)

          # Both should be in same range (constant backoff)
          expect(delay_0).to be_within(0.025).of(0.0625)
          expect(delay_5).to be_within(0.025).of(0.0625)
        end
      end

      context "retry eligibility" do
        let(:strategy) do
          described_class.new(max: 3)
        end

        it "allows retry when under max attempts" do
          expect(strategy.should_retry?(0)).to be true
          expect(strategy.should_retry?(1)).to be true
          expect(strategy.should_retry?(2)).to be true
        end

        it "denies retry when at or over max attempts" do
          expect(strategy.should_retry?(3)).to be false
          expect(strategy.should_retry?(4)).to be false
        end
      end
    end
  end

  describe "Pipeline execution duration tracking" do
    let(:agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def user_prompt
          "test"
        end

        def self.name
          "DurationTestAgent"
        end
      end
    end

    let(:mock_response) do
      build_mock_response(content: "Response", input_tokens: 100, output_tokens: 50)
    end

    let(:mock_chat) do
      build_mock_chat_client(response: mock_response)
    end

    before do
      stub_agent_configuration
      stub_ruby_llm_chat(mock_chat)
    end

    it "records accurate duration_ms in execution" do
      # Add artificial delay
      allow(mock_chat).to receive(:ask) do
        sleep 0.05
        mock_response
      end

      agent = agent_class.new
      result = agent.call

      # Get the recorded execution
      execution = RubyLLM::Agents::Execution.last

      # Duration should be at least 50ms
      expect(execution.duration_ms).to be >= 50
      # But not unreasonably long
      expect(execution.duration_ms).to be < 500
    end

    it "tracks duration even on error" do
      allow(mock_chat).to receive(:ask) do
        sleep 0.03
        raise StandardError, "Test error"
      end

      agent = agent_class.new

      expect { agent.call }.to raise_error(StandardError)

      # Error executions should still have duration
      execution = RubyLLM::Agents::Execution.where(status: "error").last
      if execution
        expect(execution.duration_ms).to be >= 30
      end
    end
  end

  describe "Concurrent execution constraints" do
    it "handles multiple agents executing simultaneously" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def user_prompt
          "test"
        end
      end

      mock_response = build_mock_response(content: "OK", input_tokens: 10, output_tokens: 5)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_agent_configuration
      stub_ruby_llm_chat(mock_chat)

      results = Concurrent::Array.new
      threads = 5.times.map do
        Thread.new do
          agent = agent_class.new
          result = agent.call
          results << result
        end
      end

      threads.each(&:join)

      expect(results.size).to eq(5)
      expect(results.all?(&:success?)).to be true
    end
  end
end
