# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow, "integration" do
  let(:mock_response) { build_mock_response(content: "Generated content", input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: true)
  end

  let(:research_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "ResearchAgent"
      model "gpt-4o"
      param :topic, required: false
      user "Research: {topic}"
    end
  end

  let(:draft_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "DraftAgent"
      model "gpt-4o"
      param :notes, required: false
      param :topic, required: false
      user "Draft about {topic} using {notes}"
    end
  end

  let(:edit_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "EditAgent"
      model "gpt-4o"
      param :content, required: false
      user "Edit: {content}"
    end
  end

  describe ".call" do
    it "executes a simple sequential workflow and returns WorkflowResult" do
      ra = research_agent
      da = draft_agent

      wf = Class.new(described_class) {
        step :research, ra
        step :draft, da, after: :research
      }

      result = wf.call(topic: "AI safety")

      expect(result).to be_a(RubyLLM::Agents::Workflow::WorkflowResult)
      expect(result.success?).to be true
      expect(result.step(:research)).to be_a(RubyLLM::Agents::Result)
      expect(result.step(:draft)).to be_a(RubyLLM::Agents::Result)
    end

    it "aggregates costs and tokens across steps" do
      ra = research_agent
      da = draft_agent
      ea = edit_agent

      wf = Class.new(described_class) {
        step :research, ra
        step :draft, da, after: :research
        step :edit, ea, after: :draft
        flow :research >> :draft >> :edit
      }

      result = wf.call(topic: "AI")

      expect(result.total_tokens).to be > 0
      expect(result.total_cost).to be >= 0
      expect(result.step_count).to eq(3)
      expect(result.duration_ms).to be >= 0
    end

    it "records execution in database" do
      ra = research_agent

      wf = Class.new(described_class) {
        def self.name = "TestWorkflow"
        step :research, ra
      }

      expect {
        wf.call(topic: "AI")
      }.to change(RubyLLM::Agents::Execution, :count)

      execution = RubyLLM::Agents::Execution.where(execution_type: "workflow").last
      expect(execution).not_to be_nil
      expect(execution.agent_type).to eq("TestWorkflow")
      expect(execution.execution_type).to eq("workflow")
      expect(execution.status).to eq("success")
    end

    it "handles workflow errors gracefully" do
      error_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ErrorAgent"
        model "gpt-4o"
      end
      allow(error_agent).to receive(:call).and_raise(StandardError, "test error")

      wf = Class.new(described_class) {
        step :fail_step, error_agent
      }

      result = wf.call

      expect(result.error?).to be true
      expect(result.errors).to have_key(:fail_step)
    end

    it "supports the flow DSL for sequential chaining" do
      execution_order = []

      ra = research_agent
      da = draft_agent
      ea = edit_agent

      allow(ra).to receive(:call).and_wrap_original do |method, **kwargs|
        execution_order << :research
        method.call(**kwargs)
      end
      allow(da).to receive(:call).and_wrap_original do |method, **kwargs|
        execution_order << :draft
        method.call(**kwargs)
      end
      allow(ea).to receive(:call).and_wrap_original do |method, **kwargs|
        execution_order << :edit
        method.call(**kwargs)
      end

      wf = Class.new(described_class) {
        step :research, ra
        step :draft, da
        step :edit, ea

        flow :research >> :draft >> :edit
      }

      wf.call(topic: "AI")

      expect(execution_order).to eq([:research, :draft, :edit])
    end

    it "passes data between steps via pass mappings" do
      received_content = nil
      ea = edit_agent
      allow(ea).to receive(:call) do |**params|
        received_content = params[:content]
        ea.allocate.tap { |i|
          i.instance_variable_set(:@options, params)
          i.instance_variable_set(:@model, "gpt-4o")
          i.instance_variable_set(:@temperature, nil)
          i.instance_variable_set(:@tracked_tool_calls, [])
        }.call
      end

      ra = research_agent
      wf = Class.new(described_class) {
        step :research, ra
        step :edit, ea, after: :research

        pass :research, to: :edit, as: {content: :content}
      }

      wf.call(topic: "AI")

      # The edit agent should have received the research content via pass
      expect(received_content).not_to be_nil
    end

    it "supports on_failure :continue to keep going after errors" do
      error_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "ErrorAgent"
        model "gpt-4o"
      end
      allow(error_agent).to receive(:call).and_raise(StandardError, "boom")

      ra = research_agent
      wf = Class.new(described_class) {
        step :fail_step, error_agent
        step :ok_step, ra
        on_failure :continue
      }

      result = wf.call(topic: "AI")

      expect(result.errors).to have_key(:fail_step)
      expect(result.step(:ok_step)).not_to be_nil
      expect(result.partial?).to be true
    end

    it "supports conditional steps with if:" do
      ra = research_agent
      da = draft_agent

      wf = Class.new(described_class) {
        step :research, ra
        step :draft, da, if: ->(ctx) { ctx[:include_draft] }
      }

      result = wf.call(topic: "AI", include_draft: false)

      expect(result.step(:research)).not_to be_nil
      expect(result.step(:draft)).to be_nil
    end

    context "without execution tracking" do
      before do
        stub_agent_configuration(track_executions: false)
      end

      it "still works without recording executions" do
        ra = research_agent
        wf = Class.new(described_class) {
          step :research, ra
        }

        result = wf.call(topic: "AI")

        expect(result.success?).to be true
        expect(result.execution_id).to be_nil
      end
    end
  end

  describe "#to_h serialization" do
    it "produces a complete hash" do
      ra = research_agent
      wf = Class.new(described_class) {
        step :research, ra
      }

      result = wf.call(topic: "AI")
      hash = result.to_h

      expect(hash).to include(
        :success, :step_count, :total_cost, :total_tokens,
        :duration_ms, :steps
      )
    end
  end
end
