# frozen_string_literal: true

require "rails_helper"

RSpec.describe "agents DSL" do
  # Define test agent classes for use as sub-agents
  let(:sub_agent_a) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "SubAgentA"

      model "gpt-4o"
      description "First sub-agent"
      param :spec, required: true
      param :workspace_path, required: true

      def user_prompt
        spec
      end
    end
  end

  let(:sub_agent_b) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "SubAgentB"

      model "gpt-4o"
      description "Second sub-agent"
      param :spec, required: true

      def user_prompt
        spec
      end
    end
  end

  before do
    stub_agent_configuration
  end

  describe "AgentsConfig" do
    it "stores agent entries via use" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.use(sub_agent_a)
      config.use(sub_agent_b, timeout: 180, description: "Custom desc")

      expect(config.agent_entries.length).to eq(2)
      expect(config.agent_entries[0][:agent_class]).to eq(sub_agent_a)
      expect(config.agent_entries[1][:timeout]).to eq(180)
      expect(config.agent_entries[1][:description]).to eq("Custom desc")
    end

    it "stores forwarded params" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.forward :workspace_path, :project_id
      expect(config.forwarded_params).to eq([:workspace_path, :project_id])
    end

    it "defaults parallel to true" do
      config = RubyLLM::Agents::AgentsConfig.new
      expect(config.parallel?).to be true
    end

    it "stores instructions" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.instructions "Use agents for big tasks"
      expect(config.instructions_text).to eq("Use agents for big tasks")
    end

    it "returns timeout_for with per-agent override" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.timeout 60
      config.use(sub_agent_a, timeout: 180)
      config.use(sub_agent_b)

      expect(config.timeout_for(sub_agent_a)).to eq(180)
      expect(config.timeout_for(sub_agent_b)).to eq(60)
    end

    it "returns description_for with per-agent override" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.use(sub_agent_a, description: "Custom A")
      config.use(sub_agent_b)

      expect(config.description_for(sub_agent_a)).to eq("Custom A")
      expect(config.description_for(sub_agent_b)).to be_nil
    end

    it "stores max_depth" do
      config = RubyLLM::Agents::AgentsConfig.new
      config.max_depth 3
      expect(config.max_depth_value).to eq(3)
    end
  end

  describe "simple form" do
    it "registers agent entries" do
      a = sub_agent_a
      b = sub_agent_b
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "SimpleFormAgent"
        model "gpt-4o"
        agents [a, b], forward: [:workspace_path]

        def user_prompt
          "test"
        end
      end

      entries = agent_class.agents_config.agent_entries
      expect(entries.length).to eq(2)
      expect(entries.map { |e| e[:agent_class] }).to eq([a, b])
      expect(agent_class.agents_config.forwarded_params).to eq([:workspace_path])
    end
  end

  describe "block form" do
    it "registers agents with per-agent options" do
      a = sub_agent_a
      b = sub_agent_b
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "BlockFormAgent"
        model "gpt-4o"

        agents do
          use a, timeout: 180, description: "Custom A"
          use b
          forward :workspace_path
          parallel true
          max_depth 3
          instructions "Use agents for big tasks"
        end

        def user_prompt
          "test"
        end
      end

      config = agent_class.agents_config
      expect(config.agent_entries.length).to eq(2)
      expect(config.description_for(a)).to eq("Custom A")
      expect(config.timeout_for(a)).to eq(180)
      expect(config.forwarded_params).to eq([:workspace_path])
      expect(config.parallel?).to be true
      expect(config.max_depth_value).to eq(3)
      expect(config.instructions_text).to eq("Use agents for big tasks")
    end
  end

  describe "resolved_tools with agents" do
    it "includes both tools and agents" do
      a = sub_agent_a
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name = "TestTool"
        description "A test tool"
        param :input, desc: "Input"
        def execute(input: nil)
          input
        end
      end

      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "MixedAgent"
        model "gpt-4o"
        tools [tool_class]
        agents [a]
        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      tools = instance.send(:resolved_tools)

      # Should have both the tool and the agent-as-tool
      expect(tools.length).to eq(2)

      agent_tools = tools.select { |t| t.respond_to?(:agent_delegate?) && t.agent_delegate? }
      expect(agent_tools.length).to eq(1)
      expect(agent_tools.first.agent_class).to eq(a)
    end

    it "marks agents with agent_delegate?" do
      a = sub_agent_a
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "DelegateMarkerAgent"
        model "gpt-4o"
        agents [a]
        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      tools = instance.send(:resolved_tools)
      agent_tool = tools.find { |t| t.respond_to?(:agent_delegate?) && t.agent_delegate? }

      expect(agent_tool).not_to be_nil
      expect(agent_tool.agent_delegate?).to be true
    end

    it "agents in tools list do NOT have agent_delegate? marker" do
      a = sub_agent_a
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "OldStyleAgent"
        model "gpt-4o"
        tools [a]
        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      tools = instance.send(:resolved_tools)

      # Old-style agents in tools should NOT be marked as delegates
      tools.each do |t|
        next unless t.respond_to?(:agent_delegate?)
        expect(t.agent_delegate?).to be false
      end
    end
  end

  describe "forward parameter injection" do
    it "excludes forwarded params from agent tool schema" do
      a = sub_agent_a  # has :spec (required) and :workspace_path (required)
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ForwardAgent"
        model "gpt-4o"
        agents [a], forward: [:workspace_path]
        param :query, required: true
        param :workspace_path, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test", workspace_path: "/tmp/ws")
      tools = instance.send(:resolved_tools)
      agent_tool = tools.find { |t| t.respond_to?(:agent_delegate?) && t.agent_delegate? }

      # Check that forwarded params are tracked and excluded from LLM schema
      expect(agent_tool.forwarded_params).to include(:workspace_path)
    end
  end

  describe "system prompt with agents" do
    it "appends agents section when agents declared" do
      a = sub_agent_a
      b = sub_agent_b
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name = "MyTool"
        description "Does things"
        param :input, desc: "Input"
        def execute(input: nil)
          input
        end
      end

      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "PromptTestAgent"
        model "gpt-4o"
        system "You are a helpful assistant."
        tools [tool_class]
        agents [a, b]
        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      prompt = instance.system_prompt

      expect(prompt).to include("You are a helpful assistant.")
      expect(prompt).to include("## Direct Tools")
      expect(prompt).to include("## Agents")
      expect(prompt).to include("sub_agent_a")
      expect(prompt).to include("sub_agent_b")
    end

    it "includes custom instructions text" do
      a = sub_agent_a
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "InstructionsAgent"
        model "gpt-4o"
        system "Base prompt."

        agents do
          use a
          instructions "Use agents for big tasks only."
        end

        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      prompt = instance.system_prompt

      expect(prompt).to include("Use agents for big tasks only.")
    end

    it "does not append sections when no agents declared" do
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "NoAgentsPromptAgent"
        model "gpt-4o"
        system "You are helpful."
        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      prompt = instance.system_prompt

      expect(prompt).to eq("You are helpful.")
      expect(prompt).not_to include("## Agents")
    end

    it "uses per-agent description override in system prompt" do
      a = sub_agent_a
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "DescOverrideAgent"
        model "gpt-4o"
        system "Base."

        agents do
          use a, description: "Custom description for A"
        end

        param :query, required: true
        def user_prompt
          query
        end
      end

      instance = agent_class.new(query: "test")
      prompt = instance.system_prompt

      expect(prompt).to include("Custom description for A")
    end
  end

  describe "stream events with agent delegates" do
    it "emits :agent_start/:agent_end for agent delegates" do
      a = sub_agent_a
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "StreamDelegateAgent"
        model "gpt-4o"
        streaming true
        agents [a]
        param :query, required: true
        def user_prompt
          query
        end
      end

      tool_call_obj = double("ToolCall",
        id: "call_456",
        name: "sub_agent_a",
        arguments: {spec: "build models"})
      tool_result_obj = "Models built successfully"

      mock_client = build_mock_chat_client(response: build_real_response(content: "Done"))

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

      allow(mock_client).to receive(:ask) do |_, **_opts, &block|
        tool_call_block&.call(tool_call_obj)
        tool_result_block&.call(tool_result_obj)
        build_real_response(content: "Done")
      end

      stub_ruby_llm_chat(mock_client)

      events = []
      agent_class.call(query: "test", workspace_path: "/tmp", stream_events: true) do |event|
        events << event
      end

      agent_events = events.select(&:agent_event?)
      expect(agent_events.length).to eq(2)

      start_event = agent_events.find { |e| e.type == :agent_start }
      expect(start_event.data[:tool_name]).to eq("sub_agent_a")
      expect(start_event.data[:agent_name]).to eq("sub_agent_a")
      expect(start_event.data[:agent_class]).to eq("SubAgentA")

      end_event = agent_events.find { |e| e.type == :agent_end }
      expect(end_event.data[:tool_name]).to eq("sub_agent_a")
      expect(end_event.data[:status]).to eq("success")
    end
  end
end
