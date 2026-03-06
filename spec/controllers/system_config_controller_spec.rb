# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SystemConfigController", type: :request do
  let(:engine_root) { RubyLLM::Agents::Engine.routes.url_helpers }

  describe "GET /system_config" do
    it "returns http success" do
      get engine_root.system_config_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the system config page" do
      get engine_root.system_config_path
      expect(response.body).to include("configuration")
    end
  end
end
