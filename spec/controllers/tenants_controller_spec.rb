# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::TenantsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  controller do
    def index
      super
      head :ok
    end

    def show
      super
      head :ok
    end

    def edit
      super
      head :ok
    end

    def update
      super
    rescue ActionController::RoutingError
      head :ok
    end
  end

  let!(:tenant) do
    create(:tenant_budget,
      tenant_id: "acme-corp",
      name: "Acme Corp",
      enforcement: "soft",
      daily_limit: 50.0,
      monthly_limit: 500.0)
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns tenants" do
      get :index
      expect(assigns(:tenants)).to include(tenant)
    end

    it "filters by search query" do
      create(:tenant_budget, tenant_id: "other-org", name: "Other Org")
      get :index, params: {q: "acme"}
      expect(assigns(:tenants)).to include(tenant)
      expect(assigns(:tenants).count).to eq(1)
    end

    it "sorts by column" do
      create(:tenant_budget, tenant_id: "zzz-org", name: "ZZZ Org")
      get :index, params: {sort: "name", direction: "desc"}
      expect(assigns(:tenants).first.name).to eq("ZZZ Org")
    end

    it "ignores invalid sort columns" do
      get :index, params: {sort: "DROP TABLE", direction: "asc"}
      expect(assigns(:sort_params)[:column]).to eq("name")
    end
  end

  describe "GET #show" do
    it "returns http success" do
      get :show, params: {id: tenant.id}
      expect(response).to have_http_status(:ok)
    end

    it "assigns the tenant" do
      get :show, params: {id: tenant.id}
      expect(assigns(:tenant)).to eq(tenant)
    end

    it "assigns usage stats" do
      get :show, params: {id: tenant.id}
      expect(assigns(:usage_stats)).to be_a(Hash)
      expect(assigns(:usage_stats)).to include(:daily_spend, :monthly_spend, :total_executions)
    end
  end

  describe "GET #edit" do
    it "returns http success" do
      get :edit, params: {id: tenant.id}
      expect(response).to have_http_status(:ok)
    end

    it "assigns the tenant" do
      get :edit, params: {id: tenant.id}
      expect(assigns(:tenant)).to eq(tenant)
    end
  end

  describe "PATCH #update" do
    it "updates budget limits" do
      patch :update, params: {
        id: tenant.id,
        tenant_budget: {daily_limit: 100.0, monthly_limit: 1000.0}
      }
      tenant.reload
      expect(tenant.daily_limit).to eq(100.0)
      expect(tenant.monthly_limit).to eq(1000.0)
    end

    it "updates enforcement mode" do
      patch :update, params: {
        id: tenant.id,
        tenant_budget: {enforcement: "hard"}
      }
      tenant.reload
      expect(tenant.enforcement).to eq("hard")
    end
  end
end
