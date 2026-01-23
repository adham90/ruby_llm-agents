# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::WorkflowsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  # Define custom render to capture assigns without needing templates
  controller do
    def index
      super
      head :ok unless performed?
    end

    def show
      super
      head :ok unless performed?
    end
  end

  describe "GET #index" do
    before do
      # Mock AgentRegistry to return test workflows
      allow(RubyLLM::Agents::AgentRegistry).to receive(:all_with_details).and_return([
        { name: "TestPipeline", is_workflow: true, workflow_type: "pipeline", active: true },
        { name: "TestParallel", is_workflow: true, workflow_type: "parallel", active: true },
        { name: "TestRouter", is_workflow: true, workflow_type: "router", active: true },
        { name: "TestAgent", is_workflow: false, agent_type: "agent", active: true }
      ])
    end

    it "returns http success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "assigns @workflows with only workflows" do
      get :index
      expect(assigns(:workflows).size).to eq(3)
      expect(assigns(:workflows).all? { |w| w[:is_workflow] }).to be true
    end

    it "assigns @workflows_by_type" do
      get :index
      workflows_by_type = assigns(:workflows_by_type)
      expect(workflows_by_type[:pipeline].size).to eq(1)
      expect(workflows_by_type[:parallel].size).to eq(1)
      expect(workflows_by_type[:router].size).to eq(1)
    end

    it "assigns @workflow_count" do
      get :index
      expect(assigns(:workflow_count)).to eq(3)
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::Agents::AgentRegistry).to receive(:all_with_details)
          .and_raise(StandardError.new("Test error"))
      end

      it "sets empty arrays and flash alert" do
        get :index
        expect(assigns(:workflows)).to eq([])
        expect(assigns(:workflows_by_type)).to eq({ pipeline: [], parallel: [], router: [] })
        expect(assigns(:workflow_count)).to eq(0)
        expect(flash[:alert]).to eq("Error loading workflows list")
      end
    end
  end

  describe "GET #show" do
    let!(:execution) do
      create(:execution,
        agent_type: "TestPipelineWorkflow",
        workflow_type: "pipeline",
        status: "success"
      )
    end

    it "returns http success" do
      get :show, params: { id: "TestPipelineWorkflow" }
      expect(response).to have_http_status(:success)
    end

    it "assigns @workflow_type" do
      get :show, params: { id: "TestPipelineWorkflow" }
      expect(assigns(:workflow_type)).to eq("TestPipelineWorkflow")
    end

    it "assigns @workflow_type_kind from execution history" do
      get :show, params: { id: "TestPipelineWorkflow" }
      expect(assigns(:workflow_type_kind)).to eq("pipeline")
    end

    it "assigns @stats" do
      get :show, params: { id: "TestPipelineWorkflow" }
      expect(assigns(:stats)).to be_a(Hash)
    end

    it "assigns @executions" do
      get :show, params: { id: "TestPipelineWorkflow" }
      expect(assigns(:executions)).to be_present
    end

    context "with different workflow types" do
      let!(:parallel_execution) do
        create(:execution,
          agent_type: "TestParallelWorkflow",
          workflow_type: "parallel"
        )
      end

      let!(:router_execution) do
        create(:execution,
          agent_type: "TestRouterWorkflow",
          workflow_type: "router",
          routed_to: "billing"
        )
      end

      it "detects parallel workflow type" do
        get :show, params: { id: "TestParallelWorkflow" }
        expect(assigns(:workflow_type_kind)).to eq("parallel")
      end

      it "detects router workflow type" do
        get :show, params: { id: "TestRouterWorkflow" }
        expect(assigns(:workflow_type_kind)).to eq("router")
      end
    end

    context "with child executions (step stats)" do
      let!(:parent_execution) do
        create(:execution,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline",
          status: "success"
        )
      end

      let!(:child_execution) do
        create(:execution,
          agent_type: "ExtractAgent",
          workflow_step: "extract",
          parent_execution: parent_execution,
          status: "success",
          duration_ms: 500,
          total_cost: 0.01,
          total_tokens: 100
        )
      end

      it "calculates step stats from child executions" do
        get :show, params: { id: "TestPipelineWorkflow" }
        expect(assigns(:step_stats)).to be_an(Array)
      end
    end

    context "with route distribution (router)" do
      before do
        create(:execution,
          agent_type: "TestRouterWorkflow",
          workflow_type: "router",
          routed_to: "billing",
          status: "success"
        )
        create(:execution,
          agent_type: "TestRouterWorkflow",
          workflow_type: "router",
          routed_to: "billing",
          status: "success"
        )
        create(:execution,
          agent_type: "TestRouterWorkflow",
          workflow_type: "router",
          routed_to: "technical",
          status: "success"
        )
      end

      it "calculates route distribution for router workflows" do
        get :show, params: { id: "TestRouterWorkflow" }
        expect(assigns(:route_distribution)).to be_a(Hash)
        expect(assigns(:route_distribution).keys).to include("billing")
      end
    end

    context "with status filter" do
      before do
        create(:execution,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline",
          status: "success"
        )
        create(:execution,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline",
          status: "error"
        )
      end

      it "filters by valid status" do
        get :show, params: { id: "TestPipelineWorkflow", statuses: "success" }
        expect(assigns(:executions).pluck(:status).uniq).to eq(["success"])
      end
    end

    context "with days filter" do
      before do
        create(:execution,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline",
          created_at: Time.current
        )
        create(:execution,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline",
          created_at: 10.days.ago
        )
      end

      it "filters by positive days" do
        get :show, params: { id: "TestPipelineWorkflow", days: "7" }
        # 2 recent executions: 1 from let! + 1 from before block
        expect(assigns(:executions).count).to eq(2)
      end
    end

    context "with pagination" do
      before do
        create_list(:execution, 30,
          agent_type: "TestPipelineWorkflow",
          workflow_type: "pipeline"
        )
      end

      it "paginates results" do
        get :show, params: { id: "TestPipelineWorkflow" }
        expect(assigns(:executions).count).to eq(25)
        expect(assigns(:pagination)[:total_pages]).to eq(2)
      end

      it "handles page parameter" do
        get :show, params: { id: "TestPipelineWorkflow", page: "2" }
        expect(assigns(:pagination)[:current_page]).to eq(2)
      end
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:stats_for)
          .and_raise(StandardError.new("Test error"))
      end

      it "redirects with error message" do
        get :show, params: { id: "TestPipelineWorkflow" }
        expect(response).to redirect_to(controller.ruby_llm_agents.workflows_path)
        expect(flash[:alert]).to eq("Error loading workflow details")
      end
    end
  end
end
