# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tool execution tracking", type: :model do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
    Thread.current[:ruby_llm_agents_caller_context] = nil
  end

  let(:execution) do
    RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o",
      status: "running",
      started_at: Time.current
    )
  end

  let(:pipeline_context) do
    agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "TestAgent"
      end
    end

    agent_instance = agent_class.allocate
    agent_instance.instance_variable_set(:@options, {container_id: "abc123"})

    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      agent_instance: agent_instance
    )
    ctx.execution_id = execution.id
    ctx.tenant_id = "tenant_1"
    ctx
  end

  describe "successful tool execution" do
    it "creates a tool execution record on success" do
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "TrackedTool"
        end

        description "A tracked tool"
        param :input, desc: "Input", required: true

        def execute(input:)
          "result: #{input}"
        end
      end

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool = tool_class.new
      result = tool.call({input: "hello"})

      expect(result).to eq("result: hello")

      records = RubyLLM::Agents::ToolExecution.where(execution_id: execution.id)
      expect(records.count).to eq(1)

      record = records.first
      expect(record.tool_name).to eq("tracked")
      expect(record.status).to eq("success")
      expect(record.input).to eq({"input" => "hello"})
      expect(record.output).to include("result: hello")
      expect(record.started_at).to be_present
      expect(record.completed_at).to be_present
      expect(record.duration_ms).to be >= 0
    end
  end

  describe "failed tool execution" do
    it "records error status on exception" do
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "ErrorTrackedTool"
        end

        description "A tool that errors"
        param :input, desc: "Input", required: true

        def execute(input:)
          raise "boom"
        end
      end

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool = tool_class.new
      result = tool.call({input: "test"})

      expect(result).to include("ERROR")

      record = RubyLLM::Agents::ToolExecution.last
      expect(record.status).to eq("error")
      expect(record.error_message).to eq("boom")
    end
  end

  describe "timed out tool execution" do
    it "records timed_out status" do
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "SlowTrackedTool"
        end

        description "A slow tool"
        timeout 1
        param :input, desc: "Input", required: true

        def execute(input:)
          sleep 2
          "done"
        end
      end

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool = tool_class.new
      result = tool.call({input: "test"})

      expect(result).to include("TIMEOUT")

      record = RubyLLM::Agents::ToolExecution.last
      expect(record.status).to eq("timed_out")
      expect(record.error_message).to include("Timed out")
    end
  end

  describe "without pipeline context" do
    it "skips tracking gracefully" do
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "UntrackTool"
        end

        description "Untracked tool"
        param :input, desc: "Input", required: true

        def execute(input:)
          "ok"
        end
      end

      # No Thread.current context set
      tool = tool_class.new
      result = tool.call({input: "test"})

      expect(result).to eq("ok")
      expect(RubyLLM::Agents::ToolExecution.count).to eq(0)
    end
  end

  describe "without execution_id" do
    it "skips tracking gracefully" do
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "NoExecAgent"
        end
      end

      agent_instance = agent_class.allocate
      agent_instance.instance_variable_set(:@options, {})

      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class,
        agent_instance: agent_instance
      )
      # execution_id is nil

      Thread.current[:ruby_llm_agents_caller_context] = ctx

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "NoExecTool"
        end

        description "Tool without execution"
        param :input, desc: "Input", required: true

        def execute(input:)
          "ok"
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})

      expect(result).to eq("ok")
      expect(RubyLLM::Agents::ToolExecution.count).to eq(0)
    end
  end

  describe "iteration tracking" do
    it "increments iteration counter per tool call" do
      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "IterTool"
        end

        description "Iteration tool"
        param :input, desc: "Input", required: true

        def execute(input:)
          "ok"
        end
      end

      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool = tool_class.new
      tool.call({input: "first"})
      tool.call({input: "second"})
      tool.call({input: "third"})

      records = RubyLLM::Agents::ToolExecution.where(execution_id: execution.id).order(:iteration)
      expect(records.pluck(:iteration)).to eq([1, 2, 3])
    end
  end
end
