# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow supervisor mode" do
  let(:mock_response) { build_mock_response(content: "Result", input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: false)
  end

  let(:orchestrator_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "OrchestratorAgent"
      model "gpt-4o"
      description "Orchestrates research and writing"

      system "You are a supervisor. Delegate tasks to available agents."
    end
  end

  let(:research_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "ResearchAgent"
      model "gpt-4o"
      description "Researches topics"
      param :_ask_message, required: false
      user "{_ask_message}"
    end
  end

  let(:writer_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "WriterAgent"
      model "gpt-4o"
      description "Writes content"
      param :_ask_message, required: false
      user "{_ask_message}"
    end
  end

  describe "DSL" do
    it "configures supervisor with agent and max_turns" do
      oa = orchestrator_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa, max_turns: 5
      }

      expect(wf.supervisor_mode?).to be true
      expect(wf.supervisor_config[:agent_class]).to eq(oa)
      expect(wf.supervisor_config[:max_turns]).to eq(5)
    end

    it "defaults max_turns to 10" do
      oa = orchestrator_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa
      }

      expect(wf.supervisor_config[:max_turns]).to eq(10)
    end

    it "registers delegate agents" do
      oa = orchestrator_agent
      ra = research_agent
      wa = writer_agent

      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa
        delegate :researcher, ra
        delegate :writer, wa
      }

      expect(wf.delegate_agents).to eq({researcher: ra, writer: wa})
    end
  end

  describe "supervisor execution" do
    it "runs the supervisor loop and collects results" do
      # Make the supervisor "call complete" on first turn
      call_count = 0
      oa = orchestrator_agent
      allow(oa).to receive(:ask) do |message, **opts|
        call_count += 1
        # Simulate calling the complete tool
        Thread.current[:workflow_supervisor_complete] = true
        Thread.current[:workflow_supervisor_result] = "All done"

        RubyLLM::Agents::Result.new(
          content: "Delegated and completed",
          input_tokens: 50,
          output_tokens: 25,
          model_id: "gpt-4o"
        )
      end

      ra = research_agent
      wa = writer_agent

      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa, max_turns: 5
        delegate :researcher, ra
        delegate :writer, wa
      }

      result = wf.call(topic: "AI safety")

      expect(result).to be_a(RubyLLM::Agents::Workflow::WorkflowResult)
      expect(result.success?).to be true
      expect(call_count).to eq(1)
    end

    it "respects max_turns limit" do
      call_count = 0
      oa = orchestrator_agent
      allow(oa).to receive(:ask) do |message, **opts|
        call_count += 1
        RubyLLM::Agents::Result.new(
          content: "Still working...",
          input_tokens: 50,
          output_tokens: 25,
          model_id: "gpt-4o"
        )
      end

      ra = research_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa, max_turns: 3
        delegate :researcher, ra
      }

      result = wf.call(topic: "test")

      expect(call_count).to eq(3)
      expect(result.step_results.size).to eq(3)
    end

    it "aggregates costs from supervisor turns" do
      turn = 0
      oa = orchestrator_agent
      allow(oa).to receive(:ask) do |message, **opts|
        turn += 1
        Thread.current[:workflow_supervisor_complete] = true if turn >= 2

        RubyLLM::Agents::Result.new(
          content: "Turn #{turn}",
          input_tokens: 100,
          output_tokens: 50,
          total_cost: 0.001,
          model_id: "gpt-4o"
        )
      end

      ra = research_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa, max_turns: 5
        delegate :researcher, ra
      }

      result = wf.call(topic: "test")

      expect(result.total_tokens).to be > 0
    end
  end

  describe "supervisor with step-based workflow is mutually exclusive" do
    it "uses supervisor mode when supervisor is configured (ignores steps)" do
      call_count = 0
      oa = orchestrator_agent
      allow(oa).to receive(:ask) do |message, **opts|
        call_count += 1
        Thread.current[:workflow_supervisor_complete] = true
        Thread.current[:workflow_supervisor_result] = "Done"

        RubyLLM::Agents::Result.new(
          content: "Completed",
          input_tokens: 50,
          output_tokens: 25,
          model_id: "gpt-4o"
        )
      end

      ra = research_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        supervisor oa, max_turns: 3
        delegate :researcher, ra
        # Also define steps — should be ignored in supervisor mode
        step :unused, ra
      }

      wf.call(topic: "test")

      # Should have used supervisor, not step execution
      expect(call_count).to eq(1)
    end
  end
end
