# frozen_string_literal: true

require "rails_helper"
require "ostruct"

# Regression test for GitHub issue #22
# https://github.com/adham90/ruby_llm-agents/issues/22
#
# Core::Base#execute overrides BaseAgent#execute without setting
# Thread.current[:ruby_llm_agents_caller_context], so tools
# always receive nil context when called from agents that inherit
# from RubyLLM::Agents::Base (which includes Core::Base).
#
# This spec reproduces the bug by running a full agent pipeline
# with a tool that reads context, verifying that context is
# available inside the tool during execution.
RSpec.describe "Tool context availability in Core::Base agents (Issue #22)" do
  # A tool that captures its context at call time for later inspection
  let(:context_capturing_tool_class) do
    Class.new(RubyLLM::Agents::Tool) do
      def self.name
        "ContextCaptureTool"
      end

      description "Captures execution context for testing"
      param :path, desc: "A file path", required: true

      def execute(path:)
        # Store what we observed for the test to inspect
        Thread.current[:test_tool_context] = context
        Thread.current[:test_tool_context_nil] = context.nil?
        if context
          Thread.current[:test_tool_workspace_path] = context.workspace_path
        end
        "read #{path}"
      end
    end
  end

  # Agent inheriting from Base (which includes Core::Base).
  # This is the standard pattern users follow.
  let(:base_agent_class) do
    tool = context_capturing_tool_class
    Class.new(RubyLLM::Agents::Base) do
      define_method(:self_name) { "ContextTestAgent" }
      (class << self; self; end).define_method(:name) { "ContextTestAgent" }

      model "gpt-4o"
      temperature 0.0
      tools [tool]

      param :query, required: true
      param :workspace_path, default: "/tmp/test"

      private

      def system_prompt
        "You are a test assistant."
      end

      def user_prompt
        query
      end
    end
  end

  # Agent inheriting directly from BaseAgent (bypasses Core::Base).
  # This one works correctly because BaseAgent#execute sets the thread-local.
  let(:base_agent_direct_class) do
    tool = context_capturing_tool_class
    Class.new(RubyLLM::Agents::BaseAgent) do
      (class << self; self; end).define_method(:name) { "DirectBaseTestAgent" }

      model "gpt-4o"
      temperature 0.0
      tools [tool]

      param :query, required: true
      param :workspace_path, default: "/tmp/test"

      private

      def system_prompt
        "You are a test assistant."
      end

      def user_prompt
        query
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
    end

    # Clear captured state
    Thread.current[:test_tool_context] = nil
    Thread.current[:test_tool_context_nil] = nil
    Thread.current[:test_tool_workspace_path] = nil
  end

  after do
    Thread.current[:test_tool_context] = nil
    Thread.current[:test_tool_context_nil] = nil
    Thread.current[:test_tool_workspace_path] = nil
    Thread.current[:ruby_llm_agents_caller_context] = nil
    RubyLLM::Agents.reset_configuration!
  end

  def build_tool_calling_mock_client(tool_class)
    mock_client = double("RubyLLM::Chat")

    allow(mock_client).to receive(:with_temperature).and_return(mock_client)
    allow(mock_client).to receive(:with_instructions).and_return(mock_client)
    allow(mock_client).to receive(:with_schema).and_return(mock_client)
    allow(mock_client).to receive(:with_tools).and_return(mock_client)
    allow(mock_client).to receive(:with_thinking).and_return(mock_client)
    allow(mock_client).to receive(:add_message).and_return(mock_client)
    allow(mock_client).to receive(:messages).and_return([])

    # Capture the on_tool_call and on_tool_result callbacks
    tool_call_block = nil
    tool_result_block = nil

    allow(mock_client).to receive(:on_tool_call) do |&blk|
      tool_call_block = blk
      mock_client
    end

    allow(mock_client).to receive(:on_tool_result) do |&blk|
      tool_result_block = blk
      mock_client
    end

    # When ask is called, simulate a tool call then return final response.
    # This exercises the real tool call path where the tool's #call method
    # is invoked, which reads Thread.current[:ruby_llm_agents_caller_context].
    allow(mock_client).to receive(:ask) do |_prompt, **_opts|
      # Simulate the tool being called (as RubyLLM::Chat would do)
      tool_instance = tool_class.new
      tool_call_data = OpenStruct.new(
        id: "call_123",
        name: tool_instance.name,
        arguments: {path: "/app/Gemfile"}
      )

      # Notify on_tool_call callback (if set)
      tool_call_block&.call(tool_call_data)

      # Actually call the tool (this is what RubyLLM::Chat does internally)
      result = tool_instance.call({path: "/app/Gemfile"})

      # Notify on_tool_result callback (if set)
      tool_result_block&.call(OpenStruct.new(
        tool_call_id: "call_123",
        content: result.to_s
      ))

      # Return final response
      build_mock_response(content: "I read the file for you")
    end

    mock_client
  end

  describe "Core::Base agent (RubyLLM::Agents::Base)" do
    it "makes context available to tools during execution" do
      mock_client = build_tool_calling_mock_client(context_capturing_tool_class)
      stub_ruby_llm_chat(mock_client)

      base_agent_class.call(query: "Read the Gemfile", workspace_path: "/my/project")

      # THE BUG: context is nil because Core::Base#execute doesn't set the thread-local
      expect(Thread.current[:test_tool_context_nil]).to eq(false),
        "Expected tool context to NOT be nil, but it was nil. " \
        "Core::Base#execute does not set Thread.current[:ruby_llm_agents_caller_context]."
    end

    it "provides agent params (workspace_path) via tool context" do
      mock_client = build_tool_calling_mock_client(context_capturing_tool_class)
      stub_ruby_llm_chat(mock_client)

      base_agent_class.call(query: "Read the Gemfile", workspace_path: "/my/project")

      # THE BUG: context.workspace_path is nil because context itself is nil
      expect(Thread.current[:test_tool_workspace_path]).to eq("/my/project"),
        "Expected tool to read workspace_path='/my/project' from context, " \
        "but got #{Thread.current[:test_tool_workspace_path].inspect}. " \
        "Core::Base#execute does not propagate the pipeline context to tools."
    end
  end

  describe "BaseAgent direct (control group)" do
    it "makes context available to tools during execution" do
      mock_client = build_tool_calling_mock_client(context_capturing_tool_class)
      stub_ruby_llm_chat(mock_client)

      base_agent_direct_class.call(query: "Read the Gemfile", workspace_path: "/my/project")

      # BaseAgent#execute correctly sets the thread-local — this should pass
      expect(Thread.current[:test_tool_context_nil]).to eq(false),
        "Control: BaseAgent#execute should set context for tools"
    end

    it "provides agent params (workspace_path) via tool context" do
      mock_client = build_tool_calling_mock_client(context_capturing_tool_class)
      stub_ruby_llm_chat(mock_client)

      base_agent_direct_class.call(query: "Read the Gemfile", workspace_path: "/my/project")

      expect(Thread.current[:test_tool_workspace_path]).to eq("/my/project"),
        "Control: BaseAgent#execute should make workspace_path accessible"
    end
  end

  describe "thread-local cleanup" do
    it "restores previous thread-local context after execution" do
      mock_client = build_tool_calling_mock_client(context_capturing_tool_class)
      stub_ruby_llm_chat(mock_client)

      # Set a pre-existing thread-local (simulating nested agent calls)
      sentinel = Object.new
      Thread.current[:ruby_llm_agents_caller_context] = sentinel

      base_agent_class.call(query: "Read the Gemfile", workspace_path: "/my/project")

      # After execution, the previous context should be restored
      expect(Thread.current[:ruby_llm_agents_caller_context]).to eq(sentinel),
        "Expected thread-local context to be restored after execution, " \
        "but it was #{Thread.current[:ruby_llm_agents_caller_context].inspect}"
    end
  end
end
