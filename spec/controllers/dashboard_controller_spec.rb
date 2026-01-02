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
  end
end
