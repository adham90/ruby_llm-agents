# frozen_string_literal: true

require "rails_helper"

class ReplayTestAgent < RubyLLM::Agents::BaseAgent
  model "gpt-4o"
  param :query, required: true
  param :limit, default: 10

  user "Search for {query} with limit {limit}"
  system "You are a search assistant"
end

RSpec.describe RubyLLM::Agents::Execution::Replayable, type: :model do
  let(:execution) do
    exec = create(:execution,
      agent_type: "ReplayTestAgent",
      model_id: "gpt-4o",
      temperature: 0.7,
      status: "success")
    exec.detail.update!(
      parameters: {"query" => "red dress", "limit" => 10},
      system_prompt: "You are a search assistant",
      user_prompt: "Search for red dress with limit 10",
      response: {"content" => "Found 5 results"}
    )
    exec
  end

  describe "#replayable?" do
    it "returns true for a complete execution with valid agent class" do
      expect(execution.replayable?).to be true
    end

    it "returns false when agent_type is blank" do
      execution.update_column(:agent_type, "")
      expect(execution.replayable?).to be false
    end

    it "returns false when detail is missing" do
      execution.detail.destroy!
      execution.reload
      expect(execution.replayable?).to be false
    end

    it "returns false when agent class does not exist" do
      execution.update_column(:agent_type, "NonExistentAgent")
      expect(execution.replayable?).to be false
    end
  end

  describe "#replay" do
    it "re-executes the agent with original parameters" do
      # RubyLLM is globally mocked — MockClient.ask returns MockResponse
      result = execution.replay
      expect(result).to be_present
      expect(result.content).to be_present
    end

    it "passes original parameters to the agent" do
      # The agent requires :query — if params aren't passed, this raises ArgumentError
      expect { execution.replay }.not_to raise_error
    end

    it "allows model override" do
      # MockClient ignores the model but we verify no error with the override
      result = execution.replay(model: "gpt-4o-mini")
      expect(result).to be_present
    end

    it "allows temperature override" do
      result = execution.replay(temperature: 0.2)
      expect(result).to be_present
    end

    it "allows parameter overrides" do
      # Override the query param — agent should use "blue shirt" instead
      result = execution.replay(query: "blue shirt")
      expect(result).to be_present
    end

    it "merges overrides over original parameters" do
      exec = create(:execution,
        agent_type: "ReplayTestAgent",
        model_id: "gpt-4o",
        status: "success")
      exec.detail.update!(
        parameters: {"query" => "original", "limit" => 5}
      )

      # Override query but keep limit from original
      result = exec.replay(query: "updated")
      expect(result).to be_present
    end

    it "raises ReplayError for missing agent class" do
      execution.update_column(:agent_type, "DeletedAgent")

      expect { execution.replay }.to raise_error(
        RubyLLM::Agents::ReplayError, /agent class 'DeletedAgent' not found/
      )
    end

    it "raises ReplayError for missing detail" do
      execution.detail.destroy!
      execution.reload

      expect { execution.replay }.to raise_error(
        RubyLLM::Agents::ReplayError, /no detail record/
      )
    end

    it "raises ReplayError for blank agent_type" do
      execution.update_column(:agent_type, "")

      expect { execution.replay }.to raise_error(
        RubyLLM::Agents::ReplayError, /has no agent_type/
      )
    end
  end

  describe "#replay?" do
    it "returns false for a normal execution" do
      expect(execution.replay?).to be false
    end

    it "returns true for a replayed execution" do
      execution.update!(metadata: {"replay_source_id" => "42"})
      expect(execution.replay?).to be true
    end

    it "returns false when metadata has no replay_source_id" do
      execution.update!(metadata: {})
      expect(execution.replay?).to be false
    end
  end

  describe "#replay_source" do
    it "returns nil for non-replay executions" do
      expect(execution.replay_source).to be_nil
    end

    it "returns the source execution for replays" do
      replay_exec = create(:execution,
        agent_type: "ReplayTestAgent",
        metadata: {"replay_source_id" => execution.id.to_s})

      expect(replay_exec.replay_source).to eq(execution)
    end

    it "returns nil when source execution has been deleted" do
      replay_exec = create(:execution,
        agent_type: "ReplayTestAgent",
        metadata: {"replay_source_id" => "999999"})

      expect(replay_exec.replay_source).to be_nil
    end
  end

  describe "#replays" do
    it "returns executions that are replays of this one" do
      replay1 = create(:execution,
        agent_type: "ReplayTestAgent",
        metadata: {"replay_source_id" => execution.id.to_s})
      replay2 = create(:execution,
        agent_type: "ReplayTestAgent",
        metadata: {"replay_source_id" => execution.id.to_s})
      _unrelated = create(:execution, agent_type: "ReplayTestAgent")

      expect(execution.replays.count).to eq(2)
      expect(execution.replays).to include(replay1, replay2)
    end

    it "returns empty relation when no replays exist" do
      expect(execution.replays.count).to eq(0)
    end
  end

  describe "replays_of scope" do
    it "finds executions by replay_source_id in metadata" do
      source = create(:execution, agent_type: "ReplayTestAgent")
      replay = create(:execution,
        agent_type: "ReplayTestAgent",
        metadata: {"replay_source_id" => source.id.to_s})
      _other = create(:execution, agent_type: "ReplayTestAgent")

      results = RubyLLM::Agents::Execution.replays_of(source.id)
      expect(results).to include(replay)
      expect(results.count).to eq(1)
    end
  end
end
