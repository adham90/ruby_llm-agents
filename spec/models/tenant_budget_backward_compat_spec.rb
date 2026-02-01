# frozen_string_literal: true

require "rails_helper"

# Backward compatibility tests for TenantBudget -> Tenant migration
# Ensures existing code using TenantBudget continues to work
RSpec.describe "TenantBudget backward compatibility", type: :model do
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenants)
      skip "Tenant table not available - run migration first"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
  end

  describe "RubyLLM::Agents::TenantBudget" do
    subject { RubyLLM::Agents::TenantBudget }

    it "is the same class as Tenant" do
      expect(subject).to eq(RubyLLM::Agents::Tenant)
    end

    it "uses the same table as Tenant" do
      expect(subject.table_name).to eq("ruby_llm_agents_tenants")
    end

    it "can create records" do
      budget = subject.create!(tenant_id: "compat_test_1", name: "Compat Test")
      expect(budget).to be_persisted
      expect(budget).to be_a(RubyLLM::Agents::Tenant)
    end

    it "shares records with Tenant" do
      tenant = RubyLLM::Agents::Tenant.create!(tenant_id: "shared_test", name: "Shared")
      budget = subject.find_by(tenant_id: "shared_test")
      expect(budget).to eq(tenant)
    end
  end

  describe ".for_tenant (backward compatible method)" do
    let!(:existing) { RubyLLM::Agents::TenantBudget.create!(tenant_id: "for_tenant_test") }

    it "finds tenant by string tenant_id" do
      found = RubyLLM::Agents::TenantBudget.for_tenant("for_tenant_test")
      expect(found).to eq(existing)
    end

    it "returns nil for non-existent tenant" do
      expect(RubyLLM::Agents::TenantBudget.for_tenant("unknown")).to be_nil
    end

    it "works the same as Tenant.for" do
      expect(RubyLLM::Agents::TenantBudget.for_tenant("for_tenant_test")).to eq(
        RubyLLM::Agents::Tenant.for("for_tenant_test")
      )
    end
  end

  describe ".for_tenant! (backward compatible method)" do
    it "creates new budget if not exists" do
      budget = RubyLLM::Agents::TenantBudget.for_tenant!("new_compat", name: "New Compat")
      expect(budget).to be_persisted
      expect(budget.name).to eq("New Compat")
    end

    it "returns existing budget if exists" do
      existing = RubyLLM::Agents::TenantBudget.create!(tenant_id: "existing_compat")
      found = RubyLLM::Agents::TenantBudget.for_tenant!("existing_compat")
      expect(found).to eq(existing)
    end

    it "works the same as Tenant.for!" do
      budget1 = RubyLLM::Agents::TenantBudget.for_tenant!("same_method_test")
      budget2 = RubyLLM::Agents::Tenant.for!("same_method_test")
      expect(budget1).to eq(budget2)
    end
  end

  describe "Budgetable concern methods" do
    let(:budget) do
      RubyLLM::Agents::TenantBudget.create!(
        tenant_id: "budgetable_test",
        daily_limit: 100.0,
        monthly_limit: 1000.0,
        enforcement: "hard"
      )
    end

    it "has effective_daily_limit" do
      expect(budget.effective_daily_limit).to eq(100.0)
    end

    it "has effective_monthly_limit" do
      expect(budget.effective_monthly_limit).to eq(1000.0)
    end

    it "has effective_enforcement" do
      expect(budget.effective_enforcement).to eq(:hard)
    end

    it "has budgets_enabled?" do
      expect(budget.budgets_enabled?).to be true
    end

    it "has hard_enforcement?" do
      expect(budget.hard_enforcement?).to be true
    end

    it "has to_budget_config" do
      config = budget.to_budget_config
      expect(config[:enabled]).to be true
      expect(config[:global_daily]).to eq(100.0)
    end
  end

  describe "Trackable concern methods" do
    let(:tenant) { RubyLLM::Agents::TenantBudget.create!(tenant_id: "trackable_test") }

    before do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_cost: 0.50,
        total_tokens: 1000,
        tenant_id: tenant.tenant_id
      )
      tenant.refresh_counters!
    end

    it "has cost method" do
      expect(tenant.cost).to eq(0.50)
    end

    it "has cost_today method" do
      expect(tenant.cost_today).to eq(0.50)
    end

    it "has tokens method" do
      expect(tenant.tokens).to eq(1000)
    end

    it "has tokens_today method" do
      expect(tenant.tokens_today).to eq(1000)
    end

    it "has execution_count method" do
      expect(tenant.execution_count).to eq(1)
    end

    it "has usage_summary method" do
      summary = tenant.usage_summary
      expect(summary[:cost]).to eq(0.50)
      expect(summary[:tokens]).to eq(1000)
      expect(summary[:executions]).to eq(1)
    end
  end

  describe "instance methods" do
    let(:budget) { RubyLLM::Agents::TenantBudget.create!(tenant_id: "instance_test", name: "Test") }

    it "has display_name" do
      expect(budget.display_name).to eq("Test")
    end

    it "has linked?" do
      expect(budget.linked?).to be false
    end

    it "has active?" do
      expect(budget.active?).to be true
    end

    it "has deactivate!" do
      budget.deactivate!
      expect(budget.reload.active?).to be false
    end

    it "has activate!" do
      budget.update!(active: false)
      budget.activate!
      expect(budget.reload.active?).to be true
    end
  end

  describe "associations" do
    it "has tenant_record polymorphic association" do
      association = RubyLLM::Agents::TenantBudget.reflect_on_association(:tenant_record)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:polymorphic]).to be true
    end

    it "has executions association" do
      association = RubyLLM::Agents::TenantBudget.reflect_on_association(:executions)
      expect(association.macro).to eq(:has_many)
    end
  end

  describe "scopes" do
    before do
      RubyLLM::Agents::TenantBudget.create!(tenant_id: "active_scope", active: true)
      RubyLLM::Agents::TenantBudget.create!(tenant_id: "inactive_scope", active: false)
    end

    it "has active scope" do
      expect(RubyLLM::Agents::TenantBudget.active.pluck(:tenant_id)).to include("active_scope")
      expect(RubyLLM::Agents::TenantBudget.active.pluck(:tenant_id)).not_to include("inactive_scope")
    end

    it "has inactive scope" do
      expect(RubyLLM::Agents::TenantBudget.inactive.pluck(:tenant_id)).to include("inactive_scope")
    end
  end

  describe "ENFORCEMENT_MODES constant" do
    it "is accessible via TenantBudget" do
      expect(RubyLLM::Agents::TenantBudget::ENFORCEMENT_MODES).to eq(%w[none soft hard])
    end
  end
end
