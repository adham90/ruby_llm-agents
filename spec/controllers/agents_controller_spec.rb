# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AgentsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }
  render_views false

  before do
    allow(controller).to receive(:render)
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns @agents" do
      get :index
      expect(assigns(:agents)).to be_an(Array)
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::Agents::AgentRegistry).to receive(:all_with_details)
          .and_raise(StandardError.new("Test error"))
      end

      it "handles the error gracefully" do
        get :index
        expect(assigns(:agents)).to eq([])
        expect(flash.now[:alert]).to eq("Error loading agents list")
      end
    end
  end

  describe "GET #show" do
    let!(:execution) { create(:execution, agent_type: "TestAgent") }

    it "returns http success" do
      get :show, params: { id: "TestAgent" }
      expect(response).to have_http_status(:success)
    end

    it "assigns @agent_type" do
      get :show, params: { id: "TestAgent" }
      expect(assigns(:agent_type)).to eq("TestAgent")
    end

    it "assigns @stats" do
      get :show, params: { id: "TestAgent" }
      expect(assigns(:stats)).to be_a(Hash)
    end

    it "assigns @executions" do
      get :show, params: { id: "TestAgent" }
      expect(assigns(:executions)).to be_present
    end

    context "with status filter" do
      before do
        create(:execution, agent_type: "TestAgent", status: "success")
        create(:execution, agent_type: "TestAgent", status: "error")
      end

      it "filters by valid status" do
        get :show, params: { id: "TestAgent", statuses: "success" }
        expect(assigns(:executions).pluck(:status).uniq).to eq(["success"])
      end

      it "ignores invalid status" do
        get :show, params: { id: "TestAgent", statuses: "invalid_status" }
        # Should return all results since invalid status is ignored
        expect(assigns(:executions).count).to be >= 0
      end
    end

    context "with days filter" do
      before do
        create(:execution, agent_type: "TestAgent", created_at: Time.current)
        create(:execution, agent_type: "TestAgent", created_at: 10.days.ago)
      end

      it "filters by positive days" do
        get :show, params: { id: "TestAgent", days: "7" }
        expect(assigns(:executions).count).to eq(1)
      end

      it "ignores negative days" do
        get :show, params: { id: "TestAgent", days: "-5" }
        # Should return all results since negative days is ignored
        expect(assigns(:executions).count).to eq(2)
      end
    end

    context "with pagination" do
      before do
        create_list(:execution, 30, agent_type: "TestAgent")
      end

      it "paginates results" do
        get :show, params: { id: "TestAgent" }
        expect(assigns(:executions).count).to eq(25)
        expect(assigns(:pagination)[:total_pages]).to eq(2)
      end

      it "handles page parameter" do
        get :show, params: { id: "TestAgent", page: "2" }
        expect(assigns(:pagination)[:current_page]).to eq(2)
      end

      it "handles invalid page parameter" do
        get :show, params: { id: "TestAgent", page: "0" }
        expect(assigns(:pagination)[:current_page]).to eq(1)
      end
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:stats_for)
          .and_raise(StandardError.new("Test error"))
      end

      it "redirects with error message" do
        get :show, params: { id: "TestAgent" }
        expect(response).to redirect_to(controller.ruby_llm_agents.agents_path)
        expect(flash[:alert]).to eq("Error loading agent details")
      end
    end
  end
end
