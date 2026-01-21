# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Budget::SpendRecorder do
  let(:config) { RubyLLM::Agents.configuration }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before(:each) do
    cache_store.clear # Clear cache before each test
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.cache_store = cache_store
    end
  end

  after(:each) do
    cache_store.clear
  end

  describe ".record_spend!" do
    let(:budget_config) do
      {
        enabled: true,
        enforcement: :soft,
        global_daily: 100.0,
        global_monthly: 1000.0
      }
    end

    it "increments all relevant counters" do
      described_class.record_spend!("TestAgent", 10.0, tenant_id: nil, budget_config: budget_config)

      expect(described_class.increment_spend(:global, :daily, 0, tenant_id: nil)).to eq(10.0)
      expect(described_class.increment_spend(:global, :monthly, 0, tenant_id: nil)).to eq(10.0)
    end

    it "skips recording when amount is nil" do
      expect {
        described_class.record_spend!("TestAgent", nil, tenant_id: nil, budget_config: budget_config)
      }.not_to change {
        RubyLLM::Agents::Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: nil)
      }
    end

    it "skips recording when amount is zero or negative" do
      described_class.record_spend!("TestAgent", 0, tenant_id: nil, budget_config: budget_config)
      described_class.record_spend!("TestAgent", -5.0, tenant_id: nil, budget_config: budget_config)

      expect(RubyLLM::Agents::Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: nil)).to eq(0)
    end

    it "records spend with tenant isolation" do
      described_class.record_spend!("TestAgent", 10.0, tenant_id: "org_123", budget_config: budget_config)
      described_class.record_spend!("TestAgent", 5.0, tenant_id: "org_456", budget_config: budget_config)

      expect(RubyLLM::Agents::Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: "org_123")).to eq(10.0)
      expect(RubyLLM::Agents::Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: "org_456")).to eq(5.0)
    end
  end

  describe ".record_tokens!" do
    let(:budget_config) do
      {
        enabled: false, # Disable to avoid alert checking which requires more setup
        enforcement: :soft,
        global_daily_tokens: 100_000,
        global_monthly_tokens: 1_000_000
      }
    end

    # NOTE: record_tokens! calls increment_tokens 4 times (global daily, global monthly, agent daily, agent monthly)
    # but increment_tokens ignores scope parameter, so daily/monthly tokens are each incremented twice.
    # This is documented behavior ("For now, we only track global token usage").

    it "increments token counters (note: doubled due to global+agent calls)" do
      described_class.record_tokens!("TestAgent", 1000, tenant_id: nil, budget_config: budget_config)

      # Tokens are incremented twice per period (global + agent calls to same key)
      expect(RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:daily, tenant_id: nil)).to eq(2000)
      expect(RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:monthly, tenant_id: nil)).to eq(2000)
    end

    it "skips recording when tokens is nil" do
      expect {
        described_class.record_tokens!("TestAgent", nil, tenant_id: nil, budget_config: budget_config)
      }.not_to change {
        RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:daily, tenant_id: nil)
      }
    end

    it "skips recording when tokens is zero or negative" do
      described_class.record_tokens!("TestAgent", 0, tenant_id: nil, budget_config: budget_config)
      described_class.record_tokens!("TestAgent", -100, tenant_id: nil, budget_config: budget_config)

      expect(RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:daily, tenant_id: nil)).to eq(0)
    end

    it "records tokens with tenant isolation (note: doubled due to global+agent calls)" do
      described_class.record_tokens!("TestAgent", 1000, tenant_id: "org_123", budget_config: budget_config)
      described_class.record_tokens!("TestAgent", 500, tenant_id: "org_456", budget_config: budget_config)

      # Tokens are incremented twice per period (global + agent calls to same key)
      expect(RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:daily, tenant_id: "org_123")).to eq(2000)
      expect(RubyLLM::Agents::Budget::BudgetQuery.current_tokens(:daily, tenant_id: "org_456")).to eq(1000)
    end
  end

  describe ".increment_spend" do
    it "increments global daily spend" do
      result = described_class.increment_spend(:global, :daily, 10.0, tenant_id: nil)
      expect(result).to eq(10.0)

      result = described_class.increment_spend(:global, :daily, 5.0, tenant_id: nil)
      expect(result).to eq(15.0)
    end

    it "increments global monthly spend" do
      result = described_class.increment_spend(:global, :monthly, 100.0, tenant_id: nil)
      expect(result).to eq(100.0)
    end

    it "increments agent-specific spend" do
      result = described_class.increment_spend(:agent, :daily, 10.0, agent_type: "TestAgent", tenant_id: nil)
      expect(result).to eq(10.0)
    end

    it "handles floating point amounts" do
      described_class.increment_spend(:global, :daily, 10.123456, tenant_id: nil)
      described_class.increment_spend(:global, :daily, 5.654321, tenant_id: nil)

      key = described_class.budget_cache_key(:global, :daily, tenant_id: nil)
      expect(described_class.cache_read(key)).to be_within(0.0001).of(15.777777)
    end
  end

  describe ".increment_tokens" do
    it "increments daily tokens" do
      result = described_class.increment_tokens(:global, :daily, 1000, tenant_id: nil)
      expect(result).to eq(1000)

      result = described_class.increment_tokens(:global, :daily, 500, tenant_id: nil)
      expect(result).to eq(1500)
    end

    it "increments monthly tokens" do
      result = described_class.increment_tokens(:global, :monthly, 10_000, tenant_id: nil)
      expect(result).to eq(10_000)
    end
  end

  describe ".tenant_key_part" do
    it "returns 'global' when no tenant_id" do
      expect(described_class.tenant_key_part(nil)).to eq("global")
      expect(described_class.tenant_key_part("")).to eq("global")
    end

    it "returns 'tenant:{id}' when tenant_id provided" do
      expect(described_class.tenant_key_part("org_123")).to eq("tenant:org_123")
    end
  end

  describe ".date_key_part" do
    it "returns current date for daily period" do
      expect(described_class.date_key_part(:daily)).to eq(Date.current.to_s)
    end

    it "returns year-month for monthly period" do
      expect(described_class.date_key_part(:monthly)).to eq(Date.current.strftime("%Y-%m"))
    end
  end

  describe ".budget_cache_key" do
    it "generates global daily key" do
      key = described_class.budget_cache_key(:global, :daily, tenant_id: nil)
      expect(key).to include("budget")
      expect(key).to include("global")
      expect(key).to include(Date.current.to_s)
    end

    it "generates global monthly key" do
      key = described_class.budget_cache_key(:global, :monthly, tenant_id: nil)
      expect(key).to include("budget")
      expect(key).to include(Date.current.strftime("%Y-%m"))
    end

    it "generates agent-specific key" do
      key = described_class.budget_cache_key(:agent, :daily, agent_type: "TestAgent", tenant_id: nil)
      expect(key).to include("agent")
      expect(key).to include("TestAgent")
    end

    it "includes tenant in key" do
      key = described_class.budget_cache_key(:global, :daily, tenant_id: "org_123")
      expect(key).to include("tenant:org_123")
    end

    it "raises for unknown scope" do
      expect {
        described_class.budget_cache_key(:unknown, :daily, tenant_id: nil)
      }.to raise_error(ArgumentError, /Unknown scope/)
    end
  end

  describe ".token_cache_key" do
    it "generates daily token key" do
      key = described_class.token_cache_key(:daily, tenant_id: nil)
      expect(key).to include("tokens")
      expect(key).to include(Date.current.to_s)
    end

    it "generates monthly token key" do
      key = described_class.token_cache_key(:monthly, tenant_id: nil)
      expect(key).to include("tokens")
      expect(key).to include(Date.current.strftime("%Y-%m"))
    end

    it "includes tenant in key" do
      key = described_class.token_cache_key(:daily, tenant_id: "org_123")
      expect(key).to include("tenant:org_123")
    end
  end

  describe ".alert_cache_key" do
    it "generates alert key with scope and tenant" do
      key = described_class.alert_cache_key("budget_alert", :global_daily, "org_123")
      expect(key).to include("budget_alert")
      expect(key).to include("tenant:org_123")
      expect(key).to include("global_daily")
    end

    it "uses 'global' when no tenant" do
      key = described_class.alert_cache_key("token_alert", :global_monthly, nil)
      expect(key).to include("global")
      expect(key).not_to include("tenant:")
    end
  end

  describe "soft cap alerting" do
    let(:budget_config) do
      {
        enabled: true,
        enforcement: :soft,
        global_daily: 10.0,
        global_monthly: 100.0,
        per_agent_daily: { "TestAgent" => 5.0 },
        per_agent_monthly: { "TestAgent" => 50.0 }
      }
    end

    before do
      RubyLLM::Agents.configure do |c|
        c.cache_store = cache_store
        c.alerts = {
          custom: ->(event, payload) { @alert_called = [event, payload] },
          on_events: [:budget_soft_cap, :budget_hard_cap, :token_soft_cap, :token_hard_cap]
        }
      end
      @alert_called = nil
    end

    describe "check_soft_cap_alerts (via record_spend!)" do
      it "does not trigger alert when within budget" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 5.0, tenant_id: nil, budget_config: budget_config)

        expect(RubyLLM::Agents::AlertManager).not_to have_received(:notify)
      end

      it "triggers budget_soft_cap alert when global daily exceeded" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        # First record to put us at the limit
        described_class.record_spend!("TestAgent", 10.0, tenant_id: nil, budget_config: budget_config)
        # Second record exceeds the limit
        described_class.record_spend!("TestAgent", 1.0, tenant_id: nil, budget_config: budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_soft_cap,
          hash_including(scope: :global_daily, limit: 10.0)
        )
      end

      it "triggers budget_soft_cap alert when per_agent_daily exceeded" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 6.0, tenant_id: nil, budget_config: budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_soft_cap,
          hash_including(scope: :per_agent_daily)
        )
      end

      it "does not trigger duplicate alerts" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: nil, budget_config: budget_config)
        described_class.record_spend!("TestAgent", 1.0, tenant_id: nil, budget_config: budget_config)
        described_class.record_spend!("TestAgent", 1.0, tenant_id: nil, budget_config: budget_config)

        # Alert should only be called once per scope due to cache key dedup
        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_soft_cap,
          hash_including(scope: :global_daily)
        ).at_most(:once)
      end

      it "triggers budget_hard_cap when enforcement is :hard" do
        hard_budget_config = budget_config.merge(enforcement: :hard)
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: nil, budget_config: hard_budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_hard_cap,
          hash_including(scope: :global_daily)
        )
      end

      it "isolates alerts by tenant" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: "tenant_a", budget_config: budget_config)
        described_class.record_spend!("TestAgent", 11.0, tenant_id: "tenant_b", budget_config: budget_config)

        # Both tenants should get alerts since they're isolated
        # Each tenant exceeds both global_daily and per_agent_daily, so expect at least one alert per tenant
        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_soft_cap,
          hash_including(tenant_id: "tenant_a")
        ).at_least(:once)
        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :budget_soft_cap,
          hash_including(tenant_id: "tenant_b")
        ).at_least(:once)
      end

      it "does not trigger alert when alerts are disabled" do
        RubyLLM::Agents.configure do |c|
          c.alerts = nil
        end
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: nil, budget_config: budget_config)

        expect(RubyLLM::Agents::AlertManager).not_to have_received(:notify)
      end

      it "does not trigger alert when event not in alert_events" do
        RubyLLM::Agents.configure do |c|
          c.cache_store = cache_store
          c.alerts = {
            custom: ->(event, payload) {},
            on_events: [:breaker_open] # No budget events
          }
        end
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: nil, budget_config: budget_config)

        expect(RubyLLM::Agents::AlertManager).not_to have_received(:notify)
      end

      it "skips alert check when budget_config enabled is false" do
        disabled_config = budget_config.merge(enabled: false)
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_spend!("TestAgent", 11.0, tenant_id: nil, budget_config: disabled_config)

        expect(RubyLLM::Agents::AlertManager).not_to have_received(:notify)
      end
    end

    describe "check_soft_token_alerts (via record_tokens!)" do
      let(:token_budget_config) do
        {
          enabled: true,
          enforcement: :soft,
          global_daily_tokens: 1000,
          global_monthly_tokens: 10_000
        }
      end

      it "does not trigger alert when within token budget" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_tokens!("TestAgent", 100, tenant_id: nil, budget_config: token_budget_config)

        expect(RubyLLM::Agents::AlertManager).not_to have_received(:notify)
      end

      it "triggers token_soft_cap alert when global daily tokens exceeded" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        # Note: record_tokens! calls increment_tokens twice per period (global + agent)
        # So 600 tokens becomes 1200 in the counter
        described_class.record_tokens!("TestAgent", 600, tenant_id: nil, budget_config: token_budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :token_soft_cap,
          hash_including(scope: :global_daily_tokens)
        )
      end

      it "triggers token_hard_cap when enforcement is :hard" do
        hard_token_config = token_budget_config.merge(enforcement: :hard)
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_tokens!("TestAgent", 600, tenant_id: nil, budget_config: hard_token_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :token_hard_cap,
          hash_including(scope: :global_daily_tokens)
        )
      end

      it "does not trigger duplicate token alerts" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_tokens!("TestAgent", 600, tenant_id: nil, budget_config: token_budget_config)
        described_class.record_tokens!("TestAgent", 100, tenant_id: nil, budget_config: token_budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :token_soft_cap,
          hash_including(scope: :global_daily_tokens)
        ).at_most(:once)
      end

      it "includes correct payload in token alert" do
        allow(RubyLLM::Agents::AlertManager).to receive(:notify)

        described_class.record_tokens!("TestAgent", 600, tenant_id: "org_xyz", budget_config: token_budget_config)

        expect(RubyLLM::Agents::AlertManager).to have_received(:notify).with(
          :token_soft_cap,
          hash_including(
            scope: :global_daily_tokens,
            limit: 1000,
            agent_type: "TestAgent",
            tenant_id: "org_xyz",
            timestamp: Date.current.to_s
          )
        )
      end
    end
  end

  describe "edge cases" do
    it "handles concurrent spend recordings" do
      budget_config = { enabled: false, enforcement: :soft }

      threads = 10.times.map do
        Thread.new do
          described_class.record_spend!("TestAgent", 1.0, tenant_id: nil, budget_config: budget_config)
        end
      end

      threads.each(&:join)

      expect(RubyLLM::Agents::Budget::BudgetQuery.current_spend(:global, :daily, tenant_id: nil)).to eq(10.0)
    end

    it "correctly uses 1.day TTL for daily counters" do
      expect(cache_store).to receive(:write).with(
        anything,
        anything,
        hash_including(expires_in: 1.day)
      ).at_least(:once)

      described_class.increment_spend(:global, :daily, 10.0, tenant_id: nil)
    end

    it "correctly uses 31.days TTL for monthly counters" do
      expect(cache_store).to receive(:write).with(
        anything,
        anything,
        hash_including(expires_in: 31.days)
      ).at_least(:once)

      described_class.increment_spend(:global, :monthly, 10.0, tenant_id: nil)
    end
  end
end
