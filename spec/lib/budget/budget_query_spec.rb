# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Budget::BudgetQuery do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:budget_config) do
    {
      enabled: true,
      enforcement: :soft,
      global_daily: 100.0,
      global_monthly: 1000.0,
      per_agent_daily: { "TestAgent" => 10.0 },
      per_agent_monthly: { "TestAgent" => 100.0 },
      global_daily_tokens: 100_000,
      global_monthly_tokens: 1_000_000
    }
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.cache_store = cache_store
    end
  end

  after do
    cache_store.clear
  end

  describe ".current_spend" do
    it "returns 0 when no spend recorded" do
      expect(described_class.current_spend(:global, :daily, tenant_id: nil)).to eq(0.0)
    end

    it "returns current global daily spend" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 25.0, tenant_id: nil)

      expect(described_class.current_spend(:global, :daily, tenant_id: nil)).to eq(25.0)
    end

    it "returns current global monthly spend" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 250.0, tenant_id: nil)

      expect(described_class.current_spend(:global, :monthly, tenant_id: nil)).to eq(250.0)
    end

    it "returns agent-specific spend" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:agent, :daily, 5.0, agent_type: "TestAgent", tenant_id: nil)

      expect(described_class.current_spend(:agent, :daily, agent_type: "TestAgent", tenant_id: nil)).to eq(5.0)
    end

    it "returns spend for specific tenant" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 10.0, tenant_id: "org_123")
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 20.0, tenant_id: "org_456")

      expect(described_class.current_spend(:global, :daily, tenant_id: "org_123")).to eq(10.0)
      expect(described_class.current_spend(:global, :daily, tenant_id: "org_456")).to eq(20.0)
    end
  end

  describe ".current_tokens" do
    it "returns 0 when no tokens recorded" do
      expect(described_class.current_tokens(:daily, tenant_id: nil)).to eq(0)
    end

    it "returns current daily tokens" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 5000, tenant_id: nil)

      expect(described_class.current_tokens(:daily, tenant_id: nil)).to eq(5000)
    end

    it "returns current monthly tokens" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :monthly, 50_000, tenant_id: nil)

      expect(described_class.current_tokens(:monthly, tenant_id: nil)).to eq(50_000)
    end

    it "returns tokens for specific tenant" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 1000, tenant_id: "org_123")
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 2000, tenant_id: "org_456")

      expect(described_class.current_tokens(:daily, tenant_id: "org_123")).to eq(1000)
      expect(described_class.current_tokens(:daily, tenant_id: "org_456")).to eq(2000)
    end
  end

  describe ".remaining_budget" do
    before do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 30.0, tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 300.0, tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:agent, :daily, 3.0, agent_type: "TestAgent", tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:agent, :monthly, 30.0, agent_type: "TestAgent", tenant_id: nil)
    end

    it "returns remaining global daily budget" do
      result = described_class.remaining_budget(:global, :daily, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(70.0)
    end

    it "returns remaining global monthly budget" do
      result = described_class.remaining_budget(:global, :monthly, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(700.0)
    end

    it "returns remaining per-agent daily budget" do
      result = described_class.remaining_budget(:agent, :daily, agent_type: "TestAgent", tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(7.0)
    end

    it "returns remaining per-agent monthly budget" do
      result = described_class.remaining_budget(:agent, :monthly, agent_type: "TestAgent", tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(70.0)
    end

    it "returns nil when no per-agent monthly limit configured" do
      no_limit_config = budget_config.merge(per_agent_monthly: nil)
      result = described_class.remaining_budget(:agent, :monthly, agent_type: "TestAgent", tenant_id: nil, budget_config: no_limit_config)
      expect(result).to be_nil
    end

    it "returns nil when no limit configured" do
      no_limit_config = budget_config.merge(global_daily: nil)
      result = described_class.remaining_budget(:global, :daily, tenant_id: nil, budget_config: no_limit_config)
      expect(result).to be_nil
    end

    it "returns 0 when budget is exceeded" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 100.0, tenant_id: nil)

      result = described_class.remaining_budget(:global, :daily, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(0)
    end
  end

  describe ".remaining_token_budget" do
    before do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 40_000, tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :monthly, 400_000, tenant_id: nil)
    end

    it "returns remaining daily token budget" do
      result = described_class.remaining_token_budget(:daily, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(60_000)
    end

    it "returns remaining monthly token budget" do
      result = described_class.remaining_token_budget(:monthly, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(600_000)
    end

    it "returns nil when no limit configured" do
      no_limit_config = budget_config.merge(global_daily_tokens: nil)
      result = described_class.remaining_token_budget(:daily, tenant_id: nil, budget_config: no_limit_config)
      expect(result).to be_nil
    end

    it "returns 0 when token budget is exceeded" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 100_000, tenant_id: nil)

      result = described_class.remaining_token_budget(:daily, tenant_id: nil, budget_config: budget_config)
      expect(result).to eq(0)
    end
  end

  describe ".status" do
    before do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 25.0, tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 250.0, tenant_id: nil)
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 25_000, tenant_id: nil)
    end

    it "returns complete budget status" do
      result = described_class.status(agent_type: "TestAgent", tenant_id: nil, budget_config: budget_config)

      expect(result[:enabled]).to be true
      expect(result[:enforcement]).to eq(:soft)
      expect(result[:global_daily]).to be_a(Hash)
      expect(result[:global_monthly]).to be_a(Hash)
      expect(result[:global_daily_tokens]).to be_a(Hash)
    end

    it "includes tenant_id in status" do
      result = described_class.status(tenant_id: "org_123", budget_config: budget_config)
      expect(result[:tenant_id]).to eq("org_123")
    end

    it "includes forecast when budgets enabled" do
      result = described_class.status(budget_config: budget_config)
      expect(result[:forecast]).to be_present
    end
  end

  describe ".budget_status" do
    it "returns nil when no limit" do
      result = described_class.budget_status(:global, :daily, nil, tenant_id: nil)
      expect(result).to be_nil
    end

    it "returns status hash for a budget" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 30.0, tenant_id: nil)

      result = described_class.budget_status(:global, :daily, 100.0, tenant_id: nil)

      expect(result[:limit]).to eq(100.0)
      expect(result[:current]).to eq(30.0)
      expect(result[:remaining]).to eq(70.0)
      expect(result[:percentage_used]).to eq(30.0)
    end

    it "calculates percentage correctly" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 75.0, tenant_id: nil)

      result = described_class.budget_status(:global, :daily, 100.0, tenant_id: nil)

      expect(result[:percentage_used]).to eq(75.0)
    end
  end

  describe ".token_status" do
    it "returns nil when no limit" do
      result = described_class.token_status(:daily, nil, tenant_id: nil)
      expect(result).to be_nil
    end

    it "returns status hash for token budget" do
      RubyLLM::Agents::Budget::SpendRecorder.increment_tokens(:global, :daily, 30_000, tenant_id: nil)

      result = described_class.token_status(:daily, 100_000, tenant_id: nil)

      expect(result[:limit]).to eq(100_000)
      expect(result[:current]).to eq(30_000)
      expect(result[:remaining]).to eq(70_000)
      expect(result[:percentage_used]).to eq(30.0)
    end
  end
end
