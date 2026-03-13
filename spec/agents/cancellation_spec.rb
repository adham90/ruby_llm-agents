# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tool cancellation", type: :model do
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
    agent_instance.instance_variable_set(:@options, {})

    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      agent_instance: agent_instance
    )
    ctx.execution_id = execution.id
    ctx
  end

  describe "on_cancelled check" do
    it "raises CancelledError when on_cancelled returns true" do
      pipeline_context[:on_cancelled] = -> { true }
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "CancellableTool"
        end

        description "A cancellable tool"
        param :input, desc: "Input", required: true

        def execute(input:)
          "should not reach here"
        end
      end

      tool = tool_class.new
      expect { tool.call({input: "test"}) }.to raise_error(RubyLLM::Agents::CancelledError)
    end

    it "does not cancel when on_cancelled returns false" do
      pipeline_context[:on_cancelled] = -> { false }
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "NoCancelTool"
        end

        description "A tool that should not cancel"
        param :input, desc: "Input", required: true

        def execute(input:)
          "completed"
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("completed")
    end

    it "does not cancel when on_cancelled is not set" do
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "NoProcTool"
        end

        description "A tool with no cancel proc"
        param :input, desc: "Input", required: true

        def execute(input:)
          "completed"
        end
      end

      tool = tool_class.new
      result = tool.call({input: "test"})
      expect(result).to eq("completed")
    end

    it "records cancelled status in tool execution tracking" do
      pipeline_context[:on_cancelled] = -> { true }
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "TrackedCancelTool"
        end

        description "Tracked and cancelled"
        param :input, desc: "Input", required: true

        def execute(input:)
          "nope"
        end
      end

      tool = tool_class.new
      expect { tool.call({input: "test"}) }.to raise_error(RubyLLM::Agents::CancelledError)

      record = RubyLLM::Agents::ToolExecution.last
      expect(record.status).to eq("cancelled")
    end

    it "cancels between calls, not during" do
      call_count = 0
      pipeline_context[:on_cancelled] = -> { call_count >= 1 }
      Thread.current[:ruby_llm_agents_caller_context] = pipeline_context

      tool_class = Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "CountTool"
        end

        description "Counts calls"
        param :input, desc: "Input", required: true

        def execute(input:)
          "call done"
        end
      end

      tool = tool_class.new

      # First call succeeds
      result = tool.call({input: "first"})
      call_count = 1
      expect(result).to eq("call done")

      # Second call is cancelled before execution
      expect { tool.call({input: "second"}) }.to raise_error(RubyLLM::Agents::CancelledError)
    end
  end

  describe "Result#cancelled?" do
    it "returns true for cancelled results" do
      result = RubyLLM::Agents::Result.new(content: nil, cancelled: true)
      expect(result.cancelled?).to be true
    end

    it "returns false for normal results" do
      result = RubyLLM::Agents::Result.new(content: "hello")
      expect(result.cancelled?).to be false
    end
  end
end
