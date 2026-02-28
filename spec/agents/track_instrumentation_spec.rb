# frozen_string_literal: true

require "spec_helper"

# Test agent for instrumentation tests
class InstrumentTrackTestAgent < RubyLLM::Agents::BaseAgent
  model "gpt-4o"
  param :query, required: true

  user "Answer: {query}"
end

RSpec.describe "Track instrumentation integration" do
  before do
    setup_agent_mocks(content: "response", input_tokens: 100, output_tokens: 50)
  end

  describe "request_id injection" do
    it "sets request_id on execution records" do
      report = RubyLLM::Agents.track(request_id: "req_abc") do
        InstrumentTrackTestAgent.call(query: "hello")
      end

      expect(report).to be_successful
      expect(report.call_count).to eq(1)

      # The execution should have the request_id
      execution = RubyLLM::Agents::Execution.last
      expect(execution.request_id).to eq("req_abc")
    end

    it "auto-generates request_id when none provided" do
      RubyLLM::Agents.track do
        InstrumentTrackTestAgent.call(query: "hello")
      end

      execution = RubyLLM::Agents::Execution.last
      expect(execution.request_id).to start_with("track_")
    end

    it "sets same request_id on all executions in block" do
      RubyLLM::Agents.track(request_id: "req_multi") do
        InstrumentTrackTestAgent.call(query: "first")
        InstrumentTrackTestAgent.call(query: "second")
      end

      executions = RubyLLM::Agents::Execution.where(request_id: "req_multi")
      expect(executions.count).to eq(2)
    end
  end

  describe "tags injection" do
    it "merges tags into execution metadata" do
      RubyLLM::Agents.track(tags: {feature: "voice-chat", session_id: "sess_1"}) do
        InstrumentTrackTestAgent.call(query: "hello")
      end

      execution = RubyLLM::Agents::Execution.last
      metadata = execution.metadata || {}
      tags = metadata["tags"] || metadata[:tags]
      expect(tags).to include("feature" => "voice-chat")
      expect(tags).to include("session_id" => "sess_1")
    end
  end

  describe "request_id grouping" do
    it "allows querying executions by request_id" do
      RubyLLM::Agents.track(request_id: "group_test") do
        InstrumentTrackTestAgent.call(query: "a")
        InstrumentTrackTestAgent.call(query: "b")
      end

      # Also create one outside the track block
      InstrumentTrackTestAgent.call(query: "outside")

      grouped = RubyLLM::Agents::Execution.where(request_id: "group_test")
      expect(grouped.count).to eq(2)
    end
  end
end
