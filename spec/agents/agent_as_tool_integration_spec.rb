# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent-as-Tool Integration" do
  # Real agent classes — no mocks per CLAUDE.md
  let(:sub_agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "SubAgent"
      end

      description "A sub-agent for testing"
      model "gpt-4o-mini"
      param :query, required: true, desc: "Query to process"

      def user_prompt
        query
      end
    end
  end

  let(:orchestrator_class) do
    agent_cls = sub_agent_class
    Class.new(RubyLLM::Agents::BaseAgent) do
      define_singleton_method(:name) { "OrchestratorAgent" }

      model "gpt-4o"
      tools [agent_cls]
      param :topic, required: true, desc: "Topic to research"

      system "You coordinate tasks using specialist agents."

      define_method(:user_prompt) { topic }
    end
  end

  before do
    stub_agent_configuration(track_executions: true)
  end

  describe "Pipeline::Context hierarchy IDs" do
    it "stores parent_execution_id" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: sub_agent_class,
        parent_execution_id: 42,
        root_execution_id: 1
      )

      expect(context.parent_execution_id).to eq(42)
      expect(context.root_execution_id).to eq(1)
    end

    it "defaults hierarchy IDs to nil" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: sub_agent_class
      )

      expect(context.parent_execution_id).to be_nil
      expect(context.root_execution_id).to be_nil
    end

    it "preserves hierarchy IDs in dup_for_retry" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: sub_agent_class,
        parent_execution_id: 42,
        root_execution_id: 1
      )

      duped = context.dup_for_retry
      expect(duped.parent_execution_id).to eq(42)
      expect(duped.root_execution_id).to eq(1)
    end
  end

  describe "BaseAgent hierarchy ID acceptance" do
    it "accepts _parent_execution_id and _root_execution_id" do
      agent = sub_agent_class.new(
        query: "test",
        _parent_execution_id: 42,
        _root_execution_id: 1
      )

      expect(agent.instance_variable_get(:@parent_execution_id)).to eq(42)
      expect(agent.instance_variable_get(:@root_execution_id)).to eq(1)
    end

    it "does not require _parent_execution_id as a param" do
      # Internal params should not trigger missing param validation
      expect {
        sub_agent_class.new(query: "test", _parent_execution_id: 42)
      }.not_to raise_error
    end

    it "passes hierarchy IDs to context via build_context" do
      agent = sub_agent_class.new(
        query: "test",
        _parent_execution_id: 42,
        _root_execution_id: 1
      )

      context = agent.send(:build_context)
      expect(context.parent_execution_id).to eq(42)
      expect(context.root_execution_id).to eq(1)
    end
  end

  describe "caller context thread-local" do
    it "sets and restores thread-local context during execute" do
      agent = sub_agent_class.new(query: "test")

      mock_response = build_mock_response(
        content: "result",
        input_tokens: 10,
        output_tokens: 5
      )
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: sub_agent_class,
        agent_instance: agent
      )
      context.execution_id = 99

      # Verify thread-local is nil before
      expect(Thread.current[:ruby_llm_agents_caller_context]).to be_nil

      agent.send(:execute, context)

      # Verify thread-local is restored to nil after
      expect(Thread.current[:ruby_llm_agents_caller_context]).to be_nil
    end

    it "restores previous context on nested calls" do
      agent = sub_agent_class.new(query: "test")

      mock_response = build_mock_response(content: "result", input_tokens: 10, output_tokens: 5)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)

      previous_ctx = Object.new
      Thread.current[:ruby_llm_agents_caller_context] = previous_ctx

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: sub_agent_class,
        agent_instance: agent
      )

      agent.send(:execute, context)

      expect(Thread.current[:ruby_llm_agents_caller_context]).to eq(previous_ctx)
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end
  end

  describe "instrumentation hierarchy" do
    it "records parent_execution_id on child execution" do
      mock_response = build_mock_response(content: "result", input_tokens: 10, output_tokens: 5)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)

      # Call sub-agent as if it were invoked by a parent
      sub_agent_class.call(
        query: "test",
        _parent_execution_id: 999,
        _root_execution_id: 888
      )

      execution = RubyLLM::Agents::Execution.last
      expect(execution.parent_execution_id).to eq(999)
      expect(execution.root_execution_id).to eq(888)
    end

    it "sets root_execution_id to self for root executions" do
      mock_response = build_mock_response(content: "result", input_tokens: 10, output_tokens: 5)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)

      sub_agent_class.call(query: "root test")

      execution = RubyLLM::Agents::Execution.last
      expect(execution.parent_execution_id).to be_nil
      expect(execution.root_execution_id).to eq(execution.id)
    end

    it "stores root_execution_id in context metadata for sub-agents" do
      mock_response = build_mock_response(content: "result", input_tokens: 10, output_tokens: 5)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)

      sub_agent_class.call(query: "test")

      execution = RubyLLM::Agents::Execution.last
      expect(execution.root_execution_id).to be_present
    end
  end

  describe "AgentTool caller context propagation" do
    it "passes parent execution ID from caller context to sub-agent" do
      agent_cls = sub_agent_class
      tool_class = RubyLLM::Agents::AgentTool.for(agent_cls)
      tool_instance = tool_class.new

      # Simulate caller context (as if an orchestrator set it)
      caller_context = RubyLLM::Agents::Pipeline::Context.new(
        input: "orchestrator input",
        agent_class: orchestrator_class
      )
      caller_context.instance_variable_set(:@execution_id, 42)

      Thread.current[:ruby_llm_agents_caller_context] = caller_context

      # The sub-agent should receive _parent_execution_id
      expect(agent_cls).to receive(:call).with(
        hash_including(_parent_execution_id: 42)
      ).and_return(RubyLLM::Agents::Result.new(content: "done"))

      tool_instance.execute(query: "test")
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end
  end
end
