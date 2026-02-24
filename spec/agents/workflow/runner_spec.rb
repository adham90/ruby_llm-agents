# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Runner do
  let(:mock_response) { build_mock_response(content: "Result", input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: false)
  end

  let(:agent_a) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentA"
      model "gpt-4o"
      param :topic, required: false

      user "Write about {topic}"
    end
  end

  let(:agent_b) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentB"
      model "gpt-4o"
      param :content, required: false

      user "Edit: {content}"
    end
  end

  def build_workflow_class(steps:, pass_defs: [], on_failure: :stop)
    aa = agent_a
    ab = agent_b
    s = steps
    pd = pass_defs
    of = on_failure

    Class.new(RubyLLM::Agents::Workflow) {
      s.call(self, aa, ab)
      pd.each { |p| p.call(self) }
      on_failure of
    }
  end

  describe "#run" do
    it "executes steps in order based on dependency layers" do
      execution_order = []
      allow(agent_a).to receive(:call).and_wrap_original do |method, **kwargs|
        execution_order << :a
        method.call(**kwargs)
      end
      allow(agent_b).to receive(:call).and_wrap_original do |method, **kwargs|
        execution_order << :b
        method.call(**kwargs)
      end

      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
        step :b, ab, after: :a
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "AI")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run
      expect(execution_order).to eq([:a, :b])
    end

    it "stores step results in context" do
      aa = agent_a
      wf = Class.new(RubyLLM::Agents::Workflow) { step :a, aa }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "AI")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run

      expect(context.step_result(:a)).to be_a(RubyLLM::Agents::Result)
    end

    it "records step timings" do
      aa = agent_a
      wf = Class.new(RubyLLM::Agents::Workflow) { step :a, aa }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "AI")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      timings = runner.run
      expect(timings[:a]).to include(:started_at, :completed_at, :duration_ms)
    end

    it "stops on error when on_failure is :stop" do
      error_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ErrorAgent"
        model "gpt-4o"
      end
      allow(error_agent).to receive(:call).and_raise(StandardError, "boom")

      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :fail_step, error_agent
        step :after_fail, ab, after: :fail_step
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run
      expect(context.errors).to have_key(:fail_step)
      expect(context.step_result(:after_fail)).to be_nil
    end

    it "continues on error when on_failure is :continue" do
      error_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ErrorAgent"
        model "gpt-4o"
      end
      allow(error_agent).to receive(:call).and_raise(StandardError, "boom")

      aa = agent_a
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :fail_step, error_agent
        step :ok_step, aa
        on_failure :continue
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "test")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :continue
      )

      runner.run
      expect(context.errors).to have_key(:fail_step)
      expect(context.step_result(:ok_step)).to be_a(RubyLLM::Agents::Result)
    end

    it "skips steps that fail their condition" do
      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
        step :b, ab, if: ->(ctx) { ctx[:run_b] }
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "test", run_b: false)
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run
      expect(context.step_result(:a)).not_to be_nil
      expect(context.step_result(:b)).to be_nil
    end
  end

  describe "pass mappings" do
    it "maps output from one step to input of another" do
      received_params = nil
      allow(agent_b).to receive(:call) do |**params|
        received_params = params
        agent_b.allocate.tap { |i|
          i.instance_variable_set(:@options, params)
          allow(i).to receive(:call).and_return(
            RubyLLM::Agents::Result.new(
              content: "edited",
              input_tokens: 50,
              output_tokens: 25,
              model_id: "gpt-4o"
            )
          )
        }.call
      end

      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :draft, aa
        step :edit, ab, after: :draft
        pass :draft, to: :edit, as: {content: :content}
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "AI")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run

      # The edit step should have received the draft's content
      expect(received_params).to have_key(:content)
    end
  end
end
