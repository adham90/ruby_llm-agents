# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Tool do
  # Real test tool classes — no mocks per CLAUDE.md

  let(:simple_tool_class) do
    Class.new(described_class) do
      def self.name
        "SimpleTool"
      end

      description "A simple test tool"
      param :input, desc: "Some input", required: true

      def execute(input:)
        "got: #{input}"
      end
    end
  end

  let(:timeout_tool_class) do
    Class.new(described_class) do
      def self.name
        "TimeoutTool"
      end

      description "A tool with a timeout"
      timeout 1

      param :input, desc: "Some input", required: true

      def execute(input:)
        sleep 2 if input == "slow"
        "got: #{input}"
      end
    end
  end

  let(:error_tool_class) do
    Class.new(described_class) do
      def self.name
        "ErrorTool"
      end

      description "A tool that raises errors"
      param :input, desc: "Some input", required: true

      def execute(input:)
        raise "Something went wrong"
      end
    end
  end

  let(:context_tool_class) do
    Class.new(described_class) do
      def self.name
        "ContextTool"
      end

      description "A tool that reads context"
      param :input, desc: "Some input", required: true

      def execute(input:)
        return "no context" unless context
        "tenant:#{context.tenant_id} container:#{context.container_id}"
      end
    end
  end

  describe "class hierarchy" do
    it "inherits from RubyLLM::Tool" do
      expect(described_class).to be < RubyLLM::Tool
    end

    it "tool subclasses are instances of RubyLLM::Agents::Tool" do
      expect(simple_tool_class).to be < described_class
    end
  end

  describe ".timeout" do
    it "returns nil when not set" do
      expect(simple_tool_class.timeout).to be_nil
    end

    it "returns the configured timeout" do
      expect(timeout_tool_class.timeout).to eq(1)
    end

    it "does not share timeout across subclasses" do
      expect(simple_tool_class.timeout).to be_nil
      expect(timeout_tool_class.timeout).to eq(1)
    end
  end

  describe "#call" do
    it "executes the tool and returns the result" do
      tool = simple_tool_class.new
      result = tool.call({input: "hello"})
      expect(result).to eq("got: hello")
    end

    it "validates required arguments via RubyLLM's validation" do
      tool = simple_tool_class.new
      result = tool.call({})
      expect(result).to be_a(Hash)
      expect(result[:error]).to include("missing keyword")
    end

    it "handles string keys in arguments" do
      tool = simple_tool_class.new
      result = tool.call({"input" => "hello"})
      expect(result).to eq("got: hello")
    end
  end

  describe "error handling" do
    it "catches exceptions and returns error strings" do
      tool = error_tool_class.new
      result = tool.call({input: "test"})
      expect(result).to include("ERROR")
      expect(result).to include("RuntimeError")
      expect(result).to include("Something went wrong")
    end

    it "does not raise — errors become strings for the LLM" do
      tool = error_tool_class.new
      expect { tool.call({input: "test"}) }.not_to raise_error
    end
  end

  describe "timeout" do
    it "returns a timeout string when tool exceeds timeout" do
      tool = timeout_tool_class.new
      result = tool.call({input: "slow"})
      expect(result).to include("TIMEOUT")
      expect(result).to include("1s")
    end

    it "completes normally when within timeout" do
      tool = timeout_tool_class.new
      result = tool.call({input: "fast"})
      expect(result).to eq("got: fast")
    end

    it "uses config.default_tool_timeout when tool has no timeout" do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.default_tool_timeout = 1
      end

      slow_tool_class = Class.new(described_class) do
        def self.name
          "SlowTool"
        end

        description "Slow tool without explicit timeout"
        param :input, desc: "Input", required: true

        def execute(input:)
          sleep 2
          "done"
        end
      end

      tool = slow_tool_class.new
      result = tool.call({input: "test"})
      expect(result).to include("TIMEOUT")
    ensure
      RubyLLM::Agents.reset_configuration!
    end

    it "has no timeout when neither tool nor config sets one" do
      tool = simple_tool_class.new
      # Simple tool has no timeout, config default is nil
      # Should execute normally without any timeout
      result = tool.call({input: "hello"})
      expect(result).to eq("got: hello")
    end
  end

  describe "context accessor" do
    it "is nil when no pipeline context is set" do
      tool = context_tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("no context")
    end

    it "provides access to agent params via method-style" do
      # Simulate the pipeline context that BaseAgent sets
      pipeline_context = build_pipeline_context(
        tenant_id: "tenant_123",
        agent_options: {container_id: "abc123"}
      )

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool = context_tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("tenant:tenant_123 container:abc123")
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end

    it "provides access to agent params via hash-style" do
      pipeline_context = build_pipeline_context(
        agent_options: {api_key: "secret"}
      )

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(described_class) do
        def self.name
          "HashAccessTool"
        end

        description "Tests hash access"
        param :input, desc: "Input", required: true

        def execute(input:)
          context[:api_key].to_s
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("secret")
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end

    it "provides execution_id via context.id" do
      pipeline_context = build_pipeline_context(execution_id: 42)

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(described_class) do
        def self.name
          "IdTool"
        end

        description "Tests id access"
        param :input, desc: "Input", required: true

        def execute(input:)
          context.id.to_s
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("42")
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end

    it "provides agent_type" do
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "TestCodingAgent"
        end
      end

      pipeline_context = build_pipeline_context(agent_class: agent_class)

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(described_class) do
        def self.name
          "AgentTypeTool"
        end

        description "Tests agent_type access"
        param :input, desc: "Input", required: true

        def execute(input:)
          context.agent_type.to_s
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("TestCodingAgent")
    ensure
      Thread.current[:ruby_llm_agents_caller_context] = nil
    end

    it "resets context between calls" do
      tool = context_tool_class.new

      # First call without context
      result1 = tool.call({input: "test"})
      expect(result1).to eq("no context")

      # Second call with context
      pipeline_context = build_pipeline_context(
        tenant_id: "t1",
        agent_options: {container_id: "c1"}
      )
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context
      result2 = tool.call({input: "test"})
      expect(result2).to eq("tenant:t1 container:c1")

      # Third call without context again
      Thread.current[:ruby_llm_agents_caller_context] = nil
      result3 = tool.call({input: "test"})
      expect(result3).to eq("no context")
    end
  end

  describe "Tool::Halt passthrough" do
    it "passes Halt results through without converting" do
      halt_tool_class = Class.new(described_class) do
        def self.name
          "HaltTool"
        end

        description "Returns halt"
        param :input, desc: "Input", required: true

        def execute(input:)
          halt("stopping here")
        end
      end

      tool = halt_tool_class.new
      result = tool.call({input: "test"})
      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(result.content).to eq("stopping here")
    end
  end

  # Helper to build a minimal pipeline context for testing
  def build_pipeline_context(tenant_id: nil, agent_options: {}, execution_id: nil, agent_class: nil)
    agent_class ||= Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "TestAgent"
      end
    end

    # Create a real agent instance with the options
    agent_instance = agent_class.allocate
    agent_instance.instance_variable_set(:@options, agent_options)

    # Build a minimal context-like object
    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      agent_instance: agent_instance
    )
    ctx.tenant_id = tenant_id
    ctx.execution_id = execution_id
    ctx
  end
end
