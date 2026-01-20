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

  # Helper to create a complete mock response
  def mock_llm_response(content: "Test response", input_tokens: 100, output_tokens: 50, model_id: "gpt-4")
    mock = double("RubyLLM::Message")
    allow(mock).to receive(:content).and_return(content)
    allow(mock).to receive(:input_tokens).and_return(input_tokens)
    allow(mock).to receive(:output_tokens).and_return(output_tokens)
    allow(mock).to receive(:model_id).and_return(model_id)
    allow(mock).to receive(:usage).and_return({
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0
    })
    allow(mock).to receive(:finish_reason).and_return("stop")
    allow(mock).to receive(:thinking).and_return(nil)
    allow(mock).to receive(:thinking_content).and_return(nil)
    allow(mock).to receive(:tool_call?).and_return(false)
    allow(mock).to receive(:tool_calls).and_return([])
    mock
  end

  describe "#instrument_execution" do
    let(:mock_response) { mock_llm_response }

    let(:mock_client) do
      double("RubyLLM::Chat", ask: mock_response)
    end

    # Shared config mock
    let(:config) { RubyLLM::Agents.configuration }

    before do
      # Enable tracking for these tests
      allow(config).to receive(:track_executions).and_return(true)
      allow(config).to receive(:async_logging).and_return(false)
    end

    context "successful execution" do
      before do
        allow(agent).to receive(:build_client).and_return(mock_client)
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
        allow(agent).to receive(:build_client).and_return(error_client)
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
        allow(agent).to receive(:build_client).and_return(timeout_client)
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

    let(:mock_response) { mock_llm_response(input_tokens: 10, output_tokens: 5) }

    let(:mock_chat) do
      chat = double("RubyLLM::Chat")
      allow(chat).to receive(:with_model).and_return(chat)
      allow(chat).to receive(:with_temperature).and_return(chat)
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_schema).and_return(chat)
      allow(chat).to receive(:with_tools).and_return(chat)
      allow(chat).to receive(:with_thinking).and_return(chat)
      allow(chat).to receive(:add_message).and_return(chat)
      allow(chat).to receive(:messages).and_return([])
      allow(chat).to receive(:ask).and_return(mock_response)
      chat
    end

    before do
      # Ensure we have a fresh configuration to mock
      RubyLLM::Agents.reset_configuration!
      allow(RubyLLM::Agents.configuration).to receive(:track_executions).and_return(true)
      allow(RubyLLM::Agents.configuration).to receive(:track_cache_hits).and_return(true)
      allow(RubyLLM::Agents.configuration).to receive(:async_logging).and_return(false)
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
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
    let(:mock_response) { mock_llm_response(input_tokens: 10, output_tokens: 5) }

    let(:mock_chat) do
      chat = double("RubyLLM::Chat")
      allow(chat).to receive(:with_model).and_return(chat)
      allow(chat).to receive(:with_temperature).and_return(chat)
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_schema).and_return(chat)
      allow(chat).to receive(:with_tools).and_return(chat)
      allow(chat).to receive(:with_thinking).and_return(chat)
      allow(chat).to receive(:add_message).and_return(chat)
      allow(chat).to receive(:messages).and_return([])
      allow(chat).to receive(:ask).and_return(mock_response)
      chat
    end

    before do
      # Ensure we have a fresh configuration to mock
      RubyLLM::Agents.reset_configuration!
      allow(RubyLLM::Agents.configuration).to receive(:track_executions).and_return(true)
      allow(RubyLLM::Agents.configuration).to receive(:track_cache_hits).and_return(true)
      allow(RubyLLM::Agents.configuration).to receive(:async_logging).and_return(false)
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
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
