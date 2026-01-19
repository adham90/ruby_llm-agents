# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Multi-tenancy support" do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
    cache_store.clear
  end

  describe RubyLLM::Agents::BudgetTracker do
    describe "tenant isolation" do
      before do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "default_tenant" }
          config.budgets = { global_daily: 100.0, enforcement: :hard }
        end
      end

      it "tracks spend separately per tenant" do
        described_class.record_spend!("TestAgent", 50.0, tenant_id: "tenant_1")
        described_class.record_spend!("TestAgent", 30.0, tenant_id: "tenant_2")

        expect(described_class.current_spend(:global, :daily, tenant_id: "tenant_1")).to eq(50.0)
        expect(described_class.current_spend(:global, :daily, tenant_id: "tenant_2")).to eq(30.0)
      end

      it "uses tenant from resolver when not explicitly passed" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "resolved_tenant" }
          config.budgets = { global_daily: 100.0 }
        end

        described_class.record_spend!("TestAgent", 25.0)

        expect(described_class.current_spend(:global, :daily)).to eq(25.0)
        expect(described_class.current_spend(:global, :daily, tenant_id: "other")).to eq(0)
      end

      it "checks budget per tenant" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "tenant_1" }
          config.budgets = { global_daily: 50.0, enforcement: :hard }
        end

        # Tenant 1 goes over budget
        described_class.record_spend!("TestAgent", 60.0, tenant_id: "tenant_1")
        # Tenant 2 is under budget
        described_class.record_spend!("TestAgent", 20.0, tenant_id: "tenant_2")

        expect {
          described_class.check_budget!("TestAgent", tenant_id: "tenant_1")
        }.to raise_error(RubyLLM::Agents::Reliability::BudgetExceededError) do |error|
          expect(error.tenant_id).to eq("tenant_1")
        end

        expect {
          described_class.check_budget!("TestAgent", tenant_id: "tenant_2")
        }.not_to raise_error
      end

      it "resets budget for specific tenant only" do
        described_class.record_spend!("TestAgent", 50.0, tenant_id: "tenant_1")
        described_class.record_spend!("TestAgent", 30.0, tenant_id: "tenant_2")

        described_class.reset!(tenant_id: "tenant_1")

        expect(described_class.current_spend(:global, :daily, tenant_id: "tenant_1")).to eq(0)
        expect(described_class.current_spend(:global, :daily, tenant_id: "tenant_2")).to eq(30.0)
      end

      it "includes tenant_id in status" do
        described_class.record_spend!("TestAgent", 25.0, tenant_id: "tenant_1")

        status = described_class.status(tenant_id: "tenant_1")

        expect(status[:tenant_id]).to eq("tenant_1")
        expect(status[:global_daily][:current]).to eq(25.0)
      end
    end

    describe "with TenantBudget database config" do
      before do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "tenant_1" }
          config.budgets = { global_daily: 100.0, enforcement: :soft }
        end

        # Reset memoized table check to ensure fresh lookup
        RubyLLM::Agents::Budget::ConfigResolver.reset_tenant_budget_table_check!

        # Skip if TenantBudget table doesn't exist (migration not run)
        skip "TenantBudget table not available" unless tenant_budget_table_exists?
      end

      it "uses database budget limits when available" do
        RubyLLM::Agents::TenantBudget.create!(
          tenant_id: "tenant_1",
          daily_limit: 20.0,
          enforcement: "hard"
        )

        described_class.record_spend!("TestAgent", 25.0, tenant_id: "tenant_1")

        expect {
          described_class.check_budget!("TestAgent", tenant_id: "tenant_1")
        }.to raise_error(RubyLLM::Agents::Reliability::BudgetExceededError)
      end

      it "falls back to global config for unknown tenants" do
        described_class.record_spend!("TestAgent", 150.0, tenant_id: "unknown_tenant")

        # Global config has soft enforcement, so no error
        expect {
          described_class.check_budget!("TestAgent", tenant_id: "unknown_tenant")
        }.not_to raise_error
      end
    end

    describe "backward compatibility" do
      it "works without multi-tenancy enabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = false
          config.budgets = { global_daily: 50.0, enforcement: :hard }
        end

        described_class.record_spend!("TestAgent", 30.0)

        expect(described_class.current_spend(:global, :daily)).to eq(30.0)
        expect { described_class.check_budget!("TestAgent") }.not_to raise_error
      end

      it "ignores tenant_id when multi-tenancy is disabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = false
          config.budgets = { global_daily: 50.0 }
        end

        # These should all go to the same global counter
        described_class.record_spend!("TestAgent", 10.0, tenant_id: "tenant_1")
        described_class.record_spend!("TestAgent", 20.0, tenant_id: "tenant_2")

        expect(described_class.current_spend(:global, :daily)).to eq(30.0)
      end
    end

    def tenant_budget_table_exists?
      ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
    rescue StandardError
      false
    end
  end

  describe RubyLLM::Agents::CircuitBreaker do
    describe "tenant isolation" do
      before do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "default_tenant" }
        end
      end

      it "tracks failures separately per tenant" do
        breaker_1 = described_class.new("TestAgent", "gpt-4o", tenant_id: "tenant_1", errors: 3)
        breaker_2 = described_class.new("TestAgent", "gpt-4o", tenant_id: "tenant_2", errors: 3)

        # Trip breaker for tenant_1
        3.times { breaker_1.record_failure! }

        expect(breaker_1.open?).to be true
        expect(breaker_2.open?).to be false
      end

      it "includes tenant_id in status" do
        breaker = described_class.new("TestAgent", "gpt-4o", tenant_id: "tenant_1", errors: 5)

        status = breaker.status

        expect(status[:tenant_id]).to eq("tenant_1")
      end

      it "isolates reset per tenant" do
        breaker_1 = described_class.new("TestAgent", "gpt-4o", tenant_id: "tenant_1", errors: 3)
        breaker_2 = described_class.new("TestAgent", "gpt-4o", tenant_id: "tenant_2", errors: 3)

        3.times { breaker_1.record_failure! }
        3.times { breaker_2.record_failure! }

        breaker_1.reset!

        expect(breaker_1.open?).to be false
        expect(breaker_2.open?).to be true
      end

      it "resolves tenant from config when not provided" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "auto_tenant" }
        end

        breaker = described_class.new("TestAgent", "gpt-4o", errors: 3)

        expect(breaker.tenant_id).to eq("auto_tenant")
      end
    end

    describe "backward compatibility" do
      it "works without multi-tenancy enabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = false
        end

        breaker = described_class.new("TestAgent", "gpt-4o", errors: 3)

        3.times { breaker.record_failure! }

        expect(breaker.open?).to be true
        expect(breaker.tenant_id).to be_nil
      end
    end
  end

  describe RubyLLM::Agents::Configuration do
    describe "#multi_tenancy_enabled?" do
      it "returns false by default" do
        RubyLLM::Agents.reset_configuration!
        expect(RubyLLM::Agents.configuration.multi_tenancy_enabled?).to be false
      end

      it "returns true when enabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
        end

        expect(RubyLLM::Agents.configuration.multi_tenancy_enabled?).to be true
      end
    end

    describe "#current_tenant_id" do
      it "returns nil when multi-tenancy is disabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = false
          config.tenant_resolver = -> { "some_tenant" }
        end

        expect(RubyLLM::Agents.configuration.current_tenant_id).to be_nil
      end

      it "calls tenant_resolver when enabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "resolved_tenant" }
        end

        expect(RubyLLM::Agents.configuration.current_tenant_id).to eq("resolved_tenant")
      end
    end
  end
end
