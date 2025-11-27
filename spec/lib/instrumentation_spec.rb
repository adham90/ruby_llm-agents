# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Instrumentation do
  let(:test_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      version "1.0.0"
      model "gpt-4"
      param :query, required: true

      def user_prompt
        "Test: #{query}"
      end

      # Anonymous classes don't have good names, so we define one
      def self.name
        "InstrumentationTestAgent"
      end
    end
  end

  let(:agent) { test_agent_class.new(query: "test") }

  describe "#instrument_execution" do
    let(:mock_response) do
      double(
        "RubyLLM::Message",
        content: "Test response",
        input_tokens: 100,
        output_tokens: 50,
        model_id: "gpt-4"
      )
    end

    let(:mock_client) do
      double("RubyLLM::Chat", ask: mock_response)
    end

    context "successful execution" do
      before do
        allow(agent).to receive(:client).and_return(mock_client)
      end

      it "creates an execution record" do
        expect {
          agent.call
        }.to change(RubyLLM::Agents::Execution, :count).by(1)
      end

      it "records correct agent type" do
        agent.call
        execution = RubyLLM::Agents::Execution.last
        expect(execution.agent_type).to eq("InstrumentationTestAgent")
      end

      it "records agent version" do
        agent.call
        execution = RubyLLM::Agents::Execution.last
        expect(execution.agent_version).to eq("1.0.0")
      end

      it "records status as success" do
        agent.call
        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("success")
      end

      it "records token usage" do
        agent.call
        execution = RubyLLM::Agents::Execution.last
        expect(execution.input_tokens).to eq(100)
        expect(execution.output_tokens).to eq(50)
      end
    end

    context "failed execution" do
      let(:error_client) do
        client = double("RubyLLM::Chat")
        allow(client).to receive(:ask).and_raise(StandardError.new("Test error"))
        client
      end

      before do
        allow(agent).to receive(:client).and_return(error_client)
      end

      it "records error status" do
        expect { agent.call }.to raise_error(StandardError)
        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
      end

      it "records error class" do
        expect { agent.call }.to raise_error(StandardError)
        execution = RubyLLM::Agents::Execution.last
        expect(execution.error_class).to eq("StandardError")
      end

      it "records error message" do
        expect { agent.call }.to raise_error(StandardError)
        execution = RubyLLM::Agents::Execution.last
        expect(execution.error_message).to eq("Test error")
      end
    end

    context "timeout execution" do
      let(:timeout_client) do
        client = double("RubyLLM::Chat")
        allow(client).to receive(:ask).and_raise(Timeout::Error.new("Timed out"))
        client
      end

      before do
        allow(agent).to receive(:client).and_return(timeout_client)
      end

      it "records timeout status" do
        expect { agent.call }.to raise_error(Timeout::Error)
        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("timeout")
      end
    end
  end

  describe "parameter sanitization" do
    let(:sensitive_agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        version "1.0.0"
        model "gpt-4"
        param :password
        param :api_key
        param :query

        def user_prompt
          "Test"
        end

        def self.name
          "SensitiveAgent"
        end
      end
    end

    let(:sensitive_agent) do
      sensitive_agent_class.new(
        password: "secret123",
        api_key: "sk-123456",
        query: "normal value"
      )
    end

    let(:mock_response) do
      double("RubyLLM::Message", content: "response", input_tokens: 10, output_tokens: 5, model_id: "gpt-4")
    end

    let(:mock_client) do
      double("RubyLLM::Chat", ask: mock_response)
    end

    before do
      allow(sensitive_agent).to receive(:client).and_return(mock_client)
    end

    it "sanitizes sensitive parameters" do
      sensitive_agent.call
      execution = RubyLLM::Agents::Execution.last
      params = execution.parameters

      expect(params["password"]).to eq("[REDACTED]")
      expect(params["api_key"]).to eq("[REDACTED]")
      expect(params["query"]).to eq("normal value")
    end
  end

  describe "duration tracking" do
    let(:mock_response) do
      double("RubyLLM::Message", content: "response", input_tokens: 10, output_tokens: 5, model_id: "gpt-4")
    end

    let(:mock_client) do
      double("RubyLLM::Chat", ask: mock_response)
    end

    before do
      allow(agent).to receive(:client).and_return(mock_client)
    end

    it "records start time" do
      agent.call
      execution = RubyLLM::Agents::Execution.last
      expect(execution.started_at).to be_present
    end

    it "records completion time" do
      agent.call
      execution = RubyLLM::Agents::Execution.last
      expect(execution.completed_at).to be_present
    end

    it "calculates duration in milliseconds" do
      agent.call
      execution = RubyLLM::Agents::Execution.last
      expect(execution.duration_ms).to be >= 0
    end
  end
end
