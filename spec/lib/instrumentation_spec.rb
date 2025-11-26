# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Instrumentation do
  let(:test_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      agent_name "InstrumentationTestAgent"
      version "1.0.0"
      model "gpt-4"
      param :query, type: :string, required: true

      def user_prompt
        "Test: #{params[:query]}"
      end
    end
  end

  let(:agent) { test_agent_class.new(query: "test") }

  describe "#instrument_execution" do
    let(:mock_response) do
      double(
        content: "Test response",
        input_tokens: 100,
        output_tokens: 50,
        model_id: "gpt-4"
      )
    end

    before do
      allow(agent).to receive(:build_client).and_return(double(chat: mock_response))
    end

    context "successful execution" do
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
      before do
        allow(agent).to receive(:build_client).and_raise(StandardError.new("Test error"))
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
      before do
        allow(agent).to receive(:build_client).and_raise(Timeout::Error.new("Timed out"))
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
        agent_name "SensitiveAgent"
        version "1.0.0"
        model "gpt-4"
        param :password, type: :string
        param :api_key, type: :string
        param :query, type: :string

        def user_prompt
          "Test"
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

    before do
      allow(sensitive_agent).to receive(:build_client).and_return(
        double(chat: double(content: "response", input_tokens: 10, output_tokens: 5, model_id: "gpt-4"))
      )
    end

    it "sanitizes sensitive parameters" do
      sensitive_agent.call
      execution = RubyLLM::Agents::Execution.last
      params = execution.parameters

      expect(params["password"]).to eq("[FILTERED]")
      expect(params["api_key"]).to eq("[FILTERED]")
      expect(params["query"]).to eq("normal value")
    end
  end

  describe "duration tracking" do
    before do
      allow(agent).to receive(:build_client).and_return(
        double(chat: double(content: "response", input_tokens: 10, output_tokens: 5, model_id: "gpt-4"))
      )
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
