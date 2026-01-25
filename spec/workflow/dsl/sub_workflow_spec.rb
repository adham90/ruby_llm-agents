# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sub-workflow composition" do
  # Simple sub-workflow for testing
  let(:inner_workflow_class) do
    Class.new(RubyLLM::Agents::Workflow) do
      description "Inner workflow"

      step :process do
        { result: "inner_processed", received: input.data }
      end
    end
  end

  # Outer workflow that calls the inner workflow
  let(:outer_workflow_class) do
    inner = inner_workflow_class
    Class.new(RubyLLM::Agents::Workflow) do
      description "Outer workflow"
      define_method(:inner_workflow) { inner }

      step :prepare do
        { data: "prepared_data" }
      end

      step :run_inner, inner,
           input: -> { { data: prepare[:data] } }

      step :finalize do
        {
          outer_result: "completed",
          inner_result: run_inner.content
        }
      end
    end
  end

  describe "StepConfig#workflow?" do
    it "returns true for workflow subclasses" do
      config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
        name: :test,
        agent: inner_workflow_class
      )
      expect(config.workflow?).to be true
    end

    it "returns false for regular agent classes" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
        name: :test,
        agent: agent_class
      )
      expect(config.workflow?).to be false
    end

    it "returns false when agent is nil" do
      config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
        name: :test,
        agent: nil
      )
      expect(config.workflow?).to be false
    end

    it "returns false for non-class values" do
      config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
        name: :test,
        agent: "not_a_class"
      )
      expect(config.workflow?).to be false
    end
  end

  describe "SubWorkflowResult" do
    let(:step_result_double) do
      double(
        content: "step_content",
        input_tokens: 10,
        output_tokens: 5,
        cached_tokens: 0,
        input_cost: 0.005,
        output_cost: 0.005,
        total_cost: 0.01,
        to_h: { content: "step_content" }
      )
    end

    let(:inner_result) do
      RubyLLM::Agents::Workflow::Result.new(
        content: { processed: true },
        status: "success",
        steps: { process: step_result_double }
      )
    end

    let(:result) do
      RubyLLM::Agents::Workflow::SubWorkflowResult.new(
        content: { processed: true },
        sub_workflow_result: inner_result,
        workflow_type: "TestWorkflow",
        step_name: :run_sub
      )
    end

    it "exposes content" do
      expect(result.content).to eq(processed: true)
    end

    it "exposes workflow_type" do
      expect(result.workflow_type).to eq("TestWorkflow")
    end

    it "exposes step_name" do
      expect(result.step_name).to eq(:run_sub)
    end

    it "delegates success? to sub_workflow_result" do
      expect(result.success?).to be true
    end

    it "aggregates metrics from sub_workflow_result" do
      expect(result.input_tokens).to eq(inner_result.input_tokens)
      expect(result.output_tokens).to eq(inner_result.output_tokens)
      expect(result.total_cost).to eq(inner_result.total_cost)
    end

    it "provides access to sub-workflow steps" do
      expect(result.steps).to eq(inner_result.steps)
    end

    it "supports hash access on content" do
      expect(result[:processed]).to be true
    end

    it "converts to hash" do
      hash = result.to_h
      expect(hash[:content]).to eq(processed: true)
      expect(hash[:workflow_type]).to eq("TestWorkflow")
      expect(hash[:step_name]).to eq(:run_sub)
    end
  end

  describe "budget inheritance" do
    let(:outer_workflow_with_budget) do
      inner = inner_workflow_class
      Class.new(RubyLLM::Agents::Workflow) do
        timeout 60
        max_cost 0.10

        step :run_inner, inner
      end
    end

    it "tracks accumulated cost from sub-workflows" do
      # This test verifies the structure exists; actual cost tracking
      # requires integration with real API calls
      workflow = outer_workflow_with_budget.new
      expect(workflow.instance_variable_get(:@accumulated_cost)).to eq(0.0)
    end
  end
end
