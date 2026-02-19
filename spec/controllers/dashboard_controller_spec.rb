# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DashboardController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  # Define custom render to capture assigns without needing templates
  controller do
    def index
      super
      head :ok
    end
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns @now_strip" do
      get :index
      expect(assigns(:now_strip)).to be_a(Hash)
    end

    it "assigns @recent_executions" do
      create_list(:execution, 3)
      get :index
      expect(assigns(:recent_executions)).to be_present
    end

    it "assigns @agent_stats" do
      get :index
      expect(assigns(:agent_stats)).to be_an(Array)
    end

    it "assigns @critical_alerts" do
      get :index
      expect(assigns(:critical_alerts)).to be_an(Array)
    end

    it "assigns @model_stats" do
      get :index
      expect(assigns(:model_stats)).to be_an(Array)
    end

    describe "@cache_savings" do
      it "returns zeros when no executions exist" do
        get :index
        savings = assigns(:cache_savings)
        expect(savings).to be_a(Hash)
        expect(savings[:count]).to eq(0)
        expect(savings[:estimated_savings]).to eq(0)
        expect(savings[:hit_rate]).to eq(0)
        expect(savings[:total_executions]).to eq(0)
      end

      it "correctly counts cached executions and computes hit rate" do
        create_list(:execution, 3)
        create_list(:execution, 2, :cached)
        get :index
        savings = assigns(:cache_savings)
        expect(savings[:count]).to eq(2)
        expect(savings[:total_executions]).to eq(5)
        expect(savings[:hit_rate]).to eq(40.0)
      end

      it "sums total_cost of cached executions as estimated savings" do
        e1 = create(:execution, cache_hit: true)
        e1.update_column(:total_cost, 0.05)
        e2 = create(:execution, cache_hit: true)
        e2.update_column(:total_cost, 0.10)
        create(:execution)
        get :index
        savings = assigns(:cache_savings)
        expect(savings[:estimated_savings].to_f).to be_within(0.001).of(0.15)
      end
    end

    describe "@top_tenants" do
      it "is nil when no tenants have activity" do
        get :index
        expect(assigns(:top_tenants)).to be_nil
      end

      it "returns sorted tenants with budget data when tenants exist" do
        RubyLLM::Agents::Tenant.create!(
          tenant_id: "tenant_a", name: "Tenant A",
          monthly_cost_spent: 50.0, monthly_executions_count: 100,
          daily_reset_date: Date.current, monthly_reset_date: Date.current.beginning_of_month
        )
        RubyLLM::Agents::Tenant.create!(
          tenant_id: "tenant_b", name: "Tenant B",
          monthly_cost_spent: 150.0, monthly_executions_count: 200,
          daily_reset_date: Date.current, monthly_reset_date: Date.current.beginning_of_month
        )
        get :index
        tenants = assigns(:top_tenants)
        expect(tenants).to be_an(Array)
        expect(tenants.length).to eq(2)
        expect(tenants.first[:name]).to eq("Tenant B") # sorted by monthly_cost_spent desc
      end

      it "is limited to 5 entries" do
        6.times do |i|
          RubyLLM::Agents::Tenant.create!(
            tenant_id: "tenant_#{i}", name: "Tenant #{i}",
            monthly_cost_spent: (i + 1) * 10.0, monthly_executions_count: 1,
            daily_reset_date: Date.current, monthly_reset_date: Date.current.beginning_of_month
          )
        end
        get :index
        tenants = assigns(:top_tenants)
        expect(tenants.length).to eq(5)
      end
    end
  end
end
