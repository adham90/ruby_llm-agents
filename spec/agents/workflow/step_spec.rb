# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Step do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "TestAgent"
      model "gpt-4o"
      param :topic, required: true
    end
  end

  describe "#initialize" do
    it "creates a step with required attributes" do
      step = described_class.new(:draft, agent_class)

      expect(step.name).to eq(:draft)
      expect(step.agent_class).to eq(agent_class)
      expect(step.params).to eq({})
      expect(step.after_steps).to eq([])
    end

    it "accepts params, after, and conditions" do
      condition = ->(ctx) { ctx[:ready] }
      step = described_class.new(
        :draft, agent_class,
        params: {tone: "formal"},
        after: [:research],
        if_condition: condition
      )

      expect(step.params).to eq({tone: "formal"})
      expect(step.after_steps).to eq([:research])
    end

    it "converts name to symbol" do
      step = described_class.new("draft", agent_class)
      expect(step.name).to eq(:draft)
    end

    it "converts after to array of symbols" do
      step = described_class.new(:draft, agent_class, after: :research)
      expect(step.after_steps).to eq([:research])
    end

    it "raises if agent_class does not respond to .call" do
      expect {
        described_class.new(:bad, Object)
      }.to raise_error(ArgumentError, /must respond to .call/)
    end
  end

  describe "#should_run?" do
    let(:context) { RubyLLM::Agents::Workflow::WorkflowContext.new(ready: true) }

    it "returns true when no conditions" do
      step = described_class.new(:draft, agent_class)
      expect(step.should_run?(context)).to be true
    end

    it "evaluates if_condition proc" do
      step = described_class.new(:draft, agent_class, if_condition: ->(ctx) { ctx[:ready] })
      expect(step.should_run?(context)).to be true
    end

    it "skips when if_condition is falsy" do
      step = described_class.new(:draft, agent_class, if_condition: ->(ctx) { ctx[:missing] })
      expect(step.should_run?(context)).to be false
    end

    it "evaluates unless_condition" do
      step = described_class.new(:draft, agent_class, unless_condition: ->(ctx) { ctx[:ready] })
      expect(step.should_run?(context)).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      step = described_class.new(:draft, agent_class, params: {tone: "formal"}, after: [:research])
      hash = step.to_h

      expect(hash[:name]).to eq(:draft)
      expect(hash[:agent_class]).to eq("TestAgent")
      expect(hash[:params]).to eq({tone: "formal"})
      expect(hash[:after_steps]).to eq([:research])
    end
  end

  describe "#add_pass_mapping" do
    it "accumulates pass mappings" do
      step = described_class.new(:edit, agent_class)
      step.add_pass_mapping(content: :draft_text)

      expect(step.pass_mappings).to eq([{content: :draft_text}])
    end
  end
end
