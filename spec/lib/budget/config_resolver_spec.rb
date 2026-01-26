# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Budget::ConfigResolver do
  let(:config) { RubyLLM::Agents.configuration }

  before do
    RubyLLM::Agents.reset_configuration!
  end

  after do
    described_class.reset_tenant_budget_table_check!
  end

  describe ".resolve_tenant_id" do
    context "when multi-tenancy is disabled" do
      before do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = false
        end
      end

      it "returns nil even when explicit tenant_id is provided" do
        result = described_class.resolve_tenant_id("org_123")
        expect(result).to be_nil
      end

      it "returns nil when no tenant_id is provided" do
        result = described_class.resolve_tenant_id(nil)
        expect(result).to be_nil
      end
    end

    context "when multi-tenancy is enabled" do
      before do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = true
        end
      end

      it "returns explicit tenant_id when provided" do
        result = described_class.resolve_tenant_id("org_123")
        expect(result).to eq("org_123")
      end

      it "uses tenant_resolver when no explicit tenant_id" do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = true
          c.tenant_resolver = -> { "resolved_org" }
        end

        result = described_class.resolve_tenant_id(nil)
        expect(result).to eq("resolved_org")
      end

      it "returns nil when no tenant_id and no resolver returns nil" do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = true
          c.tenant_resolver = -> { nil }
        end

        result = described_class.resolve_tenant_id(nil)
        expect(result).to be_nil
      end
    end
  end

  describe ".resolve_budget_config" do
    context "with runtime config" do
      it "uses runtime config as highest priority" do
        runtime_config = {
          daily_budget_limit: 100.0,
          monthly_budget_limit: 500.0,
          enforcement: :hard
        }

        result = described_class.resolve_budget_config("org_123", runtime_config: runtime_config)

        expect(result[:global_daily]).to eq(100.0)
        expect(result[:global_monthly]).to eq(500.0)
        expect(result[:enforcement]).to eq(:hard)
        expect(result[:enabled]).to be true
      end
    end

    context "with no tenant_id" do
      before do
        RubyLLM::Agents.configure do |c|
          c.budgets = {
            enforcement: :soft,
            global_daily: 50.0,
            global_monthly: 200.0
          }
        end
      end

      it "returns global budget config" do
        result = described_class.resolve_budget_config(nil)

        expect(result[:global_daily]).to eq(50.0)
        expect(result[:global_monthly]).to eq(200.0)
        expect(result[:enforcement]).to eq(:soft)
      end
    end

    context "with tenant_config_resolver" do
      before do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = true
          c.tenant_config_resolver = lambda { |tenant_id|
            if tenant_id == "premium_org"
              { daily_budget_limit: 500.0, monthly_budget_limit: 2000.0, enforcement: :soft }
            end
          }
        end
      end

      it "uses tenant_config_resolver when configured" do
        result = described_class.resolve_budget_config("premium_org")

        expect(result[:global_daily]).to eq(500.0)
        expect(result[:global_monthly]).to eq(2000.0)
      end

      it "falls back to global config when resolver returns nil" do
        RubyLLM::Agents.configure do |c|
          c.multi_tenancy_enabled = true
          c.tenant_config_resolver = ->(_tenant_id) { nil }
          c.budgets = { enforcement: :soft, global_daily: 10.0 }
        end

        result = described_class.resolve_budget_config("unknown_org")

        expect(result[:global_daily]).to eq(10.0)
      end
    end
  end

  describe ".global_budget_config" do
    before do
      RubyLLM::Agents.configure do |c|
        c.budgets = {
          enforcement: :hard,
          global_daily: 100.0,
          global_monthly: 1000.0,
          per_agent_daily: { "TestAgent" => 10.0 },
          per_agent_monthly: { "TestAgent" => 100.0 },
          global_daily_tokens: 100_000,
          global_monthly_tokens: 1_000_000
        }
      end
    end

    it "builds config from global settings" do
      result = described_class.global_budget_config(config)

      expect(result[:enabled]).to be true
      expect(result[:enforcement]).to eq(:hard)
      expect(result[:global_daily]).to eq(100.0)
      expect(result[:global_monthly]).to eq(1000.0)
      expect(result[:per_agent_daily]).to eq({ "TestAgent" => 10.0 })
      expect(result[:per_agent_monthly]).to eq({ "TestAgent" => 100.0 })
      expect(result[:global_daily_tokens]).to eq(100_000)
      expect(result[:global_monthly_tokens]).to eq(1_000_000)
    end
  end

  describe ".normalize_budget_config" do
    let(:global_config) { RubyLLM::Agents.configuration }

    before do
      RubyLLM::Agents.configure do |c|
        c.budgets = { enforcement: :soft }
      end
    end

    it "normalizes runtime config to standard format" do
      raw_config = {
        daily_budget_limit: 50.0,
        monthly_budget_limit: 500.0,
        daily_token_limit: 100_000,
        monthly_token_limit: 1_000_000
      }

      result = described_class.normalize_budget_config(raw_config, global_config)

      expect(result[:global_daily]).to eq(50.0)
      expect(result[:global_monthly]).to eq(500.0)
      expect(result[:global_daily_tokens]).to eq(100_000)
      expect(result[:global_monthly_tokens]).to eq(1_000_000)
      expect(result[:enabled]).to be true
    end

    it "uses enforcement from raw config when provided" do
      raw_config = { enforcement: :hard }

      result = described_class.normalize_budget_config(raw_config, global_config)

      expect(result[:enforcement]).to eq(:hard)
    end

    it "falls back to global enforcement" do
      raw_config = {}

      result = described_class.normalize_budget_config(raw_config, global_config)

      expect(result[:enforcement]).to eq(:soft)
    end

    it "sets enabled to false when enforcement is :none" do
      raw_config = { enforcement: :none }

      result = described_class.normalize_budget_config(raw_config, global_config)

      expect(result[:enabled]).to be false
    end
  end

  describe ".lookup_tenant_budget" do
    context "when table does not exist" do
      before do
        allow(described_class).to receive(:tenant_budget_table_exists?).and_return(false)
      end

      it "returns nil" do
        result = described_class.lookup_tenant_budget("org_123")
        expect(result).to be_nil
      end
    end

    context "when table exists" do
      before do
        described_class.reset_tenant_budget_table_check!
        allow(described_class).to receive(:tenant_budget_table_exists?).and_return(true)
      end

      it "looks up tenant budget from database" do
        mock_budget = double("TenantBudget")
        allow(RubyLLM::Agents::TenantBudget).to receive(:for_tenant)
          .with("org_123")
          .and_return(mock_budget)

        result = described_class.lookup_tenant_budget("org_123")
        expect(result).to eq(mock_budget)
      end

      it "returns nil when tenant budget not found" do
        allow(RubyLLM::Agents::TenantBudget).to receive(:for_tenant)
          .with("unknown_org")
          .and_return(nil)

        result = described_class.lookup_tenant_budget("unknown_org")
        expect(result).to be_nil
      end

      it "handles database errors gracefully" do
        allow(RubyLLM::Agents::TenantBudget).to receive(:for_tenant)
          .and_raise(ActiveRecord::RecordNotFound)

        result = described_class.lookup_tenant_budget("org_123")
        expect(result).to be_nil
      end
    end
  end

  describe ".tenant_budget_table_exists?" do
    before do
      described_class.reset_tenant_budget_table_check!
    end

    it "memoizes the result" do
      # Stub both table name checks (new name checked first, then old name for backward compatibility)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(true)

      described_class.tenant_budget_table_exists?
      described_class.tenant_budget_table_exists?

      # Should only call table_exists? once due to memoization
      expect(ActiveRecord::Base.connection).to have_received(:table_exists?).with(:ruby_llm_agents_tenants).once
    end

    it "returns false on database errors" do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .and_raise(StandardError.new("Database error"))

      result = described_class.tenant_budget_table_exists?
      expect(result).to be false
    end
  end

  describe ".reset_tenant_budget_table_check!" do
    it "clears the memoized value" do
      # Set memoized value
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(true)
      described_class.tenant_budget_table_exists?

      described_class.reset_tenant_budget_table_check!

      # Should call table_exists? again
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)
      result = described_class.tenant_budget_table_exists?
      expect(result).to be false
    end
  end
end
