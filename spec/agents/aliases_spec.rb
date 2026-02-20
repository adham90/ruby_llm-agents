# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent aliases" do
  describe ".aliases DSL" do
    it "returns empty array by default" do
      klass = Class.new(RubyLLM::Agents::Base)
      expect(klass.aliases).to eq([])
    end

    it "stores declared aliases" do
      klass = Class.new(RubyLLM::Agents::Base) do
        aliases "OldName", "AncientName"
      end
      expect(klass.aliases).to eq(["OldName", "AncientName"])
    end

    it "converts symbols to strings" do
      klass = Class.new(RubyLLM::Agents::Base) do
        aliases :OldName
      end
      expect(klass.aliases).to eq(["OldName"])
    end
  end

  describe ".all_agent_names" do
    it "returns only current name when no aliases" do
      stub_const("PlainAgent", Class.new(RubyLLM::Agents::Base))
      expect(PlainAgent.all_agent_names).to eq(["PlainAgent"])
    end

    it "returns current name plus aliases" do
      stub_const("RenamedAgent", Class.new(RubyLLM::Agents::Base) {
        aliases "OriginalAgent", "MiddleName"
      })
      expect(RenamedAgent.all_agent_names).to eq(["RenamedAgent", "OriginalAgent", "MiddleName"])
    end

    it "deduplicates names" do
      stub_const("SameAgent", Class.new(RubyLLM::Agents::Base) {
        aliases "SameAgent"
      })
      expect(SameAgent.all_agent_names).to eq(["SameAgent"])
    end
  end

  describe "Execution.by_agent with aliases" do
    it "includes executions from aliased names" do
      stub_const("NewBot", Class.new(RubyLLM::Agents::Base) {
        aliases "OldBot"
      })

      old_exec = create(:execution, agent_type: "OldBot")
      new_exec = create(:execution, agent_type: "NewBot")
      other_exec = create(:execution, agent_type: "UnrelatedAgent")

      results = RubyLLM::Agents::Execution.by_agent(NewBot)
      expect(results).to include(old_exec, new_exec)
      expect(results).not_to include(other_exec)
    end

    it "works with string argument that resolves to a class with aliases" do
      stub_const("ResolvedAgent", Class.new(RubyLLM::Agents::Base) {
        aliases "LegacyAgent"
      })

      legacy = create(:execution, agent_type: "LegacyAgent")
      current = create(:execution, agent_type: "ResolvedAgent")

      results = RubyLLM::Agents::Execution.by_agent("ResolvedAgent")
      expect(results).to include(legacy, current)
    end

    it "works with plain string that has no class" do
      exec = create(:execution, agent_type: "NonexistentAgent")
      results = RubyLLM::Agents::Execution.by_agent("NonexistentAgent")
      expect(results).to include(exec)
    end
  end

  describe "Analytics with aliases" do
    it "stats_for includes aliased executions" do
      stub_const("CurrentAgent", Class.new(RubyLLM::Agents::Base) {
        aliases "PreviousAgent"
      })

      create(:execution, agent_type: "PreviousAgent")
      create(:execution, agent_type: "CurrentAgent")

      stats = RubyLLM::Agents::Execution.stats_for("CurrentAgent", period: :all_time)
      expect(stats[:count]).to eq(2)
    end
  end
end
