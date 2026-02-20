# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM::Agents.rename_agent" do
  describe "argument validation" do
    it "raises when names are the same" do
      expect {
        RubyLLM::Agents.rename_agent("Same", to: "Same")
      }.to raise_error(ArgumentError, /different/)
    end

    it "raises when old_name is blank" do
      expect {
        RubyLLM::Agents.rename_agent("", to: "NewName")
      }.to raise_error(ArgumentError, /blank/)
    end

    it "raises when new name is blank" do
      expect {
        RubyLLM::Agents.rename_agent("OldName", to: "")
      }.to raise_error(ArgumentError, /blank/)
    end
  end

  describe "dry_run mode" do
    it "returns affected counts without modifying data" do
      create(:execution, agent_type: "OldAgent")
      create(:execution, agent_type: "OldAgent")
      create(:execution, agent_type: "OtherAgent")

      result = RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent", dry_run: true)

      expect(result).to eq(executions_affected: 2, tenants_affected: 0)
      # Data unchanged
      expect(RubyLLM::Agents::Execution.where(agent_type: "OldAgent").count).to eq(2)
      expect(RubyLLM::Agents::Execution.where(agent_type: "NewAgent").count).to eq(0)
    end
  end

  describe "execution renaming" do
    it "updates matching executions" do
      create(:execution, agent_type: "OldAgent")
      create(:execution, agent_type: "OldAgent")
      unrelated = create(:execution, agent_type: "OtherAgent")

      result = RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent")

      expect(result[:executions_updated]).to eq(2)
      expect(RubyLLM::Agents::Execution.where(agent_type: "OldAgent").count).to eq(0)
      expect(RubyLLM::Agents::Execution.where(agent_type: "NewAgent").count).to eq(2)
      expect(unrelated.reload.agent_type).to eq("OtherAgent")
    end

    it "returns zero when no executions match" do
      result = RubyLLM::Agents.rename_agent("NonExistent", to: "NewName")
      expect(result[:executions_updated]).to eq(0)
    end
  end

  describe "tenant budget key renaming" do
    it "updates per_agent_daily keys" do
      tenant = RubyLLM::Agents::Tenant.create!(
        tenant_id: "test_tenant",
        per_agent_daily: {"OldAgent" => 10.0, "OtherAgent" => 5.0},
        per_agent_monthly: {}
      )

      result = RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent")

      expect(result[:tenants_updated]).to eq(1)
      tenant.reload
      expect(tenant.per_agent_daily).to eq("NewAgent" => 10.0, "OtherAgent" => 5.0)
    end

    it "updates per_agent_monthly keys" do
      tenant = RubyLLM::Agents::Tenant.create!(
        tenant_id: "test_tenant",
        per_agent_daily: {},
        per_agent_monthly: {"OldAgent" => 100.0}
      )

      RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent")

      tenant.reload
      expect(tenant.per_agent_monthly).to eq("NewAgent" => 100.0)
    end

    it "skips tenants without matching keys" do
      RubyLLM::Agents::Tenant.create!(
        tenant_id: "unrelated_tenant",
        per_agent_daily: {"OtherAgent" => 5.0},
        per_agent_monthly: {}
      )

      result = RubyLLM::Agents.rename_agent("OldAgent", to: "NewAgent")
      expect(result[:tenants_updated]).to eq(0)
    end
  end
end
