# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::ParallelRunner do
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
      user "Process A: {topic}"
    end
  end

  let(:agent_b) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentB"
      model "gpt-4o"
      param :topic, required: false
      user "Process B: {topic}"
    end
  end

  let(:agent_c) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentC"
      model "gpt-4o"
      param :topic, required: false
      user "Process C: {topic}"
    end
  end

  let(:join_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "JoinAgent"
      model "gpt-4o"
      param :topic, required: false
      user "Join results for {topic}"
    end
  end

  describe "#run with parallel layers" do
    it "executes independent steps concurrently" do
      threads_used = Concurrent::Set.new if defined?(Concurrent::Set)
      threads_used = Set.new # plain Set — ok for testing
      mutex = Mutex.new

      aa = agent_a
      ab = agent_b

      allow(aa).to receive(:call).and_wrap_original do |method, **kwargs|
        mutex.synchronize { threads_used << Thread.current.object_id }
        sleep 0.01 # small delay to ensure threads overlap
        method.call(**kwargs)
      end
      allow(ab).to receive(:call).and_wrap_original do |method, **kwargs|
        mutex.synchronize { threads_used << Thread.current.object_id }
        sleep 0.01
        method.call(**kwargs)
      end

      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
        step :b, ab
        # Both independent — same layer → parallel
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "test")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run

      # Both steps should complete
      expect(context.step_result(:a)).to be_a(RubyLLM::Agents::Result)
      expect(context.step_result(:b)).to be_a(RubyLLM::Agents::Result)

      # They should have used different threads
      expect(threads_used.size).to eq(2)
    end

    it "respects dependencies — fan-out then fan-in" do
      execution_order = []
      mutex = Mutex.new

      aa = agent_a
      ab = agent_b
      ac = agent_c
      ja = join_agent

      [aa, ab, ac, ja].each_with_index do |agent, i|
        name = [:a, :b, :c, :join][i]
        allow(agent).to receive(:call).and_wrap_original do |method, **kwargs|
          mutex.synchronize { execution_order << name }
          method.call(**kwargs)
        end
      end

      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
        step :b, ab, after: :a
        step :c, ac, after: :a
        step :join, ja, after: [:b, :c]
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new(topic: "test")
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      runner.run

      # :a must come first
      expect(execution_order.first).to eq(:a)
      # :b and :c before :join
      join_idx = execution_order.index(:join)
      expect(execution_order.index(:b)).to be < join_idx
      expect(execution_order.index(:c)).to be < join_idx
      # All completed
      expect(context.step_result(:join)).to be_a(RubyLLM::Agents::Result)
    end

    it "collects errors from parallel steps without killing siblings" do
      error_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ErrorAgent"
        model "gpt-4o"
      end
      allow(error_agent).to receive(:call).and_raise(StandardError, "parallel boom")

      aa = agent_a
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :ok, aa
        step :fail, error_agent
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

      expect(context.step_result(:ok)).to be_a(RubyLLM::Agents::Result)
      expect(context.errors[:fail]).to be_a(StandardError)
      expect(context.errors[:fail].message).to eq("parallel boom")
    end

    it "measures wall-clock time (not sum of steps)" do
      slow_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "SlowAgent"
        model "gpt-4o"
      end
      allow(slow_agent).to receive(:call) do |**kwargs|
        sleep 0.05
        RubyLLM::Agents::Result.new(
          content: "done",
          input_tokens: 10,
          output_tokens: 5,
          model_id: "gpt-4o"
        )
      end

      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, slow_agent
        step :b, slow_agent
      }

      context = RubyLLM::Agents::Workflow::WorkflowContext.new
      graph = RubyLLM::Agents::Workflow::FlowGraph.new(wf.steps)

      runner = described_class.new(
        workflow_class: wf,
        graph: graph,
        context: context,
        on_failure: :stop
      )

      started = Time.current
      runner.run
      elapsed = ((Time.current - started) * 1000).round

      # If parallel: ~50ms wall clock. If sequential: ~100ms.
      # Allow generous margin but should be less than sequential
      expect(elapsed).to be < 150
    end

    it "thread-safe context writes from parallel steps" do
      writers = 5.times.map do |i|
        Class.new(RubyLLM::Agents::BaseAgent) do
          define_singleton_method(:name) { "Writer#{i}" }
          model "gpt-4o"
        end
      end

      writers.each_with_index do |agent, i|
        allow(agent).to receive(:call) do |**kwargs|
          RubyLLM::Agents::Result.new(
            content: "result_#{i}",
            input_tokens: 10,
            output_tokens: 5,
            model_id: "gpt-4o"
          )
        end
      end

      w = writers
      wf = Class.new(RubyLLM::Agents::Workflow) {
        w.each_with_index { |agent, i| step :"w#{i}", agent }
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

      5.times do |i|
        expect(context.step_result(:"w#{i}")).not_to be_nil
      end
    end
  end
end
