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

  describe "#effective_enforcement" do
    it "returns enforcement when set" do
      budget = described_class.new(enforcement: "hard")
      expect(budget.effective_enforcement).to eq(:hard)
    end

    it "defaults to :soft when not set and inherit is true" do
      RubyLLM::Agents.configure do |config|
        config.budgets = { enforcement: :soft }
      end

      budget = described_class.new(enforcement: nil, inherit_global_defaults: true)
      expect(budget.effective_enforcement).to eq(:soft)
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
  end
end
