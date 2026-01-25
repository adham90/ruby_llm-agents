# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution::Workflow, type: :model do
  let(:parent_execution) do
    create(:execution, :workflow,
           agent_type: "TestWorkflow",
           workflow_type: "pipeline")
  end

  let(:child_execution_1) do
    create(:execution,
           agent_type: "StepAgent1",
           status: "success",
           parent_execution: parent_execution,
           workflow_step: "step_1",
           input_cost: 0.03,
           output_cost: 0.02,
           total_cost: 0.05,
           total_tokens: 500,
           input_tokens: 300,
           output_tokens: 200,
           duration_ms: 100,
           model_id: "gpt-4",
           started_at: 1.minute.ago,
           completed_at: 30.seconds.ago)
  end

  let(:child_execution_2) do
    create(:execution,
           agent_type: "StepAgent2",
           status: "success",
           parent_execution: parent_execution,
           workflow_step: "step_2",
           input_cost: 0.02,
           output_cost: 0.01,
           total_cost: 0.03,
           total_tokens: 300,
           input_tokens: 200,
           output_tokens: 100,
           duration_ms: 50,
           model_id: "gpt-3.5-turbo",
           started_at: 30.seconds.ago,
           completed_at: Time.current)
  end

  describe "#workflow?" do
    it "returns true when workflow_type is present" do
      expect(parent_execution.workflow?).to be true
    end

    it "returns false when workflow_type is nil" do
      execution = create(:execution, workflow_type: nil)
      expect(execution.workflow?).to be false
    end
  end

  describe "#root_workflow?" do
    it "returns true for workflow with no parent" do
      expect(parent_execution.root_workflow?).to be true
    end

    it "returns false for child workflow" do
      child_workflow = create(:execution, :workflow,
                              agent_type: "ChildWorkflow",
                              workflow_type: "pipeline",
                              parent_execution: parent_execution)
      expect(child_workflow.root_workflow?).to be false
    end

    it "returns false for non-workflow" do
      execution = create(:execution, workflow_type: nil)
      expect(execution.root_workflow?).to be false
    end
  end

  describe "#workflow_steps" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns child executions ordered by creation time" do
      steps = parent_execution.workflow_steps
      expect(steps.count).to eq(2)
      expect(steps.first.workflow_step).to eq("step_1")
    end
  end

  describe "#workflow_steps_count" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns count of child executions" do
      expect(parent_execution.workflow_steps_count).to eq(2)
    end
  end

  describe "#workflow_aggregate_stats" do
    context "with child executions" do
      before do
        child_execution_1
        child_execution_2
      end

      it "returns aggregated statistics" do
        stats = parent_execution.workflow_aggregate_stats

        expect(stats[:total_cost]).to eq(0.08)
        expect(stats[:total_tokens]).to eq(800)
        expect(stats[:input_tokens]).to eq(500)
        expect(stats[:output_tokens]).to eq(300)
        expect(stats[:total_duration_ms]).to eq(150)
        expect(stats[:steps_count]).to eq(2)
        expect(stats[:successful_count]).to eq(2)
        expect(stats[:failed_count]).to eq(0)
        expect(stats[:timeout_count]).to eq(0)
        expect(stats[:running_count]).to eq(0)
        expect(stats[:models_used]).to contain_exactly("gpt-4", "gpt-3.5-turbo")
      end

      it "calculates wall clock duration" do
        stats = parent_execution.workflow_aggregate_stats
        expect(stats[:wall_clock_ms]).to be_present
      end

      it "calculates success rate" do
        stats = parent_execution.workflow_aggregate_stats
        expect(stats[:success_rate]).to eq(100.0)
      end

      it "memoizes the result" do
        stats1 = parent_execution.workflow_aggregate_stats
        stats2 = parent_execution.workflow_aggregate_stats
        expect(stats1).to equal(stats2)
      end
    end

    context "without child executions" do
      it "returns empty aggregate stats" do
        stats = parent_execution.workflow_aggregate_stats

        expect(stats[:total_cost]).to eq(0)
        expect(stats[:total_tokens]).to eq(0)
        expect(stats[:steps_count]).to eq(0)
        expect(stats[:success_rate]).to eq(0.0)
        expect(stats[:models_used]).to eq([])
      end
    end

    context "with mixed status children" do
      before do
        child_execution_1
        create(:execution, :failed,
               agent_type: "FailedAgent",
               parent_execution: parent_execution,
               started_at: Time.current,
               completed_at: Time.current)
        create(:execution, :timeout,
               agent_type: "TimeoutAgent",
               parent_execution: parent_execution,
               started_at: Time.current,
               completed_at: Time.current)
        create(:execution, :running,
               agent_type: "RunningAgent",
               parent_execution: parent_execution,
               started_at: Time.current)
      end

      it "counts each status type" do
        stats = parent_execution.workflow_aggregate_stats

        expect(stats[:successful_count]).to eq(1)
        expect(stats[:failed_count]).to eq(1)
        expect(stats[:timeout_count]).to eq(1)
        expect(stats[:running_count]).to eq(1)
      end

      it "excludes running from success rate calculation" do
        stats = parent_execution.workflow_aggregate_stats
        # 1 success out of 3 completed (excluding 1 running)
        expect(stats[:success_rate]).to be_within(0.1).of(33.3)
      end
    end
  end

  describe "#workflow_total_cost" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns total cost from aggregate stats" do
      expect(parent_execution.workflow_total_cost).to eq(0.08)
    end
  end

  describe "#workflow_total_tokens" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns total tokens from aggregate stats" do
      expect(parent_execution.workflow_total_tokens).to eq(800)
    end
  end

  describe "#workflow_wall_clock_ms" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns wall clock duration from aggregate stats" do
      expect(parent_execution.workflow_wall_clock_ms).to be_present
    end
  end

  describe "#workflow_sum_duration_ms" do
    before do
      child_execution_1
      child_execution_2
    end

    it "returns sum of durations from aggregate stats" do
      expect(parent_execution.workflow_sum_duration_ms).to eq(150)
    end
  end

  describe "#workflow_overall_status" do
    context "with no children" do
      it "returns :pending" do
        expect(parent_execution.workflow_overall_status).to eq(:pending)
      end
    end

    context "with all successful children" do
      before do
        child_execution_1
        child_execution_2
      end

      it "returns :success" do
        expect(parent_execution.workflow_overall_status).to eq(:success)
      end
    end

    context "with running children" do
      before do
        create(:execution, :running,
               agent_type: "RunningAgent",
               parent_execution: parent_execution)
      end

      it "returns :running" do
        expect(parent_execution.workflow_overall_status).to eq(:running)
      end
    end

    context "with failed children" do
      before do
        create(:execution, :failed,
               agent_type: "FailedAgent",
               parent_execution: parent_execution)
      end

      it "returns :error" do
        expect(parent_execution.workflow_overall_status).to eq(:error)
      end
    end

    context "with timeout children" do
      before do
        create(:execution, :timeout,
               agent_type: "TimeoutAgent",
               parent_execution: parent_execution)
      end

      it "returns :timeout" do
        expect(parent_execution.workflow_overall_status).to eq(:timeout)
      end
    end
  end

  describe "private methods" do
    describe "#calculate_wall_clock_duration" do
      context "with started_at and completed_at times" do
        before do
          child_execution_1
          child_execution_2
        end

        it "calculates duration from first start to last complete" do
          # This is tested indirectly through workflow_aggregate_stats
          stats = parent_execution.workflow_aggregate_stats
          expect(stats[:wall_clock_ms]).to be_a(Integer)
          expect(stats[:wall_clock_ms]).to be > 0
        end
      end

      context "with missing completed_at (running execution)" do
        before do
          create(:execution, :running,
                 agent_type: "RunningAgent",
                 parent_execution: parent_execution)
        end

        it "returns nil when completed_at is missing" do
          stats = parent_execution.workflow_aggregate_stats
          expect(stats[:wall_clock_ms]).to be_nil
        end
      end
    end

    describe "#calculate_success_rate" do
      context "with no children" do
        it "returns 0.0" do
          stats = parent_execution.workflow_aggregate_stats
          expect(stats[:success_rate]).to eq(0.0)
        end
      end

      context "with only running children" do
        before do
          create(:execution, :running,
                 agent_type: "RunningAgent",
                 parent_execution: parent_execution)
        end

        it "returns 0.0" do
          stats = parent_execution.workflow_aggregate_stats
          expect(stats[:success_rate]).to eq(0.0)
        end
      end
    end
  end
end
