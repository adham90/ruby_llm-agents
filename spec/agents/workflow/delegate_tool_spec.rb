# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DelegateTool do
  let(:mock_response) { build_mock_response(content: "Research findings", input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: false)
  end

  let(:research_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "ResearchAgent"
      model "gpt-4o"
      param :_ask_message, required: false
      user "{_ask_message}"
    end
  end

  let(:writer_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "WriterAgent"
      model "gpt-4o"
      param :_ask_message, required: false
      user "{_ask_message}"
    end
  end

  describe ".for" do
    it "creates a configured tool class" do
      context = RubyLLM::Agents::Workflow::WorkflowContext.new
      tool_class = described_class.for(
        agents: {researcher: research_agent, writer: writer_agent},
        context: context
      )

      expect(tool_class).to be < described_class
    end
  end

  describe "#execute" do
    let(:context) { RubyLLM::Agents::Workflow::WorkflowContext.new }
    let(:tool_class) do
      described_class.for(
        agents: {researcher: research_agent, writer: writer_agent},
        context: context
      )
    end

    it "delegates to the named agent and returns content" do
      tool = tool_class.new
      result = tool.execute(agent: "researcher", input: "Find info on AI")

      expect(result).to be_a(String)
    end

    it "stores result in context" do
      tool = tool_class.new
      tool.execute(agent: "researcher", input: "Find info on AI")

      # Should have stored a result in context
      expect(context.step_results.size).to eq(1)
    end

    it "returns error for unknown agent" do
      tool = tool_class.new
      result = tool.execute(agent: "unknown_agent", input: "test")

      expect(result).to include("Unknown agent")
      expect(result).to include("researcher, writer")
    end

    it "handles agent execution errors gracefully" do
      allow(research_agent).to receive(:call).and_raise(StandardError, "API error")

      tool = tool_class.new
      result = tool.execute(agent: "researcher", input: "test")

      expect(result).to include("Error from researcher")
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::CompleteTool do
  describe "#execute" do
    it "sets thread-local completion signal" do
      tool = described_class.new
      result = tool.execute(result: "All work is done")

      expect(Thread.current[:workflow_supervisor_complete]).to be true
      expect(Thread.current[:workflow_supervisor_result]).to eq("All work is done")
      expect(result).to include("completed successfully")
    ensure
      Thread.current[:workflow_supervisor_complete] = nil
      Thread.current[:workflow_supervisor_result] = nil
    end
  end
end
