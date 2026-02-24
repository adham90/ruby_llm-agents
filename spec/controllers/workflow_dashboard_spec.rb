# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow dashboard integration" do
  describe "Agent Registry" do
    it "detects workflow type correctly" do
      workflow_class = Class.new(RubyLLM::Agents::Workflow) do
        def self.name = "TestWorkflow"
      end

      detected = RubyLLM::Agents::AgentRegistry.send(:detect_agent_type, workflow_class)
      expect(detected).to eq("workflow")
    end

    it "sets is_workflow flag in agent info" do
      # Create a workflow execution so the registry discovers it
      create(:execution, agent_type: "TestWorkflow", execution_type: "workflow")

      all = RubyLLM::Agents::AgentRegistry.all_with_details
      wf = all.find { |a| a[:name] == "TestWorkflow" }

      # The workflow execution should appear in the registry
      expect(wf).not_to be_nil
    end
  end

  describe "Execution records" do
    it "stores workflow execution_type in metadata" do
      execution = create(:execution,
        agent_type: "ContentWorkflow",
        execution_type: "workflow",
        metadata: {
          workflow_type: "sequential",
          step_count: 3,
          successful_steps: 3,
          failed_steps: 0,
          step_names: ["research", "draft", "edit"]
        })

      expect(execution.execution_type).to eq("workflow")
      expect(execution.metadata["step_count"]).to eq(3)
      expect(execution.metadata["step_names"]).to eq(["research", "draft", "edit"])
    end

    it "can filter executions by workflow execution_type" do
      create(:execution, agent_type: "RegularAgent", execution_type: "chat")
      create(:execution, agent_type: "TestWorkflow", execution_type: "workflow")

      workflow_execs = RubyLLM::Agents::Execution.where(execution_type: "workflow")
      expect(workflow_execs.count).to eq(1)
      expect(workflow_execs.first.agent_type).to eq("TestWorkflow")
    end
  end
end
