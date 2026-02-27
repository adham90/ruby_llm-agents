# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Agents::Tracker do
  describe "#initialize" do
    it "starts with empty results" do
      tracker = described_class.new
      expect(tracker.results).to eq([])
    end

    it "generates a request_id when none provided" do
      tracker = described_class.new
      expect(tracker.request_id).to start_with("track_")
      expect(tracker.request_id.length).to be > 10
    end

    it "uses provided request_id" do
      tracker = described_class.new(request_id: "req_123")
      expect(tracker.request_id).to eq("req_123")
    end

    it "stores defaults" do
      tracker = described_class.new(defaults: {tenant: "user_1"})
      expect(tracker.defaults).to eq({tenant: "user_1"})
    end

    it "defaults to empty defaults hash" do
      tracker = described_class.new
      expect(tracker.defaults).to eq({})
    end

    it "stores tags" do
      tracker = described_class.new(tags: {feature: "voice-chat"})
      expect(tracker.tags).to eq({feature: "voice-chat"})
    end

    it "defaults to empty tags hash" do
      tracker = described_class.new
      expect(tracker.tags).to eq({})
    end
  end

  describe "#<<" do
    it "collects results pushed to it" do
      tracker = described_class.new
      result = RubyLLM::Agents::Result.new(content: "test", total_cost: 0.01, input_tokens: 100, output_tokens: 50)
      tracker << result
      expect(tracker.results).to eq([result])
    end

    it "maintains insertion order" do
      tracker = described_class.new
      r1 = RubyLLM::Agents::Result.new(content: "first", input_tokens: 10, output_tokens: 5)
      r2 = RubyLLM::Agents::Result.new(content: "second", input_tokens: 20, output_tokens: 10)
      r3 = RubyLLM::Agents::Result.new(content: "third", input_tokens: 30, output_tokens: 15)

      tracker << r1
      tracker << r2
      tracker << r3

      expect(tracker.results).to eq([r1, r2, r3])
    end
  end

  describe "unique request_ids" do
    it "generates different request_ids for different trackers" do
      ids = 10.times.map { described_class.new.request_id }
      expect(ids.uniq.size).to eq(10)
    end
  end
end
