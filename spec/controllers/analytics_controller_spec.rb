# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AnalyticsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  controller do
    def index
      super
      head :ok
    end

    def chart_data
      super
    end
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns @summary with expected keys" do
      get :index
      summary = assigns(:summary)
      expect(summary).to be_a(Hash)
      expect(summary).to include(:total_cost, :total_runs, :avg_cost, :cost_change, :prior_cost)
    end

    it "assigns filter options" do
      create(:execution, agent_type: "TestAgent", model_id: "gpt-4o")
      get :index
      expect(assigns(:available_agents)).to include("TestAgent")
      expect(assigns(:available_models)).to include("gpt-4o")
    end

    it "assigns efficiency data" do
      create(:execution, model_id: "gpt-4o", total_cost: 0.05)
      get :index
      expect(assigns(:efficiency)).to be_an(Array)
    end

    it "assigns error breakdown" do
      get :index
      expect(assigns(:error_breakdown)).to be_an(Array)
    end

    it "defaults to 30d range" do
      get :index
      expect(assigns(:selected_range)).to eq("30d")
    end

    it "accepts valid ranges" do
      %w[7d 30d 90d].each do |range|
        get :index, params: {range: range}
        expect(assigns(:selected_range)).to eq(range)
      end
    end

    it "rejects invalid range" do
      get :index, params: {range: "invalid"}
      expect(assigns(:selected_range)).to eq("30d")
    end

    it "supports custom date range" do
      get :index, params: {range: "custom", from: 7.days.ago.to_date.to_s, to: Date.current.to_s}
      expect(assigns(:selected_range)).to eq("custom")
      expect(assigns(:custom_from)).to be_present
    end

    context "with filters" do
      before do
        create(:execution, agent_type: "AgentA", model_id: "gpt-4o", total_cost: 0.10)
        create(:execution, agent_type: "AgentB", model_id: "gpt-4o-mini", total_cost: 0.01)
      end

      it "filters by agent" do
        get :index, params: {agent: "AgentA"}
        expect(assigns(:filter_agent)).to eq("AgentA")
        expect(assigns(:summary)[:total_runs]).to eq(1)
      end

      it "filters by model" do
        get :index, params: {model: "gpt-4o-mini"}
        expect(assigns(:filter_model)).to eq("gpt-4o-mini")
        expect(assigns(:summary)[:total_runs]).to eq(1)
      end

      it "combines filters" do
        get :index, params: {agent: "AgentA", model: "gpt-4o"}
        expect(assigns(:summary)[:total_runs]).to eq(1)
      end

      it "returns zero for non-matching filter" do
        get :index, params: {agent: "NonExistent"}
        expect(assigns(:summary)[:total_runs]).to eq(0)
      end
    end

    context "projection" do
      it "calculates projection when data exists" do
        create(:execution, total_cost: 0.50, created_at: 2.days.ago)
        get :index, params: {range: "7d"}
        projection = assigns(:projection)
        expect(projection).to be_present
        expect(projection[:daily_rate]).to be > 0
        expect(projection[:projected_month]).to be > 0
      end

      it "returns nil projection when no cost" do
        get :index
        expect(assigns(:projection)).to be_nil
      end
    end

    context "savings opportunity" do
      it "identifies savings when multiple models used" do
        create(:execution, model_id: "gpt-4o", total_cost: 0.50, total_tokens: 1000)
        create(:execution, model_id: "gpt-4o-mini", total_cost: 0.01, total_tokens: 1000)
        get :index
        savings = assigns(:savings)
        if savings
          expect(savings[:expensive_model]).to eq("gpt-4o")
          expect(savings[:potential_savings]).to be > 0
        end
      end

      it "returns nil savings with single model" do
        create(:execution, model_id: "gpt-4o", total_cost: 0.10)
        get :index
        expect(assigns(:savings)).to be_nil
      end
    end
  end

  describe "GET analytics/chart_data", type: :request do
    include RubyLLM::Agents::Engine.routes.url_helpers

    it "returns JSON with series" do
      get analytics_chart_data_path(range: "30d")
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["series"]).to be_an(Array)
      expect(data["series"].size).to eq(2)
      expect(data["series"][0]["name"]).to eq("Current period")
      expect(data["series"][1]["name"]).to eq("Prior period")
    end

    it "passes filters to chart data" do
      create(:execution, agent_type: "AgentA", total_cost: 0.10, created_at: 2.days.ago)
      create(:execution, agent_type: "AgentB", total_cost: 0.50, created_at: 2.days.ago)
      get analytics_chart_data_path(range: "7d", agent: "AgentA")
      data = JSON.parse(response.body)
      # Should only have AgentA data
      total = data["series"][0]["data"].sum { |d| d[1] }
      expect(total).to be <= 0.11
    end
  end
end
