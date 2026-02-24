# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::FlowGraph do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "TestAgent"
      model "gpt-4o"
    end
  end

  def build_step(name, after: [])
    RubyLLM::Agents::Workflow::Step.new(name, agent_class, after: after)
  end

  describe "#execution_layers" do
    it "returns empty array for no steps" do
      graph = described_class.new([])
      expect(graph.execution_layers).to eq([])
    end

    it "puts independent steps in the same layer" do
      steps = [build_step(:a), build_step(:b), build_step(:c)]
      graph = described_class.new(steps)

      layers = graph.execution_layers
      expect(layers).to eq([[:a, :b, :c]])
    end

    it "respects sequential dependencies" do
      steps = [
        build_step(:a),
        build_step(:b, after: [:a]),
        build_step(:c, after: [:b])
      ]
      graph = described_class.new(steps)

      layers = graph.execution_layers
      expect(layers).to eq([[:a], [:b], [:c]])
    end

    it "groups parallel steps and respects fan-in" do
      steps = [
        build_step(:a),
        build_step(:b, after: [:a]),
        build_step(:c, after: [:a]),
        build_step(:d, after: [:b, :c])
      ]
      graph = described_class.new(steps)

      layers = graph.execution_layers
      expect(layers).to eq([[:a], [:b, :c], [:d]])
    end

    it "handles diamond dependency" do
      steps = [
        build_step(:start),
        build_step(:left, after: [:start]),
        build_step(:right, after: [:start]),
        build_step(:join, after: [:left, :right])
      ]
      graph = described_class.new(steps)

      layers = graph.execution_layers
      expect(layers).to eq([[:start], [:left, :right], [:join]])
    end

    it "raises CyclicDependencyError for circular deps" do
      steps = [
        build_step(:a, after: [:b]),
        build_step(:b, after: [:a])
      ]

      expect {
        described_class.new(steps).execution_layers
      }.to raise_error(RubyLLM::Agents::Workflow::CyclicDependencyError)
    end
  end

  describe "#step" do
    it "looks up a step by name" do
      steps = [build_step(:a), build_step(:b)]
      graph = described_class.new(steps)

      expect(graph.step(:a).name).to eq(:a)
      expect(graph.step(:unknown)).to be_nil
    end
  end

  describe "validation" do
    it "raises on duplicate step names" do
      steps = [build_step(:a), build_step(:a)]

      expect {
        described_class.new(steps)
      }.to raise_error(ArgumentError, /Duplicate step names/)
    end

    it "raises when step depends on unknown step" do
      steps = [build_step(:a, after: [:nonexistent])]

      expect {
        described_class.new(steps)
      }.to raise_error(ArgumentError, /unknown step/)
    end
  end
end
