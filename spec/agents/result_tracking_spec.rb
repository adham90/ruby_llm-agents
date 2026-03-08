# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Result tracking integration" do
  describe "agent_class_name" do
    it "stores agent_class_name when provided" do
      result = RubyLLM::Agents::Result.new(
        content: "test",
        input_tokens: 100,
        output_tokens: 50,
        agent_class_name: "MyAgent"
      )
      expect(result.agent_class_name).to eq("MyAgent")
    end

    it "defaults to nil when not provided" do
      result = RubyLLM::Agents::Result.new(content: "test", input_tokens: 10, output_tokens: 5)
      expect(result.agent_class_name).to be_nil
    end
  end

  describe "tracker registration" do
    it "registers with active tracker on creation" do
      tracker = RubyLLM::Agents::Tracker.new
      Thread.current[:ruby_llm_agents_tracker] = tracker

      result = RubyLLM::Agents::Result.new(content: "test", input_tokens: 10, output_tokens: 5)
      expect(tracker.results).to eq([result])
    ensure
      Thread.current[:ruby_llm_agents_tracker] = nil
    end

    it "does nothing when no tracker is active" do
      Thread.current[:ruby_llm_agents_tracker] = nil

      result = RubyLLM::Agents::Result.new(content: "test", input_tokens: 10, output_tokens: 5)
      expect(result).to be_a(RubyLLM::Agents::Result)
    end

    it "registers subclass results with tracker" do
      tracker = RubyLLM::Agents::Tracker.new
      Thread.current[:ruby_llm_agents_tracker] = tracker

      result = RubyLLM::Agents::EmbeddingResult.new(
        vectors: [[0.1, 0.2, 0.3]],
        input_tokens: 10,
        model_id: "text-embedding-3-small"
      )
      expect(tracker.results).to eq([result])
    ensure
      Thread.current[:ruby_llm_agents_tracker] = nil
    end

    it "registers multiple results in order" do
      tracker = RubyLLM::Agents::Tracker.new
      Thread.current[:ruby_llm_agents_tracker] = tracker

      r1 = RubyLLM::Agents::Result.new(content: "first", input_tokens: 10, output_tokens: 5)
      r2 = RubyLLM::Agents::Result.new(content: "second", input_tokens: 20, output_tokens: 10)

      expect(tracker.results).to eq([r1, r2])
    ensure
      Thread.current[:ruby_llm_agents_tracker] = nil
    end
  end

  describe "agent_class_name in to_h" do
    it "includes agent_class_name in hash output" do
      result = RubyLLM::Agents::Result.new(
        content: "test",
        input_tokens: 10,
        output_tokens: 5,
        agent_class_name: "SearchAgent"
      )
      expect(result.to_h).to include(agent_class_name: "SearchAgent")
    end
  end
end
