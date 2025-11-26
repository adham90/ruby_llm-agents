# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BudgetTracker do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
    cache_store.clear
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
  end
end
