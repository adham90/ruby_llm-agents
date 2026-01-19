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
      expect(described_class.all).to eq(described_class.all.sort)
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
        allow(RubyLLM::Agents::Execution).to receive(:distinct)
          .and_raise(StandardError.new("Database error"))
      end

      it "returns empty array for execution_agents" do
        # Should not raise and should return agents from file system only
        expect { described_class.all }.not_to raise_error
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
