# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::ParallelGroup do
  describe "#initialize" do
    it "stores the name" do
      group = described_class.new(name: :analysis)
      expect(group.name).to eq(:analysis)
    end

    it "stores step names" do
      group = described_class.new(step_names: [:step1, :step2])
      expect(group.step_names).to eq([:step1, :step2])
    end

    it "stores options" do
      group = described_class.new(options: { fail_fast: true, concurrency: 5 })
      expect(group.fail_fast?).to be true
      expect(group.concurrency).to eq(5)
    end
  end

  describe "#add_step" do
    it "adds a step to the group" do
      group = described_class.new
      group.add_step(:new_step)
      expect(group.step_names).to include(:new_step)
    end
  end

  describe "#size" do
    it "returns the number of steps" do
      group = described_class.new(step_names: [:a, :b, :c])
      expect(group.size).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns true when no steps" do
      expect(described_class.new.empty?).to be true
    end

    it "returns false when steps exist" do
      group = described_class.new(step_names: [:step])
      expect(group.empty?).to be false
    end
  end

  describe "#fail_fast?" do
    it "returns false by default" do
      group = described_class.new
      expect(group.fail_fast?).to be false
    end

    it "returns true when set" do
      group = described_class.new(options: { fail_fast: true })
      expect(group.fail_fast?).to be true
    end
  end

  describe "#concurrency" do
    it "returns nil by default" do
      group = described_class.new
      expect(group.concurrency).to be_nil
    end

    it "returns the configured value" do
      group = described_class.new(options: { concurrency: 3 })
      expect(group.concurrency).to eq(3)
    end
  end

  describe "#timeout" do
    it "returns nil by default" do
      group = described_class.new
      expect(group.timeout).to be_nil
    end

    it "returns the configured value" do
      group = described_class.new(options: { timeout: 60 })
      expect(group.timeout).to eq(60)
    end
  end

  describe "#to_h" do
    it "serializes the group" do
      group = described_class.new(
        name: :analysis,
        step_names: [:step1, :step2],
        options: { fail_fast: true, concurrency: 5 }
      )

      hash = group.to_h

      expect(hash[:name]).to eq(:analysis)
      expect(hash[:step_names]).to eq([:step1, :step2])
      expect(hash[:fail_fast]).to be true
      expect(hash[:concurrency]).to eq(5)
    end
  end

  describe "#inspect" do
    it "returns a readable string" do
      group = described_class.new(name: :analysis, step_names: [:step1])
      expect(group.inspect).to include("ParallelGroup")
      expect(group.inspect).to include("analysis")
      expect(group.inspect).to include("step1")
    end
  end
end
