# frozen_string_literal: true

require "rails_helper"

# Request specs (type: :request) exercise the real respond_to block,
# unlike the existing controller specs which override actions with `head :ok`.
# Since turbo-rails is NOT in the test Gemfile, these tests directly
# reproduce the NoMethodError from Issue #11.
RSpec.describe "Executions without turbo-rails", type: :request do
  let(:url_helpers) { RubyLLM::Agents::Engine.routes.url_helpers }

  before do
    create(:execution, agent_type: "TestAgent", status: "success")
  end

  describe "GET /executions" do
    it "responds successfully with HTML" do
      get url_helpers.executions_path

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "handles turbo_stream Accept header gracefully" do
      get url_helpers.executions_path, headers: {"Accept" => "text/vnd.turbo-stream.html, text/html"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "GET /executions/search" do
    it "responds successfully with HTML" do
      get url_helpers.search_executions_path

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "handles turbo_stream Accept header gracefully" do
      get url_helpers.search_executions_path, headers: {"Accept" => "text/vnd.turbo-stream.html, text/html"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
