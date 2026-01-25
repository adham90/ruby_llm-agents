# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Recursion support" do
  describe "max_recursion_depth class method" do
    it "sets and gets max_recursion_depth" do
      klass = Class.new(RubyLLM::Agents::Workflow) do
        max_recursion_depth 5
      end
      expect(klass.max_recursion_depth).to eq(5)
    end

    it "defaults to 10" do
      klass = Class.new(RubyLLM::Agents::Workflow)
      expect(klass.max_recursion_depth).to eq(10)
    end

    it "converts to integer" do
      klass = Class.new(RubyLLM::Agents::Workflow) do
        max_recursion_depth "7"
      end
      expect(klass.max_recursion_depth).to eq(7)
    end
  end

  describe "RecursionDepthExceededError" do
    it "includes depth information" do
      error = RubyLLM::Agents::RecursionDepthExceededError.new(
        "Depth exceeded",
        current_depth: 11,
        max_depth: 10
      )
      expect(error.current_depth).to eq(11)
      expect(error.max_depth).to eq(10)
      expect(error.message).to eq("Depth exceeded")
    end
  end

  describe "recursion depth tracking" do
    let(:workflow_class) do
      Class.new(RubyLLM::Agents::Workflow) do
        max_recursion_depth 5

        step :process do
          { depth: recursion_depth }
        end
      end
    end

    it "starts at depth 0 by default" do
      workflow = workflow_class.new
      expect(workflow.recursion_depth).to eq(0)
    end

    it "extracts depth from execution_metadata" do
      workflow = workflow_class.new(
        execution_metadata: { recursion_depth: 3 }
      )
      expect(workflow.recursion_depth).to eq(3)
    end

    it "raises error when depth exceeds max" do
      expect {
        workflow_class.new(
          execution_metadata: { recursion_depth: 6 }
        )
      }.to raise_error(RubyLLM::Agents::RecursionDepthExceededError)
    end

    it "allows depth equal to max" do
      expect {
        workflow_class.new(
          execution_metadata: { recursion_depth: 5 }
        )
      }.not_to raise_error
    end
  end

  describe "self-referential workflow detection" do
    let(:recursive_workflow_class) do
      klass = Class.new(RubyLLM::Agents::Workflow)
      # Simulate a recursive workflow reference
      klass.class_eval do
        step :process do
          { result: "done" }
        end
      end
      klass
    end

    it "identifies workflow steps in step_metadata" do
      inner_workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :inner_step do
          { processed: true }
        end
      end

      outer_workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :run_sub, inner_workflow
      end

      metadata = outer_workflow.step_metadata.first
      expect(metadata[:workflow]).to be true
    end
  end

  describe "budget inheritance in recursive calls" do
    let(:workflow_with_budget) do
      Class.new(RubyLLM::Agents::Workflow) do
        max_cost 1.00

        step :process do
          { done: true }
        end
      end
    end

    it "respects remaining_cost_budget from parent" do
      workflow = workflow_with_budget.new(
        execution_metadata: { remaining_cost_budget: 0.25 }
      )
      expect(workflow.instance_variable_get(:@remaining_cost_budget)).to eq(0.25)
    end

    it "respects remaining_timeout from parent" do
      workflow = workflow_with_budget.new(
        execution_metadata: { remaining_timeout: 30 }
      )
      expect(workflow.instance_variable_get(:@remaining_timeout)).to eq(30)
    end
  end

  describe "step_metadata with recursion indicators" do
    let(:self_referential_workflow) do
      inner = Class.new(RubyLLM::Agents::Workflow) do
        step :inner do
          { processed: true }
        end
      end

      Class.new(RubyLLM::Agents::Workflow) do
        max_recursion_depth 3

        step :process do
          { result: "processed" }
        end

        step :recurse, inner,
             if: -> { should_recurse? }
      end
    end

    it "includes workflow flag in step_metadata" do
      metadata = self_referential_workflow.step_metadata
      recurse_step = metadata.find { |m| m[:name] == :recurse }
      expect(recurse_step[:workflow]).to be true
    end
  end
end
