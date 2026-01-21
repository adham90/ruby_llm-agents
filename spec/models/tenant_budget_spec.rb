# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::TenantBudget, type: :model do
  # Skip all tests if the table doesn't exist (migration not run)
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
      skip "TenantBudget table not available - run migration first"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
  end

  describe "validations" do
    it "requires tenant_id" do
      budget = described_class.new(tenant_id: nil)
      expect(budget).not_to be_valid
      expect(budget.errors[:tenant_id]).to include("can't be blank")
    end

    it "requires unique tenant_id" do
      described_class.create!(tenant_id: "tenant_1")
      duplicate = described_class.new(tenant_id: "tenant_1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:tenant_id]).to include("has already been taken")
    end

    it "validates enforcement mode" do
      budget = described_class.new(tenant_id: "test", enforcement: "invalid")
      expect(budget).not_to be_valid
      expect(budget.errors[:enforcement]).to be_present
    end

    it "accepts valid enforcement modes" do
      %w[none soft hard].each do |mode|
        budget = described_class.new(tenant_id: "test_#{mode}", enforcement: mode)
        expect(budget).to be_valid
      end
    end

    it "validates daily_limit is non-negative" do
      budget = described_class.new(tenant_id: "test", daily_limit: -10)
      expect(budget).not_to be_valid
    end

    it "validates monthly_limit is non-negative" do
      budget = described_class.new(tenant_id: "test", monthly_limit: -10)
      expect(budget).not_to be_valid
    end

    it "validates daily_token_limit is non-negative integer" do
      budget = described_class.new(tenant_id: "test", daily_token_limit: -10)
      expect(budget).not_to be_valid
    end

    it "validates monthly_token_limit is non-negative integer" do
      budget = described_class.new(tenant_id: "test", monthly_token_limit: -10)
      expect(budget).not_to be_valid
    end

    it "validates daily_execution_limit is non-negative integer" do
      budget = described_class.new(tenant_id: "test", daily_execution_limit: -10)
      expect(budget).not_to be_valid
    end

    it "validates monthly_execution_limit is non-negative integer" do
      budget = described_class.new(tenant_id: "test", monthly_execution_limit: -10)
      expect(budget).not_to be_valid
    end
  end

  describe ".for_tenant" do
    it "returns budget for existing tenant" do
      created = described_class.create!(tenant_id: "my_tenant", daily_limit: 50.0)
      found = described_class.for_tenant("my_tenant")
      expect(found).to eq(created)
    end

    it "returns nil for non-existent tenant" do
      expect(described_class.for_tenant("unknown")).to be_nil
    end

    it "returns nil for blank tenant_id" do
      expect(described_class.for_tenant("")).to be_nil
      expect(described_class.for_tenant(nil)).to be_nil
    end

    context "with object that responds to llm_tenant_id" do
      let(:tenant_object) do
        obj = Object.new
        def obj.llm_tenant_id
          "object_tenant_123"
        end
        obj
      end

      it "finds by tenant_id when no polymorphic match exists" do
        created = described_class.create!(tenant_id: "object_tenant_123", daily_limit: 75.0)
        found = described_class.for_tenant(tenant_object)
        expect(found).to eq(created)
      end

      it "returns nil when no budget exists for tenant object" do
        expect(described_class.for_tenant(tenant_object)).to be_nil
      end

      it "prefers polymorphic association over tenant_id when both exist" do
        # Create budget with polymorphic association
        poly_budget = described_class.create!(
          tenant_id: "poly_tenant_123",
          tenant_record_type: "TestTenant",
          tenant_record_id: 999,
          daily_limit: 100.0
        )

        # Create a mock tenant record object
        tenant_record = Object.new
        tenant_record.define_singleton_method(:llm_tenant_id) { "poly_tenant_123" }

        # Stub find_by to return poly_budget when queried with tenant_record
        allow(described_class).to receive(:find_by).with(tenant_record: tenant_record).and_return(poly_budget)
        # Let the actual find_by pass through for tenant_id query
        allow(described_class).to receive(:find_by).with(tenant_id: "poly_tenant_123").and_call_original

        found = described_class.for_tenant(tenant_record)
        expect(found).to eq(poly_budget)
      end
    end
  end

  describe ".for_tenant!" do
    it "creates a new budget if one does not exist" do
      budget = described_class.for_tenant!("new_tenant", name: "New Tenant Corp")
      expect(budget).to be_persisted
      expect(budget.tenant_id).to eq("new_tenant")
      expect(budget.name).to eq("New Tenant Corp")
    end

    it "returns existing budget if one exists" do
      existing = described_class.create!(tenant_id: "existing_tenant", daily_limit: 100.0)
      found = described_class.for_tenant!("existing_tenant", name: "Should Not Update")
      expect(found).to eq(existing)
      expect(found.name).to be_nil # Name wasn't set on create, and find_or_create_by doesn't update
    end

    it "creates budget without name if not provided" do
      budget = described_class.for_tenant!("nameless_tenant")
      expect(budget).to be_persisted
      expect(budget.name).to be_nil
    end
  end

  describe "#display_name" do
    it "returns name when present" do
      budget = described_class.new(tenant_id: "acme", name: "Acme Corporation")
      expect(budget.display_name).to eq("Acme Corporation")
    end

    it "returns tenant_id when name is blank" do
      budget = described_class.new(tenant_id: "acme", name: nil)
      expect(budget.display_name).to eq("acme")
    end

    it "returns tenant_id when name is empty string" do
      budget = described_class.new(tenant_id: "acme", name: "")
      expect(budget.display_name).to eq("acme")
    end

    it "returns tenant_id when name is whitespace" do
      budget = described_class.new(tenant_id: "acme", name: "   ")
      expect(budget.display_name).to eq("acme")
    end
  end

  describe "#effective_daily_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(daily_limit: 50.0)
        expect(budget.effective_daily_limit).to eq(50.0)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily: 25.0 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(daily_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_daily_limit).to eq(25.0)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(daily_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_daily_limit).to be_nil
      end
    end
  end

  describe "#effective_monthly_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(monthly_limit: 500.0)
        expect(budget.effective_monthly_limit).to eq(500.0)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_monthly: 250.0 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(monthly_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_monthly_limit).to eq(250.0)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(monthly_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_monthly_limit).to be_nil
      end
    end
  end

  describe "#effective_daily_token_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(daily_token_limit: 1_000_000)
        expect(budget.effective_daily_token_limit).to eq(1_000_000)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily_tokens: 500_000 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(daily_token_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_daily_token_limit).to eq(500_000)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(daily_token_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_daily_token_limit).to be_nil
      end
    end
  end

  describe "#effective_monthly_token_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(monthly_token_limit: 10_000_000)
        expect(budget.effective_monthly_token_limit).to eq(10_000_000)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_monthly_tokens: 5_000_000 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(monthly_token_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_monthly_token_limit).to eq(5_000_000)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(monthly_token_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_monthly_token_limit).to be_nil
      end
    end
  end

  describe "#effective_daily_execution_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(daily_execution_limit: 500)
        expect(budget.effective_daily_execution_limit).to eq(500)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily_executions: 250 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(daily_execution_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_daily_execution_limit).to eq(250)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(daily_execution_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_daily_execution_limit).to be_nil
      end
    end
  end

  describe "#effective_monthly_execution_limit" do
    context "when limit is set" do
      it "returns the set limit" do
        budget = described_class.new(monthly_execution_limit: 10_000)
        expect(budget.effective_monthly_execution_limit).to eq(10_000)
      end
    end

    context "when inherit_global_defaults is true and limit is not set" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_monthly_executions: 5_000 }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(monthly_execution_limit: nil, inherit_global_defaults: true)
        expect(budget.effective_monthly_execution_limit).to eq(5_000)
      end
    end

    context "when inherit_global_defaults is false and limit is not set" do
      it "returns nil" do
        budget = described_class.new(monthly_execution_limit: nil, inherit_global_defaults: false)
        expect(budget.effective_monthly_execution_limit).to be_nil
      end
    end
  end

  describe "#effective_per_agent_daily" do
    it "returns tenant-specific limit when set" do
      budget = described_class.new(per_agent_daily: { "TestAgent" => 10.0 })
      expect(budget.effective_per_agent_daily("TestAgent")).to eq(10.0)
    end

    it "returns nil for unconfigured agent" do
      budget = described_class.new(per_agent_daily: {})
      expect(budget.effective_per_agent_daily("UnknownAgent")).to be_nil
    end

    it "returns nil when per_agent_daily is nil" do
      budget = described_class.new(per_agent_daily: nil, inherit_global_defaults: false)
      expect(budget.effective_per_agent_daily("TestAgent")).to be_nil
    end

    context "with inherit_global_defaults true" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { per_agent_daily: { "GlobalAgent" => 15.0 } }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(per_agent_daily: {}, inherit_global_defaults: true)
        expect(budget.effective_per_agent_daily("GlobalAgent")).to eq(15.0)
      end

      it "prefers tenant-specific over global" do
        budget = described_class.new(
          per_agent_daily: { "GlobalAgent" => 5.0 },
          inherit_global_defaults: true
        )
        expect(budget.effective_per_agent_daily("GlobalAgent")).to eq(5.0)
      end
    end
  end

  describe "#effective_per_agent_monthly" do
    it "returns tenant-specific limit when set" do
      budget = described_class.new(per_agent_monthly: { "TestAgent" => 100.0 })
      expect(budget.effective_per_agent_monthly("TestAgent")).to eq(100.0)
    end

    it "returns nil for unconfigured agent" do
      budget = described_class.new(per_agent_monthly: {})
      expect(budget.effective_per_agent_monthly("UnknownAgent")).to be_nil
    end

    it "returns nil when per_agent_monthly is nil" do
      budget = described_class.new(per_agent_monthly: nil, inherit_global_defaults: false)
      expect(budget.effective_per_agent_monthly("TestAgent")).to be_nil
    end

    context "with inherit_global_defaults false" do
      it "returns nil for unconfigured agent without inheritance" do
        budget = described_class.new(per_agent_monthly: {}, inherit_global_defaults: false)
        expect(budget.effective_per_agent_monthly("UnknownAgent")).to be_nil
      end
    end

    context "with inherit_global_defaults true" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { per_agent_monthly: { "GlobalAgent" => 150.0 } }
        end
      end

      it "falls back to global config" do
        budget = described_class.new(per_agent_monthly: {}, inherit_global_defaults: true)
        expect(budget.effective_per_agent_monthly("GlobalAgent")).to eq(150.0)
      end

      it "prefers tenant-specific over global" do
        budget = described_class.new(
          per_agent_monthly: { "GlobalAgent" => 50.0 },
          inherit_global_defaults: true
        )
        expect(budget.effective_per_agent_monthly("GlobalAgent")).to eq(50.0)
      end
    end
  end

  describe "#effective_enforcement" do
    it "returns enforcement when set" do
      budget = described_class.new(enforcement: "hard")
      expect(budget.effective_enforcement).to eq(:hard)
    end

    it "returns :soft when enforcement is set to soft" do
      budget = described_class.new(enforcement: "soft")
      expect(budget.effective_enforcement).to eq(:soft)
    end

    it "returns :none when enforcement is set to none" do
      budget = described_class.new(enforcement: "none")
      expect(budget.effective_enforcement).to eq(:none)
    end

    context "when enforcement is not set" do
      it "returns :soft when inherit_global_defaults is false" do
        budget = described_class.new(enforcement: nil, inherit_global_defaults: false)
        expect(budget.effective_enforcement).to eq(:soft)
      end

      it "falls back to global config when inherit_global_defaults is true" do
        RubyLLM::Agents.configure do |config|
          config.budgets = { enforcement: :hard }
        end

        budget = described_class.new(enforcement: nil, inherit_global_defaults: true)
        expect(budget.effective_enforcement).to eq(:hard)
      end

      it "uses global default :none when inherit_global_defaults is true" do
        RubyLLM::Agents.configure do |config|
          config.budgets = { enforcement: :none }
        end

        budget = described_class.new(enforcement: nil, inherit_global_defaults: true)
        expect(budget.effective_enforcement).to eq(:none)
      end
    end
  end

  describe "#budgets_enabled?" do
    it "returns true for soft enforcement" do
      budget = described_class.new(enforcement: "soft")
      expect(budget.budgets_enabled?).to be true
    end

    it "returns true for hard enforcement" do
      budget = described_class.new(enforcement: "hard")
      expect(budget.budgets_enabled?).to be true
    end

    it "returns false for none enforcement" do
      budget = described_class.new(enforcement: "none")
      expect(budget.budgets_enabled?).to be false
    end
  end

  describe "#to_budget_config" do
    it "returns a hash suitable for BudgetTracker" do
      budget = described_class.new(
        daily_limit: 50.0,
        monthly_limit: 500.0,
        daily_token_limit: 1_000_000,
        monthly_token_limit: 10_000_000,
        daily_execution_limit: 500,
        monthly_execution_limit: 10_000,
        per_agent_daily: { "AgentA" => 10.0 },
        per_agent_monthly: { "AgentA" => 100.0 },
        enforcement: "hard"
      )

      config = budget.to_budget_config

      expect(config[:enabled]).to be true
      expect(config[:enforcement]).to eq(:hard)
      # Cost limits
      expect(config[:global_daily]).to eq(50.0)
      expect(config[:global_monthly]).to eq(500.0)
      expect(config[:per_agent_daily]).to include("AgentA" => 10.0)
      expect(config[:per_agent_monthly]).to include("AgentA" => 100.0)
      # Token limits
      expect(config[:global_daily_tokens]).to eq(1_000_000)
      expect(config[:global_monthly_tokens]).to eq(10_000_000)
      # Execution limits
      expect(config[:global_daily_executions]).to eq(500)
      expect(config[:global_monthly_executions]).to eq(10_000)
    end

    it "returns enabled false for none enforcement" do
      budget = described_class.new(enforcement: "none")
      config = budget.to_budget_config
      expect(config[:enabled]).to be false
    end

    it "returns empty per_agent hashes when not set and no inheritance" do
      budget = described_class.new(
        per_agent_daily: nil,
        per_agent_monthly: nil,
        inherit_global_defaults: false
      )
      config = budget.to_budget_config
      expect(config[:per_agent_daily]).to eq({})
      expect(config[:per_agent_monthly]).to eq({})
    end

    context "with inheritance enabled" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = {
            per_agent_daily: { "GlobalAgentDaily" => 20.0 },
            per_agent_monthly: { "GlobalAgentMonthly" => 200.0 }
          }
        end
      end

      it "merges tenant-specific limits with global defaults" do
        budget = described_class.new(
          per_agent_daily: { "TenantAgentDaily" => 15.0 },
          per_agent_monthly: { "TenantAgentMonthly" => 150.0 },
          inherit_global_defaults: true
        )
        config = budget.to_budget_config

        # Should include both global and tenant-specific limits
        expect(config[:per_agent_daily]).to include(
          "GlobalAgentDaily" => 20.0,
          "TenantAgentDaily" => 15.0
        )
        expect(config[:per_agent_monthly]).to include(
          "GlobalAgentMonthly" => 200.0,
          "TenantAgentMonthly" => 150.0
        )
      end

      it "tenant-specific limits override global defaults for same agent" do
        budget = described_class.new(
          per_agent_daily: { "GlobalAgentDaily" => 5.0 },
          per_agent_monthly: { "GlobalAgentMonthly" => 50.0 },
          inherit_global_defaults: true
        )
        config = budget.to_budget_config

        # Tenant-specific should override global
        expect(config[:per_agent_daily]["GlobalAgentDaily"]).to eq(5.0)
        expect(config[:per_agent_monthly]["GlobalAgentMonthly"]).to eq(50.0)
      end

      it "uses global limits when tenant has nil per_agent hashes" do
        budget = described_class.new(
          per_agent_daily: nil,
          per_agent_monthly: nil,
          inherit_global_defaults: true
        )
        config = budget.to_budget_config

        expect(config[:per_agent_daily]).to include("GlobalAgentDaily" => 20.0)
        expect(config[:per_agent_monthly]).to include("GlobalAgentMonthly" => 200.0)
      end
    end

    context "without inheritance" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = {
            per_agent_daily: { "GlobalAgent" => 20.0 },
            per_agent_monthly: { "GlobalAgent" => 200.0 }
          }
        end
      end

      it "does not include global limits" do
        budget = described_class.new(
          per_agent_daily: { "TenantAgent" => 15.0 },
          per_agent_monthly: { "TenantAgent" => 150.0 },
          inherit_global_defaults: false
        )
        config = budget.to_budget_config

        expect(config[:per_agent_daily]).to eq({ "TenantAgent" => 15.0 })
        expect(config[:per_agent_monthly]).to eq({ "TenantAgent" => 150.0 })
        expect(config[:per_agent_daily]).not_to include("GlobalAgent")
        expect(config[:per_agent_monthly]).not_to include("GlobalAgent")
      end
    end
  end

  describe "ENFORCEMENT_MODES constant" do
    it "contains none, soft, and hard" do
      expect(described_class::ENFORCEMENT_MODES).to eq(%w[none soft hard])
    end
  end

  describe "associations" do
    it "belongs to tenant_record polymorphically" do
      association = described_class.reflect_on_association(:tenant_record)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:polymorphic]).to be true
      expect(association.options[:optional]).to be true
    end
  end

  describe "table name" do
    it "uses the correct table name" do
      expect(described_class.table_name).to eq("ruby_llm_agents_tenant_budgets")
    end
  end
end
