# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM::Agents convenience API" do
  describe ".executions" do
    it "returns an ActiveRecord::Relation" do
      expect(RubyLLM::Agents.executions).to be_a(ActiveRecord::Relation)
    end

    it "supports chaining scopes" do
      expect(RubyLLM::Agents.executions.successful.today).to be_a(ActiveRecord::Relation)
    end
  end

  describe ".usage" do
    before do
      create(:execution, status: "success")
      create(:execution, :failed)
    end

    it "returns a summary hash" do
      result = RubyLLM::Agents.usage(period: :today)

      expect(result).to include(
        executions: 2,
        successful: 1,
        failed: 1
      )
      expect(result[:success_rate]).to eq(50.0)
      expect(result[:total_cost]).to be > 0
      expect(result[:total_tokens]).to be > 0
    end

    it "filters by agent" do
      create(:execution, agent_type: "SpecialAgent", status: "success")

      result = RubyLLM::Agents.usage(period: :today, agent: "SpecialAgent")
      expect(result[:executions]).to eq(1)
    end

    it "filters by tenant" do
      create(:execution, tenant_id: "tenant-1", status: "success", total_cost: 0.10, total_tokens: 200)
      create(:execution, tenant_id: "tenant-2", status: "success", total_cost: 0.20, total_tokens: 400)

      result = RubyLLM::Agents.usage(period: :today, tenant: "tenant-1")
      expect(result[:executions]).to eq(1)
    end

    it "supports :this_month period" do
      result = RubyLLM::Agents.usage(period: :this_month)
      expect(result[:executions]).to eq(2)
    end

    it "supports Range period" do
      result = RubyLLM::Agents.usage(period: 1.hour.ago..Time.current)
      expect(result[:executions]).to eq(2)
    end

    it "returns zero rates when no executions" do
      RubyLLM::Agents::Execution.delete_all
      result = RubyLLM::Agents.usage(period: :today)

      expect(result[:executions]).to eq(0)
      expect(result[:success_rate]).to eq(0.0)
      expect(result[:avg_cost]).to eq(0)
    end
  end

  describe ".costs" do
    before do
      create(:execution, agent_type: "AgentA", total_cost: 0.05)
      create(:execution, agent_type: "AgentA", total_cost: 0.10)
      create(:execution, agent_type: "AgentB", total_cost: 0.20)
    end

    it "returns cost breakdown by agent" do
      result = RubyLLM::Agents.costs(period: :today)

      expect(result).to have_key("AgentA")
      expect(result).to have_key("AgentB")
      expect(result["AgentA"][:count]).to eq(2)
      expect(result["AgentB"][:count]).to eq(1)
    end

    it "filters by tenant" do
      create(:execution, agent_type: "AgentC", tenant_id: "t1", total_cost: 0.50)
      result = RubyLLM::Agents.costs(period: :today, tenant: "t1")

      expect(result).to have_key("AgentC")
      expect(result.keys).to eq(["AgentC"])
    end
  end

  describe ".agents" do
    it "returns an array" do
      expect(RubyLLM::Agents.agents).to be_an(Array)
    end
  end

  describe ".tenant_for" do
    it "returns a Tenant record for a string ID" do
      RubyLLM::Agents::Tenant.create!(tenant_id: "test-tenant")
      tenant = RubyLLM::Agents.tenant_for("test-tenant")

      expect(tenant).to be_a(RubyLLM::Agents::Tenant)
      expect(tenant.tenant_id).to eq("test-tenant")
    end

    it "returns nil for unknown tenant" do
      expect(RubyLLM::Agents.tenant_for("nonexistent")).to be_nil
    end
  end
end
