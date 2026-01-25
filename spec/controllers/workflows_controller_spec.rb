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
        { name: "TestWorkflow", is_workflow: true, workflow_type: "workflow", active: true },
        { name: "TestWorkflow2", is_workflow: true, workflow_type: "workflow", active: true },
        { name: "TestAgent", is_workflow: false, agent_type: "agent", active: true }
      ])
    end

    it "returns http success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "assigns @workflows with only workflows" do
      get :index
      expect(assigns(:workflows).size).to eq(2)
      expect(assigns(:workflows).all? { |w| w[:is_workflow] }).to be true
    end

    it "assigns @sort_params with defaults" do
      get :index
      expect(assigns(:sort_params)).to eq({ column: "name", direction: "asc" })
    end

    context "with sorting parameters" do
      before do
        allow(RubyLLM::Agents::AgentRegistry).to receive(:all_with_details).and_return([
          { name: "ZWorkflow", is_workflow: true, execution_count: 10, total_cost: 0.5 },
          { name: "AWorkflow", is_workflow: true, execution_count: 5, total_cost: 1.0 }
        ])
      end

      it "sorts by name ascending by default" do
        get :index
        expect(assigns(:workflows).first[:name]).to eq("AWorkflow")
      end

      it "sorts by name descending" do
        get :index, params: { sort: "name", direction: "desc" }
        expect(assigns(:workflows).first[:name]).to eq("ZWorkflow")
      end

      it "sorts by execution_count" do
        get :index, params: { sort: "execution_count", direction: "desc" }
        expect(assigns(:workflows).first[:execution_count]).to eq(10)
      end

      it "sorts by total_cost" do
        get :index, params: { sort: "total_cost", direction: "desc" }
        expect(assigns(:workflows).first[:total_cost]).to eq(1.0)
      end

      it "ignores invalid sort columns" do
        get :index, params: { sort: "invalid_column", direction: "asc" }
        expect(assigns(:sort_params)[:column]).to eq("name")
      end

      it "ignores invalid sort directions" do
        get :index, params: { sort: "name", direction: "invalid" }
        expect(assigns(:sort_params)[:direction]).to eq("asc")
      end
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::Agents::AgentRegistry).to receive(:all_with_details)
          .and_raise(StandardError.new("Test error"))
      end

      it "sets empty array and flash alert" do
        get :index
        expect(assigns(:workflows)).to eq([])
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
      let!(:workflow_execution) do
        create(:execution,
          agent_type: "TestDSLWorkflow",
          workflow_type: "workflow"
        )
      end

      it "detects workflow type" do
        get :show, params: { id: "TestDSLWorkflow" }
        expect(assigns(:workflow_type_kind)).to eq("workflow")
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
