# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tool concurrency DSL" do
  let(:tool_class) do
    Class.new(RubyLLM::Agents::Tool) do
      def self.name
        "ConcurrencyTool"
      end

      description "A tool"
      param :input, desc: "Input", required: true

      def execute(input:)
        "ok: #{input}"
      end
    end
  end

  describe ".tool_concurrency" do
    it "returns nil when never set, so the agent defers to the global default" do
      agent = Class.new(RubyLLM::Agents::BaseAgent)

      expect(agent.tool_concurrency).to be_nil
    end

    it "stores and returns an explicit mode" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) { tool_concurrency :threads }

      expect(agent.tool_concurrency).to eq(:threads)
    end

    it "treats false as an explicit override rather than unset" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) { tool_concurrency false }

      expect(agent.tool_concurrency).to be(false)
    end

    it "inherits the mode from a superclass" do
      parent = Class.new(RubyLLM::Agents::BaseAgent) { tool_concurrency :fibers }
      child = Class.new(parent)

      expect(child.tool_concurrency).to eq(:fibers)
    end

    it "lets a subclass override an inherited mode with false" do
      parent = Class.new(RubyLLM::Agents::BaseAgent) { tool_concurrency :threads }
      child = Class.new(parent) { tool_concurrency false }

      expect(child.tool_concurrency).to be(false)
    end
  end

  describe "wiring into the chat client" do
    def build_client_for(agent_class)
      agent = agent_class.allocate
      agent.instance_variable_set(:@options, {})
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "hi",
        agent_class: agent_class,
        agent_instance: agent
      )
      agent.send(:build_client, ctx)
    end

    it "passes the configured concurrency to with_tools" do
      tc = tool_class
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "ConcurrentToolAgent"
        end

        model "gpt-4o"
        tools tc
        tool_concurrency :threads
      end

      mock = build_mock_chat_client
      stub_ruby_llm_chat(mock)
      expect(mock).to receive(:with_tools).with(tc, concurrency: :threads).and_return(mock)

      build_client_for(agent_class)
    end

    it "omits the concurrency keyword when the agent does not configure it" do
      tc = tool_class
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "PlainToolAgent"
        end

        model "gpt-4o"
        tools tc
      end

      mock = build_mock_chat_client
      stub_ruby_llm_chat(mock)
      expect(mock).to receive(:with_tools).with(tc).and_return(mock)

      build_client_for(agent_class)
    end
  end
end
