# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ExecutionsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  # Define custom render to capture assigns without needing templates
  controller do
    def index
      super
      head :ok
    end

    def show
      super
      head :ok
    end

    def search
      super
      head :ok
    end
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns @agent_types" do
      create(:execution, agent_type: "AgentA")
      create(:execution, agent_type: "AgentB")
      get :index
      expect(assigns(:agent_types)).to include("AgentA", "AgentB")
    end

    it "assigns @statuses" do
      get :index
      expect(assigns(:statuses)).to include("running", "success", "error", "timeout")
    end

    it "assigns @executions" do
      create_list(:execution, 3)
      get :index
      expect(assigns(:executions).count).to eq(3)
    end

    it "assigns @pagination" do
      get :index
      expect(assigns(:pagination)).to include(:current_page, :per_page, :total_count, :total_pages)
    end

    it "assigns @filter_stats" do
      get :index
      expect(assigns(:filter_stats)).to include(:total_count, :total_cost, :total_tokens)
    end

    context "with agent_types filter" do
      before do
        create(:execution, agent_type: "AgentA")
        create(:execution, agent_type: "AgentB")
      end

      it "filters by single agent type" do
        get :index, params: { agent_types: "AgentA" }
        expect(assigns(:executions).pluck(:agent_type).uniq).to eq(["AgentA"])
      end

      it "filters by multiple agent types" do
        get :index, params: { agent_types: "AgentA,AgentB" }
        expect(assigns(:executions).count).to eq(2)
      end
    end

    context "with status filter" do
      before do
        create(:execution, status: "success")
        create(:execution, :failed)
      end

      it "filters by valid status" do
        get :index, params: { statuses: "success" }
        expect(assigns(:executions).pluck(:status).uniq).to eq(["success"])
      end

      it "ignores invalid status values" do
        get :index, params: { statuses: "invalid" }
        # Invalid statuses are ignored, so returns all results
        expect(assigns(:executions).count).to eq(2)
      end
    end

    context "with days filter" do
      before do
        create(:execution, created_at: Time.current)
        create(:execution, created_at: 10.days.ago)
      end

      it "filters by days" do
        get :index, params: { days: "7" }
        expect(assigns(:executions).count).to eq(1)
      end

      it "ignores negative days" do
        get :index, params: { days: "-1" }
        expect(assigns(:executions).count).to eq(2)
      end

      it "ignores zero days" do
        get :index, params: { days: "0" }
        expect(assigns(:executions).count).to eq(2)
      end
    end

    context "with pagination" do
      before { create_list(:execution, 30) }

      it "defaults to page 1" do
        get :index
        expect(assigns(:pagination)[:current_page]).to eq(1)
      end

      it "returns configured per_page count" do
        get :index
        expect(assigns(:executions).count).to eq(RubyLLM::Agents.configuration.per_page)
      end

      it "handles page 2" do
        get :index, params: { page: "2" }
        expect(assigns(:pagination)[:current_page]).to eq(2)
      end

      it "handles invalid page (converts to 1)" do
        get :index, params: { page: "-1" }
        expect(assigns(:pagination)[:current_page]).to eq(1)
      end
    end

    context "with sorting" do
      before do
        create(:execution, agent_type: "AgentA", duration_ms: 1000, created_at: 1.day.ago)
        create(:execution, agent_type: "AgentB", duration_ms: 500, created_at: 2.days.ago)
        create(:execution, agent_type: "AgentC", duration_ms: 2000, created_at: Time.current)
      end

      it "assigns @sort_params" do
        get :index
        expect(assigns(:sort_params)).to include(:column, :direction)
      end

      it "defaults to created_at desc" do
        get :index
        expect(assigns(:sort_params)[:column]).to eq("created_at")
        expect(assigns(:sort_params)[:direction]).to eq("desc")
        # Most recent execution should be first
        expect(assigns(:executions).first.agent_type).to eq("AgentC")
      end

      it "sorts by specified column ascending" do
        get :index, params: { sort: "duration_ms", direction: "asc" }
        expect(assigns(:sort_params)[:column]).to eq("duration_ms")
        expect(assigns(:sort_params)[:direction]).to eq("asc")
        # Shortest duration should be first
        expect(assigns(:executions).first.duration_ms).to eq(500)
      end

      it "sorts by specified column descending" do
        get :index, params: { sort: "duration_ms", direction: "desc" }
        expect(assigns(:sort_params)[:column]).to eq("duration_ms")
        expect(assigns(:sort_params)[:direction]).to eq("desc")
        # Longest duration should be first
        expect(assigns(:executions).first.duration_ms).to eq(2000)
      end

      it "sorts by agent_type" do
        get :index, params: { sort: "agent_type", direction: "asc" }
        expect(assigns(:executions).pluck(:agent_type)).to eq(%w[AgentA AgentB AgentC])
      end

      it "falls back to default for invalid sort column" do
        get :index, params: { sort: "invalid_column" }
        expect(assigns(:sort_params)[:column]).to eq("created_at")
      end

      it "falls back to default for invalid direction" do
        get :index, params: { sort: "duration_ms", direction: "invalid" }
        expect(assigns(:sort_params)[:direction]).to eq("desc")
      end

      it "rejects SQL injection attempts" do
        get :index, params: { sort: "duration_ms; DROP TABLE executions" }
        expect(assigns(:sort_params)[:column]).to eq("created_at")
      end
    end

  end

  describe "GET #show" do
    let(:execution) { create(:execution) }

    it "assigns @execution" do
      get :show, params: { id: execution.id }
      expect(assigns(:execution)).to eq(execution)
    end

    it "raises error for non-existent execution" do
      expect {
        get :show, params: { id: 999999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "with tool calls" do
      let(:execution_with_tools) { create(:execution, :with_tool_calls) }

      it "makes tool_calls accessible" do
        get :show, params: { id: execution_with_tools.id }
        expect(assigns(:execution).tool_calls).to be_an(Array)
        expect(assigns(:execution).tool_calls.size).to eq(2)
      end

      it "includes tool call structure with id, name, and arguments" do
        get :show, params: { id: execution_with_tools.id }
        tool_call = assigns(:execution).tool_calls.first
        expect(tool_call).to include("id", "name", "arguments")
      end

      it "returns empty array when execution has no tool calls" do
        get :show, params: { id: execution.id }
        expect(assigns(:execution).tool_calls).to eq([])
      end

      it "handles execution with many tool calls" do
        execution_many = create(:execution, :with_many_tool_calls)
        get :show, params: { id: execution_many.id }
        expect(assigns(:execution).tool_calls.size).to eq(5)
      end

      it "handles tool calls with symbol keys" do
        execution_symbols = create(:execution, :with_symbol_key_tool_calls)
        get :show, params: { id: execution_symbols.id }
        expect(assigns(:execution).tool_calls).to be_present
      end
    end
  end

end
