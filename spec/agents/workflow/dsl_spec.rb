# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL do
  let(:agent_a) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentA"
      model "gpt-4o"
      param :topic, required: true
    end
  end

  let(:agent_b) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentB"
      model "gpt-4o"
    end
  end

  let(:agent_c) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "AgentC"
      model "gpt-4o"
    end
  end

  def build_workflow(&block)
    aa = agent_a
    ab = agent_b
    ac = agent_c
    Class.new(RubyLLM::Agents::Workflow) do
      define_method(:agent_a) { aa }
      define_method(:agent_b) { ab }
      define_method(:agent_c) { ac }
      class_eval(&block)
    end
  end

  describe "step" do
    it "registers a step with agent class" do
      aa = agent_a
      wf = Class.new(RubyLLM::Agents::Workflow) { step :draft, aa }

      expect(wf.steps.size).to eq(1)
      expect(wf.steps.first.name).to eq(:draft)
      expect(wf.steps.first.agent_class).to eq(agent_a)
    end

    it "accepts params and after" do
      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :draft, aa, params: {tone: "formal"}
        step :edit, ab, after: :draft
      }

      edit = wf.steps.find { |s| s.name == :edit }
      expect(edit.after_steps).to eq([:draft])
    end

    it "raises on duplicate step names" do
      aa = agent_a
      expect {
        Class.new(RubyLLM::Agents::Workflow) {
          step :draft, aa
          step :draft, aa
        }
      }.to raise_error(ArgumentError, /already defined/)
    end
  end

  describe "flow" do
    it "creates dependencies from FlowChain" do
      aa = agent_a
      ab = agent_b
      ac = agent_c
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :research, aa
        step :draft, ab
        step :edit, ac

        flow :research >> :draft >> :edit
      }

      draft = wf.steps.find { |s| s.name == :draft }
      edit = wf.steps.find { |s| s.name == :edit }

      expect(draft.after_steps).to include(:research)
      expect(edit.after_steps).to include(:draft)
    end

    it "accepts an array" do
      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
        step :b, ab

        flow [:a, :b]
      }

      b = wf.steps.find { |s| s.name == :b }
      expect(b.after_steps).to include(:a)
    end

    it "raises for unknown step in flow" do
      aa = agent_a
      expect {
        Class.new(RubyLLM::Agents::Workflow) {
          step :a, aa
          flow :a >> :nonexistent
        }
      }.to raise_error(ArgumentError, /Unknown step/)
    end
  end

  describe "pass" do
    it "stores pass definitions" do
      aa = agent_a
      ab = agent_b
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :draft, aa
        step :edit, ab, after: :draft

        pass :draft, to: :edit, as: {content: :draft_text}
      }

      expect(wf.pass_definitions.size).to eq(1)
      expect(wf.pass_definitions.first[:from]).to eq(:draft)
      expect(wf.pass_definitions.first[:to]).to eq(:edit)
      expect(wf.pass_definitions.first[:mapping]).to eq({content: :draft_text})
    end
  end

  describe "description" do
    it "sets and gets description" do
      wf = Class.new(RubyLLM::Agents::Workflow) {
        description "Test workflow"
      }

      expect(wf.description).to eq("Test workflow")
    end
  end

  describe "on_failure" do
    it "defaults to :stop" do
      wf = Class.new(RubyLLM::Agents::Workflow)
      expect(wf.on_failure).to eq(:stop)
    end

    it "can be set to :continue" do
      wf = Class.new(RubyLLM::Agents::Workflow) {
        on_failure :continue
      }
      expect(wf.on_failure).to eq(:continue)
    end

    it "raises for invalid strategy" do
      expect {
        Class.new(RubyLLM::Agents::Workflow) {
          on_failure :invalid
        }
      }.to raise_error(ArgumentError, /must be :stop or :continue/)
    end
  end

  describe "budget" do
    it "sets budget limit" do
      wf = Class.new(RubyLLM::Agents::Workflow) {
        budget 5.0
      }
      expect(wf.budget_limit).to eq(5.0)
    end
  end

  describe "inheritance" do
    it "inherits steps from parent" do
      aa = agent_a
      ab = agent_b
      parent = Class.new(RubyLLM::Agents::Workflow) {
        step :a, aa
      }
      child = Class.new(parent) {
        step :b, ab
      }

      expect(child.steps.size).to eq(2)
      expect(child.steps.map(&:name)).to eq([:a, :b])

      # Parent unchanged
      expect(parent.steps.size).to eq(1)
    end

    it "inherits description" do
      parent = Class.new(RubyLLM::Agents::Workflow) {
        description "Parent workflow"
      }
      child = Class.new(parent)

      expect(child.description).to eq("Parent workflow")
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::FlowChain do
  describe "Symbol#>>" do
    it "creates a FlowChain from two symbols" do
      chain = :a >> :b
      expect(chain).to be_a(described_class)
      expect(chain.steps).to eq([:a, :b])
    end

    it "chains multiple symbols" do
      chain = :a >> :b >> :c >> :d
      expect(chain.steps).to eq([:a, :b, :c, :d])
    end
  end
end
