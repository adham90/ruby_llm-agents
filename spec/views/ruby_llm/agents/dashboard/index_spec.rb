# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ruby_llm/agents/dashboard/index", type: :view do
  helper RubyLLM::Agents::ApplicationHelper

  before do
    assign(:selected_range, "today")
    assign(:now_strip, {success_today: 10, errors_today: 1, cost_today: 0.50})
    assign(:critical_alerts, [])
    assign(:recent_executions, RubyLLM::Agents::Execution.none)
    assign(:agent_stats, [])
    assign(:embedder_stats, [])
    assign(:transcriber_stats, [])
    assign(:speaker_stats, [])
    assign(:image_generator_stats, [])
    assign(:top_errors, [])
    assign(:tenant_budget, nil)
    assign(:model_stats, [])
    assign(:cache_savings, {count: 0, estimated_savings: 0, hit_rate: 0, total_executions: 0})
    assign(:top_tenants, nil)

    without_partial_double_verification do
      allow(view).to receive(:ruby_llm_agents).and_return(RubyLLM::Agents::Engine.routes.url_helpers)
    end
    allow(view).to receive(:controller_name).and_return("dashboard")
    allow(view).to receive(:action_name).and_return("index")
  end

  describe "chart containers" do
    it "renders chart container divs" do
      render

      expect(rendered).to include('id="activity-chart"')
      expect(rendered).to include('id="cost-over-time-chart"')
      expect(rendered).to include('id="tokens-over-time-chart"')
      expect(rendered).to include('id="cost-by-agent-chart"')
      expect(rendered).to include('id="cost-by-model-chart"')
    end

    it "renders breakdown chart containers" do
      render
      expect(rendered).to include('id="cost-by-agent-chart"')
      expect(rendered).to include('id="cost-by-model-chart"')
    end
  end

  describe "cache savings strip" do
    context "when cache savings count is zero" do
      it "does not render the cache savings strip" do
        render
        expect(rendered).not_to include("cache hits")
      end
    end

    context "when cache savings count is positive" do
      before do
        assign(:cache_savings, {count: 42, estimated_savings: 3.24, hit_rate: 15.6, total_executions: 269})
      end

      it "renders cache hit count" do
        render
        expect(rendered).to include("42")
        expect(rendered).to include("cache hits")
      end

      it "renders estimated savings" do
        render
        expect(rendered).to include("$3.24")
        expect(rendered).to include("saved")
      end

      it "renders hit rate" do
        render
        expect(rendered).to include("15.6%")
        expect(rendered).to include("hit rate")
      end
    end
  end

  describe "top tenants section" do
    context "when top_tenants is nil" do
      it "does not render the tenants section" do
        render
        # The tenants partial links to the tenants index; this link only
        # appears when top_tenants data is present
        expect(rendered).not_to include("/tenants")
      end
    end

    context "when top_tenants has data" do
      before do
        assign(:top_tenants, [
          {id: 1, tenant_id: "acme", name: "Acme Corp", enforcement: :soft,
           monthly_spend: 150.0, monthly_limit: 500.0, monthly_percentage: 30.0,
           daily_spend: 10.0, daily_limit: 50.0, daily_percentage: 20.0,
           monthly_executions: 200}
        ])
      end

      it "renders the tenants section" do
        render
        expect(rendered).to include("Acme Corp")
      end

      it "renders monthly spend" do
        render
        expect(rendered).to include("$150.00")
      end

      it "renders execution count" do
        render
        expect(rendered).to include("200")
      end
    end
  end
end
