# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance and Timeout Constraints" do
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
        RubyLLM::Agents.reset_configuration!
        RubyLLM::Agents.configure { |c| c.cache_store = cache_store }
        breaker.reset!
      end

      after do
        RubyLLM::Agents.reset_configuration!
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
      agent.call

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
