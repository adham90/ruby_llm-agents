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

  describe "#pipeline_workflow?" do
    it "returns true when workflow_type is pipeline" do
      expect(parent_execution.pipeline_workflow?).to be true
    end

    it "returns false when workflow_type is different" do
      execution = create(:execution, :workflow, workflow_type: "parallel")
      expect(execution.pipeline_workflow?).to be false
    end
  end

  describe "#parallel_workflow?" do
    it "returns true when workflow_type is parallel" do
      execution = create(:execution, :workflow, workflow_type: "parallel")
      expect(execution.parallel_workflow?).to be true
    end

    it "returns false when workflow_type is pipeline" do
      expect(parent_execution.parallel_workflow?).to be false
    end
  end

  describe "#router_workflow?" do
    it "returns true when workflow_type is router" do
      execution = create(:execution, :workflow, workflow_type: "router")
      expect(execution.router_workflow?).to be true
    end

    it "returns false when workflow_type is pipeline" do
      expect(parent_execution.router_workflow?).to be false
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

  describe "#pipeline_steps_detail" do
    context "for pipeline workflow" do
      before do
        child_execution_1
        child_execution_2
      end

      it "returns detailed step information" do
        details = parent_execution.pipeline_steps_detail

        expect(details.length).to eq(2)
        expect(details.first[:name]).to eq("step_1")
        expect(details.first[:agent_type]).to eq("StepAgent1")
        expect(details.first[:status]).to eq("success")
        expect(details.first[:duration_ms]).to eq(100)
        expect(details.first[:total_cost]).to eq(0.05)
        expect(details.first[:model_id]).to eq("gpt-4")
      end
    end

    context "for non-pipeline workflow" do
      it "returns empty array" do
        parallel_workflow = create(:execution, :workflow,
                                   agent_type: "ParallelWorkflow",
                                   workflow_type: "parallel")
        expect(parallel_workflow.pipeline_steps_detail).to eq([])
      end
    end

    context "with missing workflow_step" do
      before do
        create(:execution,
               agent_type: "SomeAgent",
               parent_execution: parent_execution,
               workflow_step: nil)
      end

      it "falls back to agent_type without Agent suffix" do
        details = parent_execution.pipeline_steps_detail
        expect(details.first[:name]).to eq("Some")
      end
    end
  end

  describe "#parallel_branches_detail" do
    let(:parallel_workflow) do
      create(:execution, :workflow,
             agent_type: "ParallelWorkflow",
             workflow_type: "parallel")
    end

    context "for parallel workflow" do
      before do
        create(:execution,
               agent_type: "FastAgent",
               parent_execution: parallel_workflow,
               workflow_step: "branch_fast",
               duration_ms: 50,
               total_cost: 0.02,
               started_at: Time.current,
               completed_at: Time.current)
        create(:execution,
               agent_type: "SlowAgent",
               parent_execution: parallel_workflow,
               workflow_step: "branch_slow",
               duration_ms: 200,
               total_cost: 0.05,
               started_at: Time.current,
               completed_at: Time.current)
      end

      it "returns detailed branch information" do
        details = parallel_workflow.parallel_branches_detail

        expect(details.length).to eq(2)
      end

      it "marks fastest and slowest branches" do
        details = parallel_workflow.parallel_branches_detail
        fast_branch = details.find { |d| d[:name] == "branch_fast" }
        slow_branch = details.find { |d| d[:name] == "branch_slow" }

        expect(fast_branch[:is_fastest]).to be true
        expect(fast_branch[:is_slowest]).to be false
        expect(slow_branch[:is_fastest]).to be false
        expect(slow_branch[:is_slowest]).to be true
      end
    end

    context "for non-parallel workflow" do
      it "returns empty array" do
        expect(parent_execution.parallel_branches_detail).to eq([])
      end
    end

    context "with no branches" do
      it "returns empty array" do
        expect(parallel_workflow.parallel_branches_detail).to eq([])
      end
    end

    context "with single branch" do
      before do
        create(:execution,
               agent_type: "OnlyAgent",
               parent_execution: parallel_workflow,
               duration_ms: 100)
      end

      it "does not mark is_fastest or is_slowest for single branch" do
        details = parallel_workflow.parallel_branches_detail
        expect(details.first[:is_fastest]).to be false
        expect(details.first[:is_slowest]).to be false
      end
    end

    context "with equal duration branches" do
      before do
        create(:execution,
               agent_type: "Agent1",
               parent_execution: parallel_workflow,
               duration_ms: 100)
        create(:execution,
               agent_type: "Agent2",
               parent_execution: parallel_workflow,
               duration_ms: 100)
      end

      it "does not mark is_slowest when all durations are equal" do
        details = parallel_workflow.parallel_branches_detail
        slowest_count = details.count { |d| d[:is_slowest] }
        expect(slowest_count).to eq(0)
      end
    end
  end

  describe "#router_classification_detail" do
    let(:router_workflow) do
      create(:execution, :workflow,
             agent_type: "RouterWorkflow",
             workflow_type: "router",
             routed_to: "SupportAgent",
             classification_result: {
               "method" => "llm",
               "classifier_model" => "gpt-4",
               "classification_time_ms" => 150,
               "confidence" => 0.95
             }.to_json)
    end

    context "for router workflow" do
      it "returns classification details" do
        details = router_workflow.router_classification_detail

        expect(details[:method]).to eq("llm")
        expect(details[:classifier_model]).to eq("gpt-4")
        expect(details[:classification_time_ms]).to eq(150)
        expect(details[:routed_to]).to eq("SupportAgent")
        expect(details[:confidence]).to eq(0.95)
      end
    end

    context "for non-router workflow" do
      it "returns empty hash" do
        expect(parent_execution.router_classification_detail).to eq({})
      end
    end

    context "with invalid JSON classification_result" do
      let(:invalid_router) do
        create(:execution, :workflow,
               agent_type: "RouterWorkflow",
               workflow_type: "router",
               classification_result: "invalid json{")
      end

      it "handles parse error gracefully" do
        details = invalid_router.router_classification_detail
        expect(details[:method]).to be_nil
      end
    end

    context "with hash classification_result" do
      let(:hash_router) do
        execution = create(:execution, :workflow,
                           agent_type: "RouterWorkflow",
                           workflow_type: "router")
        # Simulate hash stored in classification_result
        execution.update_column(:classification_result, { "method" => "keyword" }.to_json)
        execution.reload
        execution
      end

      it "handles hash result" do
        details = hash_router.router_classification_detail
        expect(details[:method]).to eq("keyword")
      end
    end

    context "with nil classification_result" do
      let(:nil_router) do
        create(:execution, :workflow,
               agent_type: "RouterWorkflow",
               workflow_type: "router",
               classification_result: nil)
      end

      it "handles nil gracefully" do
        details = nil_router.router_classification_detail
        expect(details[:method]).to be_nil
      end
    end
  end

  describe "#router_routes_detail" do
    let(:router_workflow) do
      create(:execution, :workflow,
             agent_type: "RouterWorkflow",
             workflow_type: "router",
             routed_to: "SupportAgent")
    end

    context "for router workflow with routed execution" do
      before do
        create(:execution,
               agent_type: "SupportAgent",
               parent_execution: router_workflow,
               duration_ms: 250,
               input_cost: 0.05,
               output_cost: 0.03,
               total_cost: 0.08)
      end

      it "returns route details" do
        details = router_workflow.router_routes_detail

        expect(details[:chosen_route]).to eq("SupportAgent")
        expect(details[:routed_execution]).to be_present
        expect(details[:routed_execution][:agent_type]).to eq("SupportAgent")
        expect(details[:routed_execution][:status]).to eq("success")
        expect(details[:routed_execution][:duration_ms]).to eq(250)
        expect(details[:routed_execution][:total_cost]).to eq(0.08)
      end
    end

    context "for router workflow without routed execution" do
      it "returns nil for routed_execution" do
        details = router_workflow.router_routes_detail

        expect(details[:chosen_route]).to eq("SupportAgent")
        expect(details[:routed_execution]).to be_nil
      end
    end

    context "for non-router workflow" do
      it "returns empty hash" do
        expect(parent_execution.router_routes_detail).to eq({})
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
