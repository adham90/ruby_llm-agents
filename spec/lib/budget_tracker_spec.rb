# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BudgetTracker do
  # Use a fresh cache store for each test to avoid state leakage
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  around do |example|
    # Create fresh configuration and cache for each test
    RubyLLM::Agents.reset_configuration!
    fresh_cache = ActiveSupport::Cache::MemoryStore.new
    RubyLLM::Agents.configuration.cache_store = fresh_cache
    example.run
  end

  describe ".check_budget!" do
    context "with no budget limits configured" do
      it "does not raise" do
        expect { described_class.check_budget!("TestAgent") }.not_to raise_error
      end
    end

    context "with global daily budget and hard enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily: 10.0, enforcement: :hard }
        end
      end

      it "does not raise when under budget" do
        described_class.record_spend!("TestAgent", 5.0)
        expect { described_class.check_budget!("TestAgent") }.not_to raise_error
      end

      it "raises BudgetExceededError when at or over budget" do
        described_class.record_spend!("TestAgent", 15.0)

        expect { described_class.check_budget!("TestAgent") }.to raise_error(
          RubyLLM::Agents::Reliability::BudgetExceededError
        ) do |error|
          expect(error.scope).to eq(:global_daily)
        end
      end
    end

    context "with global monthly budget and hard enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_monthly: 100.0, enforcement: :hard }
        end
      end

      it "raises when monthly budget exceeded" do
        described_class.record_spend!("TestAgent", 150.0)

        expect { described_class.check_budget!("TestAgent") }.to raise_error(
          RubyLLM::Agents::Reliability::BudgetExceededError
        ) do |error|
          expect(error.scope).to eq(:global_monthly)
        end
      end
    end

    context "with per-agent daily budget and hard enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = {
            per_agent_daily: { "ExpensiveAgent" => 5.0 },
            enforcement: :hard
          }
        end
      end

      it "raises when agent daily budget exceeded" do
        described_class.record_spend!("ExpensiveAgent", 6.0)

        expect { described_class.check_budget!("ExpensiveAgent") }.to raise_error(
          RubyLLM::Agents::Reliability::BudgetExceededError
        ) do |error|
          expect(error.scope).to eq(:per_agent_daily)
        end
      end

      it "does not raise for other agents" do
        described_class.record_spend!("ExpensiveAgent", 6.0)

        # Different agent has no per-agent limit
        expect { described_class.check_budget!("OtherAgent") }.not_to raise_error
      end
    end

    context "with soft enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily: 10.0, enforcement: :soft }
        end
      end

      it "does not raise even when over budget" do
        described_class.record_spend!("TestAgent", 15.0)
        expect { described_class.check_budget!("TestAgent") }.not_to raise_error
      end
    end
  end

  describe ".record_spend!" do
    it "accumulates spend for global tracking" do
      described_class.record_spend!("TestAgent", 5.0)
      described_class.record_spend!("TestAgent", 3.0)

      expect(described_class.current_spend(:global, :daily)).to eq(8.0)
    end

    it "accumulates spend separately for different agents" do
      described_class.record_spend!("Agent1", 5.0)
      described_class.record_spend!("Agent2", 3.0)

      expect(described_class.current_spend(:agent, :daily, agent_type: "Agent1")).to eq(5.0)
      expect(described_class.current_spend(:agent, :daily, agent_type: "Agent2")).to eq(3.0)
    end

    it "ignores nil or zero amounts" do
      described_class.record_spend!("TestAgent", nil)
      described_class.record_spend!("TestAgent", 0)
      described_class.record_spend!("TestAgent", -5)

      expect(described_class.current_spend(:global, :daily)).to eq(0)
    end
  end

  describe ".current_spend" do
    it "returns 0 when no spend recorded" do
      expect(described_class.current_spend(:global, :daily)).to eq(0)
    end

    it "returns recorded spend" do
      described_class.record_spend!("TestAgent", 7.5)
      expect(described_class.current_spend(:global, :daily)).to eq(7.5)
    end

    it "tracks daily and monthly separately" do
      described_class.record_spend!("TestAgent", 5.0)

      # Both should have the spend recorded
      expect(described_class.current_spend(:global, :daily)).to eq(5.0)
      expect(described_class.current_spend(:global, :monthly)).to eq(5.0)
    end
  end

  describe ".remaining_budget" do
    before do
      RubyLLM::Agents.configure do |config|
        config.budgets = { global_daily: 10.0 }
      end
    end

    it "returns full budget when no spend" do
      expect(described_class.remaining_budget(:global, :daily)).to eq(10.0)
    end

    it "returns remaining after spend" do
      described_class.record_spend!("TestAgent", 3.5)
      expect(described_class.remaining_budget(:global, :daily)).to eq(6.5)
    end

    it "returns nil when no limit configured" do
      expect(described_class.remaining_budget(:global, :monthly)).to be_nil
    end

    it "returns 0 when over budget" do
      described_class.record_spend!("TestAgent", 15.0)
      expect(described_class.remaining_budget(:global, :daily)).to eq(0)
    end
  end

  describe ".status" do
    before do
      RubyLLM::Agents.configure do |config|
        config.budgets = { global_daily: 10.0, global_monthly: 100.0 }
      end
    end

    it "returns status for configured budgets" do
      described_class.record_spend!("TestAgent", 5.0)
      status = described_class.status

      # Check that global daily budget status is present and correct
      expect(status[:global_daily][:limit]).to eq(10.0)
      expect(status[:global_daily][:current]).to eq(5.0)
      expect(status[:global_daily][:remaining]).to eq(5.0)
      expect(status[:global_daily][:percentage_used]).to eq(50.0)
    end
  end

  describe ".reset!" do
    it "clears budget counters" do
      described_class.record_spend!("TestAgent", 10.0)
      expect(described_class.current_spend(:global, :daily)).to eq(10.0)

      described_class.reset!
      expect(described_class.current_spend(:global, :daily)).to eq(0)
    end

    it "clears counters for specific tenant" do
      described_class.record_spend!("TestAgent", 10.0, tenant_id: "org_123")
      expect(described_class.current_spend(:global, :daily, tenant_id: "org_123")).to eq(10.0)

      described_class.reset!(tenant_id: "org_123")
      expect(described_class.current_spend(:global, :daily, tenant_id: "org_123")).to eq(0)
    end
  end

  describe ".check_token_budget!" do
    context "with no token budget limits configured" do
      it "does not raise" do
        expect { described_class.check_token_budget!("TestAgent") }.not_to raise_error
      end
    end

    context "with global daily token budget and hard enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily_tokens: 10_000, enforcement: :hard }
        end
      end

      it "does not raise when under budget" do
        described_class.record_tokens!("TestAgent", 5000)
        expect { described_class.check_token_budget!("TestAgent") }.not_to raise_error
      end

      it "raises BudgetExceededError when at or over budget" do
        described_class.record_tokens!("TestAgent", 15_000)

        expect { described_class.check_token_budget!("TestAgent") }.to raise_error(
          RubyLLM::Agents::Reliability::BudgetExceededError
        ) do |error|
          expect(error.scope).to eq(:global_daily_tokens)
        end
      end
    end

    context "with global monthly token budget and hard enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_monthly_tokens: 100_000, enforcement: :hard }
        end
      end

      it "raises when monthly token budget exceeded" do
        described_class.record_tokens!("TestAgent", 150_000)

        expect { described_class.check_token_budget!("TestAgent") }.to raise_error(
          RubyLLM::Agents::Reliability::BudgetExceededError
        ) do |error|
          expect(error.scope).to eq(:global_monthly_tokens)
        end
      end
    end

    context "with soft enforcement" do
      before do
        RubyLLM::Agents.configure do |config|
          config.budgets = { global_daily_tokens: 10_000, enforcement: :soft }
        end
      end

      it "does not raise even when over budget" do
        described_class.record_tokens!("TestAgent", 15_000)
        expect { described_class.check_token_budget!("TestAgent") }.not_to raise_error
      end
    end
  end

  describe ".record_tokens!" do
    it "accumulates tokens for global tracking" do
      described_class.record_tokens!("TestAgent", 5000)
      described_class.record_tokens!("TestAgent", 3000)

      expect(described_class.current_tokens(:daily)).to eq(8000)
    end

    it "ignores nil or zero amounts" do
      described_class.record_tokens!("TestAgent", nil)
      described_class.record_tokens!("TestAgent", 0)
      described_class.record_tokens!("TestAgent", -500)

      expect(described_class.current_tokens(:daily)).to eq(0)
    end
  end

  describe ".current_tokens" do
    it "returns 0 when no tokens recorded" do
      expect(described_class.current_tokens(:daily)).to eq(0)
    end

    it "returns recorded tokens" do
      described_class.record_tokens!("TestAgent", 7500)
      expect(described_class.current_tokens(:daily)).to eq(7500)
    end

    it "tracks daily and monthly separately" do
      described_class.record_tokens!("TestAgent", 5000)

      expect(described_class.current_tokens(:daily)).to eq(5000)
      expect(described_class.current_tokens(:monthly)).to eq(5000)
    end
  end

  describe ".remaining_token_budget" do
    before do
      RubyLLM::Agents.configure do |config|
        config.budgets = { global_daily_tokens: 10_000 }
      end
    end

    it "returns full budget when no tokens used" do
      expect(described_class.remaining_token_budget(:daily)).to eq(10_000)
    end

    it "returns remaining after token usage" do
      described_class.record_tokens!("TestAgent", 3500)
      expect(described_class.remaining_token_budget(:daily)).to eq(6500)
    end

    it "returns nil when no limit configured" do
      expect(described_class.remaining_token_budget(:monthly)).to be_nil
    end

    it "returns 0 when over budget" do
      described_class.record_tokens!("TestAgent", 15_000)
      expect(described_class.remaining_token_budget(:daily)).to eq(0)
    end
  end

  describe ".calculate_forecast" do
    before do
      RubyLLM::Agents.configure do |config|
        config.budgets = { enforcement: :soft, global_daily: 10.0, global_monthly: 100.0 }
      end
    end

    it "returns forecast data" do
      described_class.record_spend!("TestAgent", 5.0)
      forecast = described_class.calculate_forecast

      expect(forecast).to be_a(Hash)
    end

    it "works with tenant_id" do
      described_class.record_spend!("TestAgent", 5.0, tenant_id: "org_123")
      forecast = described_class.calculate_forecast(tenant_id: "org_123")

      expect(forecast).to be_a(Hash)
    end
  end

  describe ".check_budget! with per-agent monthly budget" do
    before do
      RubyLLM::Agents.configure do |config|
        config.budgets = {
          per_agent_monthly: { "ExpensiveAgent" => 50.0 },
          enforcement: :hard
        }
      end
    end

    it "raises when agent monthly budget exceeded" do
      described_class.record_spend!("ExpensiveAgent", 60.0)

      expect { described_class.check_budget!("ExpensiveAgent") }.to raise_error(
        RubyLLM::Agents::Reliability::BudgetExceededError
      ) do |error|
        expect(error.scope).to eq(:per_agent_monthly)
      end
    end
  end

  describe "with tenant_config runtime override" do
    it "uses runtime tenant_config for check_budget!" do
      # Note: normalize_budget_config expects daily_budget_limit, not global_daily
      runtime_config = { daily_budget_limit: 5.0, enforcement: :hard }
      described_class.record_spend!("TestAgent", 10.0)

      expect { described_class.check_budget!("TestAgent", tenant_config: runtime_config) }.to raise_error(
        RubyLLM::Agents::Reliability::BudgetExceededError
      )
    end

    it "uses runtime tenant_config for record_spend!" do
      runtime_config = { enforcement: :soft }

      expect { described_class.record_spend!("TestAgent", 5.0, tenant_config: runtime_config) }.not_to raise_error
    end
  end
end
