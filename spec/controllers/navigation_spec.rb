# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navigation tenants link visibility", type: :request do
  let(:engine_root) { RubyLLM::Agents::Engine.routes.url_helpers.root_path }

  after do
    RubyLLM::Agents.reset_configuration!
  end

  context "when multi_tenancy_enabled is false" do
    before do
      RubyLLM::Agents.configure { |c| c.multi_tenancy_enabled = false }
      get engine_root
    end

    it "does not show the tenants link" do
      expect(response.body).not_to include(">tenants</a>")
    end

    it "shows dashboard, agents, and executions links" do
      expect(response.body).to include(">dashboard</a>")
      expect(response.body).to include(">agents</a>")
      expect(response.body).to include(">executions</a>")
    end
  end

  context "when multi_tenancy_enabled is true" do
    before do
      RubyLLM::Agents.configure { |c| c.multi_tenancy_enabled = true }
      get engine_root
    end

    it "shows the tenants link" do
      expect(response.body).to include(">tenants</a>")
    end

    it "shows all navigation links" do
      expect(response.body).to include(">dashboard</a>")
      expect(response.body).to include(">agents</a>")
      expect(response.body).to include(">executions</a>")
      expect(response.body).to include(">tenants</a>")
    end
  end
end
