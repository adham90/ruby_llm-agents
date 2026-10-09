# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AgentRegistry do
  describe ".all" do
    it "returns an array of agent type names" do
      expect(described_class.all).to be_an(Array)
    end

    it "includes agents from file system" do
      # TestAgent is defined in spec/dummy/app/agents/
      expect(described_class.all).to include("TestAgent")
    end

    it "includes agents from execution history" do
      create(:execution, agent_type: "HistoricalAgent")
      expect(described_class.all).to include("HistoricalAgent")
    end

    it "returns unique agent names" do
      create(:execution, agent_type: "TestAgent")
      result = described_class.all
      expect(result.count("TestAgent")).to eq(1)
    end

    it "returns sorted names" do
      # Compare one snapshot: the registry reads Class#descendants, and GC can
      # collect other specs' throwaway agent classes between two calls.
      result = described_class.all
      expect(result).to eq(result.sort)
    end
  end

  describe ".find" do
    it "returns agent class for existing agent" do
      result = described_class.find("TestAgent")
      expect(result).to eq(TestAgent)
    end

    it "returns nil for non-existent agent" do
      result = described_class.find("NonExistentAgent")
      expect(result).to be_nil
    end

    it "returns nil for invalid class name" do
      result = described_class.find("Not::A::Valid::Class")
      expect(result).to be_nil
    end
  end

  describe ".exists?" do
    it "returns true for existing agent" do
      expect(described_class.exists?("TestAgent")).to be true
    end

    it "returns false for non-existent agent" do
      expect(described_class.exists?("NonExistentAgent")).to be false
    end
  end

  describe ".all_with_details" do
    before do
      create(:execution, agent_type: "TestAgent", total_cost: 1.0)
    end

    it "returns array of agent info hashes" do
      result = described_class.all_with_details
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Hash)
    end

    it "includes required keys" do
      result = described_class.all_with_details.find { |a| a[:name] == "TestAgent" }
      expect(result).to include(
        :name,
        :class,
        :active,
        :version,
        :model,
        :execution_count,
        :total_cost
      )
    end

    it "includes stats for agents with executions" do
      result = described_class.all_with_details.find { |a| a[:name] == "TestAgent" }
      expect(result[:execution_count]).to be >= 1
    end

    it "computes stats for every agent with one grouped query" do
      create(:execution, agent_type: "OtherAgent")

      queries = capture_sql { described_class.all_with_details }

      grouped = queries.grep(/FROM "ruby_llm_agents_executions"/).grep(/GROUP BY/)
      expect(grouped.size).to eq(1)
      expect(queries.grep(/SUM\(/).size).to eq(1)
    end

    it "reports usage over the stats window" do
      create(:execution, :failed, agent_type: "TestAgent", input_cost: 0.5, output_cost: 0)
      create(:execution, agent_type: "TestAgent", created_at: (described_class::STATS_WINDOW + 5.days).ago)

      result = described_class.all_with_details.find { |a| a[:name] == "TestAgent" }

      expect(result[:execution_count]).to eq(2)
      expect(result[:total_cost]).to be_within(1e-6).of(1.5)
      expect(result[:success_rate]).to eq(50.0)
      expect(result[:error_rate]).to eq(50.0)
      expect(result[:last_executed]).to be_within(5.seconds).of(Time.current)
    end

    it "reports zero usage but the true last run for an agent idle since before the window" do
      last_run = (described_class::STATS_WINDOW + 10.days).ago
      create(:execution, agent_type: "DormantAgent", created_at: last_run)

      result = described_class.all_with_details.find { |a| a[:name] == "DormantAgent" }

      expect(result[:execution_count]).to eq(0)
      expect(result[:total_cost]).to eq(0)
      expect(result[:last_executed]).to be_within(1.second).of(last_run)
    end

    it "counts executions recorded under an agent's previous names" do
      stub_const("RenamedAgent", Class.new(RubyLLM::Agents::Base) { aliases "LegacyAgent" })
      create(:execution, agent_type: "RenamedAgent", input_cost: 1.0, output_cost: 0)
      create(:execution, agent_type: "LegacyAgent", input_cost: 2.0, output_cost: 0)

      result = described_class.all_with_details.find { |a| a[:name] == "RenamedAgent" }

      expect(result[:execution_count]).to eq(2)
      expect(result[:total_cost]).to be_within(1e-6).of(3.0)
    end

    it "leaves the stats nil, and still lists every agent, when the stats query is cancelled" do
      allow(RubyLLM::Agents::Execution).to receive(:breakdown)
        .and_raise(ActiveRecord::QueryCanceled, "canceling statement due to statement timeout")

      result = described_class.all_with_details.find { |a| a[:name] == "TestAgent" }

      expect(result[:active]).to be true
      expect(result[:execution_count]).to be_nil
      expect(result[:total_cost]).to be_nil
      expect(result[:last_executed]).to be_within(5.seconds).of(Time.current)
    end

    context "for inactive agents (deleted but have history)" do
      before do
        create(:execution, agent_type: "DeletedAgent")
      end

      it "marks inactive agents correctly" do
        result = described_class.all_with_details.find { |a| a[:name] == "DeletedAgent" }
        expect(result[:active]).to be false
        expect(result[:class]).to be_nil
      end
    end
  end

  describe "error handling" do
    context "when database query fails" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:distinct_values)
          .and_raise(StandardError.new("Database error"))
      end

      it "returns empty array for execution_agents" do
        # Should not raise and should return agents from file system only
        expect { described_class.all }.not_to raise_error
        expect(described_class.all).to include("TestAgent")
      end
    end

    context "when agent file fails to load" do
      it "logs error but continues" do
        # Create a temporary file that will fail to load
        allow(Dir).to receive(:glob).and_return(["/nonexistent/broken_agent.rb"])
        allow(Rails.root).to receive(:join).and_return(Pathname.new("/nonexistent"))
        allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)

        # The require_dependency will fail for the nonexistent file (once per directory)
        expect(Rails.logger).to receive(:error).with(/Failed to load file/).at_least(:once)
        described_class.send(:eager_load_agents!)
      end
    end
  end
end
