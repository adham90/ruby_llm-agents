# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navigation tenants link visibility", type: :request do
  let(:engine_root) { RubyLLM::Agents::Engine.routes.url_helpers.root_path }

  context "when multi_tenancy_enabled is false" do
    before do
      allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(false)
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
      allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(true)
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
