# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Agents::RequestsController, type: :request do
  let(:engine_routes) { RubyLLM::Agents::Engine.routes }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
    end
  end

  describe "GET #index" do
    it "renders successfully with no requests" do
      get engine_routes.url_helpers.requests_path
      expect(response).to have_http_status(:ok)
    end

    it "lists requests grouped by request_id" do
      create(:execution, request_id: "req_001", agent_type: "AgentA")
      create(:execution, request_id: "req_001", agent_type: "AgentB")
      create(:execution, request_id: "req_002", agent_type: "AgentC")

      get engine_routes.url_helpers.requests_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("req_001")
      expect(response.body).to include("req_002")
    end

    it "excludes executions without request_id" do
      create(:execution, request_id: nil)
      create(:execution, request_id: "req_with_id")

      get engine_routes.url_helpers.requests_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("req_with_id")
    end

    it "supports sorting by cost" do
      create(:execution, request_id: "cheap_req", total_cost: 0.001)
      create(:execution, request_id: "expensive_req", total_cost: 1.0)

      get engine_routes.url_helpers.requests_path, params: {sort: "total_cost", direction: "desc"}
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET #show" do
    it "shows a request detail page" do
      create(:execution, request_id: "req_abc", agent_type: "AgentA")
      create(:execution, request_id: "req_abc", agent_type: "AgentB")

      get engine_routes.url_helpers.request_path("req_abc")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("req_abc")
      expect(response.body).to include("AgentA")
      expect(response.body).to include("AgentB")
    end

    it "shows summary statistics" do
      create(:execution, request_id: "req_stats", total_cost: 0.005, total_tokens: 100)
      create(:execution, request_id: "req_stats", total_cost: 0.010, total_tokens: 200)

      get engine_routes.url_helpers.request_path("req_stats")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("300") # total tokens
    end

    it "redirects when request_id not found" do
      get engine_routes.url_helpers.request_path("nonexistent_req")
      expect(response).to redirect_to(engine_routes.url_helpers.requests_path)
    end

    it "shows error status when executions have errors" do
      create(:execution, request_id: "req_err", status: "success")
      create(:execution, :failed, request_id: "req_err")

      get engine_routes.url_helpers.request_path("req_err")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("error")
    end
  end
end
