# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Instrumentation do
  include ActiveSupport::Testing::TimeHelpers

  # Create a test workflow class that includes the instrumentation module
  let(:test_workflow_class) do
    Class.new(RubyLLM::Agents::Workflow) do
      version "1.0.0"

      def self.name
        "TestWorkflow"
      end
    end
  end

  let(:workflow) { test_workflow_class.new(input: "test") }
  let(:mock_result) do
    RubyLLM::Agents::Workflow::Result.new(
      content: "test content",
      workflow_type: "TestWorkflow",
      workflow_id: workflow.workflow_id,
      status: "success",
      steps: {},
      branches: {}
    )
  end

  describe "#instrument_workflow" do
    context "when execution succeeds" do
      it "creates an execution record" do
        expect {
          workflow.instrument_workflow { mock_result }
        }.to change(RubyLLM::Agents::Execution, :count).by(1)
      end

      it "sets execution status to running initially" do
        execution = nil
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_wrap_original do |method, **args|
          expect(args[:status]).to eq("running")
          execution = method.call(**args)
        end

        workflow.instrument_workflow { mock_result }
      end

      it "updates execution to success on completion" do
        result = workflow.instrument_workflow { mock_result }
        execution = RubyLLM::Agents::Execution.last

        expect(execution.status).to eq("success")
        expect(result).to eq(mock_result)
      end

      it "stores workflow metadata" do
        workflow.instrument_workflow { mock_result }
        execution = RubyLLM::Agents::Execution.last

        expect(execution.workflow_id).to eq(workflow.workflow_id)
        expect(execution.workflow_type).to eq("workflow")
        expect(execution.model_id).to eq("workflow")
      end

      it "calculates duration_ms" do
        workflow.instrument_workflow do
          sleep(0.01)
          mock_result
        end
        execution = RubyLLM::Agents::Execution.last

        expect(execution.duration_ms).to be >= 10
      end

      it "stores aggregate metrics from result" do
        step_result = RubyLLM::Agents::TestSupport::MockStepResult.successful(
          total_cost: 0.01,
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 10,
          input_cost: 0.005,
          output_cost: 0.005,
          duration_ms: 100
        )

        result_with_metrics = RubyLLM::Agents::Workflow::Result.new(
          content: "test",
          status: "success",
          steps: { step1: step_result }
        )

        workflow.instrument_workflow { result_with_metrics }
        execution = RubyLLM::Agents::Execution.last

        expect(execution.input_tokens).to eq(100)
        expect(execution.output_tokens).to eq(50)
        expect(execution.total_tokens).to eq(150)
      end

      it "sets execution_id on the workflow" do
        workflow.instrument_workflow { mock_result }

        expect(workflow.execution_id).to be_present
        expect(workflow.execution_id).to eq(RubyLLM::Agents::Execution.last.id)
      end

      it "returns the result" do
        result = workflow.instrument_workflow { mock_result }

        expect(result).to eq(mock_result)
      end
    end

    context "when execution fails with StandardError" do
      it "updates execution status to error" do
        expect {
          workflow.instrument_workflow { raise StandardError, "Test error" }
        }.to raise_error(StandardError, "Test error")

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("StandardError")
        expect(execution.error_message).to eq("Test error")
      end

      it "re-raises the error" do
        expect {
          workflow.instrument_workflow { raise StandardError, "Test error" }
        }.to raise_error(StandardError, "Test error")
      end
    end

    context "when execution times out" do
      let(:test_workflow_class_with_timeout) do
        Class.new(RubyLLM::Agents::Workflow) do
          version "1.0.0"
          timeout 0.01 # 10ms timeout

          def self.name
            "TimeoutWorkflow"
          end
        end
      end

      it "updates execution status to timeout" do
        timeout_workflow = test_workflow_class_with_timeout.new(input: "test")

        expect {
          timeout_workflow.instrument_workflow { sleep(1); mock_result }
        }.to raise_error(Timeout::Error)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("timeout")
      end
    end

    context "when execution fails with WorkflowCostExceededError" do
      it "updates execution status to error" do
        # WorkflowCostExceededError is in RubyLLM::Agents namespace
        error = RubyLLM::Agents::WorkflowCostExceededError.new(
          "Cost exceeded",
          accumulated_cost: 10.0,
          max_cost: 5.0
        )

        expect {
          workflow.instrument_workflow { raise error }
        }.to raise_error(RubyLLM::Agents::WorkflowCostExceededError)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("RubyLLM::Agents::WorkflowCostExceededError")
      end
    end

    context "when create_workflow_execution fails" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_raise(StandardError, "DB error")
      end

      it "logs error but continues execution" do
        expect(Rails.logger).to receive(:error).with(/Failed to create workflow execution/)

        result = workflow.instrument_workflow { mock_result }

        expect(result).to eq(mock_result)
      end

      it "sets execution_id to nil" do
        workflow.instrument_workflow { mock_result }

        expect(workflow.execution_id).to be_nil
      end
    end

    context "when complete_workflow_execution fails" do
      it "calls mark_workflow_failed! as fallback" do
        execution = RubyLLM::Agents::Execution.create!(
          agent_type: "TestWorkflow",
          agent_version: "1.0.0",
          model_id: "workflow",
          started_at: Time.current,
          status: "running",
          workflow_id: "test-123",
          workflow_type: "workflow"
        )
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(execution)
        allow(execution).to receive(:update!).and_raise(StandardError, "Update failed")

        expect(Rails.logger).to receive(:error).with(/Failed to update workflow execution/)

        workflow.instrument_workflow { mock_result }

        # Check that mark_workflow_failed! updated the status
        execution.reload
        expect(execution.status).to eq("error")
      end
    end
  end

  describe "#build_response_summary" do
    it "includes workflow_type and status" do
      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        workflow_type: "TestWorkflow",
        status: "success"
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:workflow_type]).to eq("TestWorkflow")
      expect(summary[:status]).to eq("success")
    end

    it "includes step summaries for pipeline workflows" do
      step_result = RubyLLM::Agents::TestSupport::MockStepResult.successful(
        total_cost: 0.01,
        duration_ms: 100
      )

      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        status: "success",
        steps: { extract: step_result }
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:steps]).to be_present
      expect(summary[:steps][:extract][:status]).to eq("success")
      expect(summary[:steps][:extract][:total_cost]).to eq(0.01)
      expect(summary[:steps][:extract][:duration_ms]).to eq(100)
    end

    it "includes branch summaries for parallel workflows" do
      branch_result = RubyLLM::Agents::TestSupport::MockStepResult.successful(
        total_cost: 0.02,
        duration_ms: 200
      )

      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        status: "success",
        branches: { sentiment: branch_result }
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:branches]).to be_present
      expect(summary[:branches][:sentiment][:status]).to eq("success")
    end

    it "handles nil branch results" do
      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        status: "partial",
        branches: { failed_branch: nil }
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:branches][:failed_branch][:status]).to eq("error")
    end

    it "includes router information" do
      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        status: "success",
        routed_to: :billing,
        classifier_result: RubyLLM::Agents::TestSupport::MockStepResult.successful(total_cost: 0.001)
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:routed_to]).to eq(:billing)
      expect(summary[:classification_cost]).to eq(0.001)
    end

    it "handles objects without expected methods" do
      step_result = Object.new

      result = RubyLLM::Agents::Workflow::Result.new(
        content: "test",
        status: "success",
        steps: { weird_step: step_result }
      )

      summary = workflow.send(:build_response_summary, result)

      expect(summary[:steps][:weird_step][:status]).to eq("unknown")
      expect(summary[:steps][:weird_step][:total_cost]).to eq(0)
      expect(summary[:steps][:weird_step][:duration_ms]).to be_nil
    end
  end

  describe "#workflow_metadata" do
    it "includes workflow_id and workflow_type" do
      metadata = workflow.send(:workflow_metadata)

      expect(metadata[:workflow_id]).to eq(workflow.workflow_id)
      expect(metadata[:workflow_type]).to eq("workflow")
    end

    context "when execution_metadata is defined" do
      let(:test_workflow_class_with_metadata) do
        Class.new(test_workflow_class) do
          def execution_metadata
            { custom_key: "custom_value" }
          end
        end
      end

      it "merges custom metadata" do
        custom_workflow = test_workflow_class_with_metadata.new(input: "test")
        metadata = custom_workflow.send(:workflow_metadata)

        expect(metadata[:custom_key]).to eq("custom_value")
        expect(metadata[:workflow_id]).to eq(custom_workflow.workflow_id)
      end
    end
  end

  describe "#workflow_type_name" do
    it "returns 'workflow' for base workflow class" do
      expect(workflow.send(:workflow_type_name)).to eq("workflow")
    end
  end

  describe "#mark_workflow_failed!" do
    let(:execution) do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestWorkflow",
        agent_version: "1.0.0",
        model_id: "workflow",
        started_at: Time.current,
        status: "running",
        workflow_id: "test-123",
        workflow_type: "workflow"
      )
    end

    it "updates execution status to error" do
      error = StandardError.new("Test error")
      workflow.send(:mark_workflow_failed!, execution, error: error)

      execution.reload
      expect(execution.status).to eq("error")
      expect(execution.error_class).to eq("StandardError")
      expect(execution.error_message).to eq("Test error")
    end

    it "sets completed_at" do
      travel_to Time.current do
        workflow.send(:mark_workflow_failed!, execution)
        execution.reload
        expect(execution.completed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "handles nil execution" do
      expect { workflow.send(:mark_workflow_failed!, nil) }.not_to raise_error
    end

    it "handles nil error" do
      workflow.send(:mark_workflow_failed!, execution, error: nil)

      execution.reload
      expect(execution.error_class).to eq("UnknownError")
      expect(execution.error_message).to eq("Unknown error")
    end

    it "only updates running executions" do
      execution.update!(status: "success")

      workflow.send(:mark_workflow_failed!, execution, error: StandardError.new("Test"))

      execution.reload
      expect(execution.status).to eq("success") # Unchanged
    end

    it "handles database errors gracefully" do
      allow(execution.class).to receive(:where).and_raise(StandardError, "DB error")
      expect(Rails.logger).to receive(:error).with(/CRITICAL: Failed to mark workflow/)

      expect { workflow.send(:mark_workflow_failed!, execution) }.not_to raise_error
    end
  end
end
