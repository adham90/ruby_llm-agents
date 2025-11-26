# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DashboardController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }
  render_views false

  describe "GET #index" do
    before do
      # Stub view rendering to avoid template not found errors
      allow(controller).to receive(:render)
    end

    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns @stats" do
      get :index
      expect(assigns(:stats)).to be_a(Hash)
      expect(assigns(:stats)).to include(
        :total_executions,
        :successful,
        :failed,
        :total_cost,
        :total_tokens,
        :avg_duration_ms,
        :success_rate
      )
    end

    it "assigns @recent_executions" do
      create_list(:execution, 3)
      get :index
      expect(assigns(:recent_executions)).to be_present
    end

    it "assigns @hourly_activity" do
      get :index
      expect(assigns(:hourly_activity)).to be_an(Array)
      expect(assigns(:hourly_activity).size).to eq(2)
      expect(assigns(:hourly_activity).first[:name]).to eq("Success")
    end

    context "with executions today" do
      before do
        create(:execution, status: "success")
        create(:execution, status: "success")
        create(:execution, :failed)
      end

      it "calculates correct stats" do
        get :index
        stats = assigns(:stats)
        expect(stats[:total_executions]).to eq(3)
        expect(stats[:successful]).to eq(2)
        expect(stats[:failed]).to eq(1)
      end

      it "calculates success rate" do
        get :index
        stats = assigns(:stats)
        expect(stats[:success_rate]).to be_within(0.1).of(66.7)
      end
    end

    context "caching" do
      it "caches daily stats" do
        expect(Rails.cache).to receive(:fetch)
          .with(/ruby_llm_agents\/daily_stats/, expires_in: 1.minute)
          .and_call_original

        get :index
      end
    end
  end
end
