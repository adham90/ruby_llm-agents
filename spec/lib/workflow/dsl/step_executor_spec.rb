# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::StepExecutor do
  let(:mock_agent) do
    Class.new do
      def self.name
        "MockAgent"
      end

      def self.call(**input)
        RubyLLM::Agents::Result.new(
          content: "processed: #{input[:query]}",
          model_id: "test-model"
        )
      end
    end
  end

  let(:workflow) do
    # Create an object that can handle send(:execute_agent, ...) properly
    workflow_class = Class.new do
      attr_accessor :input, :step_results, :execute_agent_handler, :error_handler

      def initialize
        @input = OpenStruct.new(query: "test")
        @step_results = {}
        @execute_agent_handler = nil
        @error_handler = nil
      end

      def step_result(name)
        @step_results[name]
      end

      def instance_exec(*args, &block)
        block&.call(*args)
      end

      def handle_error(error)
        if @error_handler
          @error_handler.call(error)
        else
          RubyLLM::Agents::Result.new(content: "handled", model_id: "test")
        end
      end

      private

      def execute_agent(agent, input, **opts, &block)
        if @execute_agent_handler
          @execute_agent_handler.call(agent, input, opts)
        else
          RubyLLM::Agents::Result.new(content: "default result", model_id: "test")
        end
      end
    end

    workflow_class.new
  end

  describe "#execute" do
    context "when condition not met" do
      it "returns skipped result" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          agent: mock_agent,
          options: { if: -> { false } }
        )
        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::SkippedResult)
        expect(result.step_name).to eq(:process)
        expect(result.reason).to eq("condition not met")
      end
    end

    context "agent step execution" do
      it "executes the agent and returns result" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          agent: mock_agent
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          RubyLLM::Agents::Result.new(content: "result", model_id: "test")
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Result)
        expect(result.content).to eq("result")
      end
    end

    context "block step execution" do
      it "executes custom block" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :custom,
          block: proc { "custom result" }
        )

        executor = described_class.new(workflow, config)

        # Need to set up the BlockContext properly
        allow_any_instance_of(RubyLLM::Agents::Workflow::DSL::BlockContext).to receive(:instance_exec) do |&block|
          block.call
        end

        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::DSL::SimpleResult)
        expect(result.content).to eq("custom result")
      end

      it "wraps block result in SimpleResult if not already a Result" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :custom,
          block: proc { { data: "value" } }
        )

        executor = described_class.new(workflow, config)
        allow_any_instance_of(RubyLLM::Agents::Workflow::DSL::BlockContext).to receive(:instance_exec) do |&block|
          block.call
        end

        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::DSL::SimpleResult)
        expect(result.content).to eq({ data: "value" })
      end
    end

    context "with timeout" do
      it "wraps execution in timeout" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :slow,
          agent: mock_agent,
          options: { timeout: 1 }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          RubyLLM::Agents::Result.new(content: "result", model_id: "test")
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Result)
      end
    end

    context "with retries" do
      it "retries on configured errors" do
        attempt = 0
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :flaky,
          agent: mock_agent,
          options: { retry: { max: 2, on: [StandardError], delay: 0 } }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          attempt += 1
          raise StandardError, "temporary error" if attempt < 2
          RubyLLM::Agents::Result.new(content: "success", model_id: "test")
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result.content).to eq("success")
        expect(attempt).to eq(2)
      end

      it "raises after max retries exceeded" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :always_fails,
          agent: mock_agent,
          options: { retry: { max: 2, on: [StandardError], delay: 0 } }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          raise StandardError, "persistent error"
        }

        executor = described_class.new(workflow, config)

        expect { executor.execute }.to raise_error(StandardError, "persistent error")
      end
    end

    context "with fallbacks" do
      let(:fallback_agent) do
        Class.new do
          def self.name
            "FallbackAgent"
          end
        end
      end

      it "tries fallback on error" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :step_with_fallback,
          agent: mock_agent,
          options: { fallback: fallback_agent }
        )

        call_count = 0
        workflow.execute_agent_handler = ->(agent, input, opts) {
          call_count += 1
          if agent == mock_agent
            raise StandardError, "primary failed"
          else
            RubyLLM::Agents::Result.new(content: "fallback result", model_id: "test")
          end
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result.content).to eq("fallback result")
        expect(call_count).to eq(2)
      end
    end

    context "optional steps" do
      it "returns error result without raising for optional steps" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :optional_step,
          agent: mock_agent,
          options: { optional: true }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          raise StandardError, "step failed"
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Pipeline::ErrorResult)
        expect(result.error_class).to eq("StandardError")
      end

      it "returns default value when configured" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :optional_with_default,
          agent: mock_agent,
          options: { optional: true, default: "default value" }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          raise StandardError, "step failed"
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::DSL::SimpleResult)
        expect(result.content).to eq("default value")
      end
    end

    context "error handlers" do
      it "invokes symbol error handler" do
        handler_called_with = nil
        workflow.define_singleton_method(:handle_step_error) do |error|
          handler_called_with = error
          # Must return a Workflow::Result, not an Agents::Result
          RubyLLM::Agents::Workflow::Result.new(
            content: "error handled",
            workflow_type: "Test",
            status: "success"
          )
        end

        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :failing_step,
          agent: mock_agent,
          options: { on_error: :handle_step_error }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          raise StandardError, "step failed"
        }

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(handler_called_with).to be_a(StandardError)
        expect(handler_called_with.message).to eq("step failed")
        expect(result.content).to eq("error handled")
      end

      it "invokes proc error handler" do
        handler_called_with = nil
        error_proc = proc do |error|
          handler_called_with = error
          # Must return a Workflow::Result, not an Agents::Result
          RubyLLM::Agents::Workflow::Result.new(
            content: "proc handled",
            workflow_type: "Test",
            status: "success"
          )
        end

        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :failing_step,
          agent: mock_agent,
          options: { on_error: error_proc }
        )

        workflow.execute_agent_handler = ->(agent, input, opts) {
          raise StandardError, "step error"
        }

        # Override instance_exec to call the proc with the error
        workflow.define_singleton_method(:instance_exec) do |error, &block|
          block.call(error)
        end

        executor = described_class.new(workflow, config)
        result = executor.execute

        expect(handler_called_with).to be_a(StandardError)
        expect(handler_called_with.message).to eq("step error")
        expect(result.content).to eq("proc handled")
      end
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::BlockContext do
  let(:workflow) do
    double("workflow").tap do |w|
      allow(w).to receive(:input).and_return(OpenStruct.new(query: "test"))
      allow(w).to receive(:step_results).and_return({ prev: double(content: "previous") })
      allow(w).to receive(:send)
      allow(w).to receive(:respond_to?).and_return(false)
    end
  end

  let(:config) do
    RubyLLM::Agents::Workflow::DSL::StepConfig.new(name: :test)
  end

  let(:previous_result) do
    double("result", content: "previous data")
  end

  let(:context) { described_class.new(workflow, config, previous_result) }

  describe "#input" do
    it "returns workflow input" do
      expect(context.input.query).to eq("test")
    end
  end

  describe "#previous" do
    it "returns previous step result" do
      expect(context.previous).to eq(previous_result)
    end
  end

  describe "#skip!" do
    it "throws :skip_step with skipped info" do
      expect {
        context.skip!("reason", default: "default")
      }.to throw_symbol(:skip_step, { skipped: true, reason: "reason", default: "default" })
    end
  end

  describe "#halt!" do
    it "throws :halt_workflow" do
      expect {
        context.halt!({ final: "result" })
      }.to throw_symbol(:halt_workflow, { halted: true, result: { final: "result" } })
    end
  end

  describe "#fail!" do
    it "raises StepFailedError" do
      expect {
        context.fail!("step failed")
      }.to raise_error(RubyLLM::Agents::Workflow::DSL::StepFailedError, "step failed")
    end
  end

  describe "#retry!" do
    it "raises RetryStep" do
      expect {
        context.retry!("retry reason")
      }.to raise_error(RubyLLM::Agents::Workflow::DSL::RetryStep, "retry reason")
    end
  end

  describe "method delegation to workflow" do
    it "delegates unknown methods to workflow" do
      allow(workflow).to receive(:respond_to?).with(:custom_method, true).and_return(true)
      allow(workflow).to receive(:send).with(:custom_method, "arg").and_return("result")

      result = context.custom_method("arg")

      expect(result).to eq("result")
    end

    it "raises NoMethodError for unknown methods" do
      expect {
        context.unknown_method
      }.to raise_error(NoMethodError)
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::SimpleResult do
  describe "#initialize" do
    it "creates a result with content" do
      result = described_class.new(content: "test", success: true)

      expect(result.content).to eq("test")
      expect(result.success?).to be true
      expect(result.error?).to be false
    end
  end

  describe "token and cost methods" do
    let(:result) { described_class.new(content: "test", success: true) }

    it "returns zero for all metrics" do
      expect(result.input_tokens).to eq(0)
      expect(result.output_tokens).to eq(0)
      expect(result.total_tokens).to eq(0)
      expect(result.cached_tokens).to eq(0)
      expect(result.input_cost).to eq(0.0)
      expect(result.output_cost).to eq(0.0)
      expect(result.total_cost).to eq(0.0)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      result = described_class.new(content: { data: "value" }, success: true)

      expect(result.to_h).to eq({ content: { data: "value" }, success: true })
    end
  end
end
