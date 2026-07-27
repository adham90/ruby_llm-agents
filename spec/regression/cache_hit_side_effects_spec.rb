# frozen_string_literal: true

require "rails_helper"

# A cache hit hands a result back to the caller without ever running
# Result#initialize — the object is deserialized, then duped. Two things that
# normally happen at that moment therefore did not: the result never registered
# with an active Tracker (so TrackReport#call_count under-reported), and a
# streaming agent's block never fired (so the stream went silent even though
# the content was in the return value).
RSpec.describe "cache hit side effects" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
      c.cache_store = ActiveSupport::Cache::MemoryStore.new
    end
    RubyLLM::Agents::Execution.delete_all
  end

  after { RubyLLM::Agents.reset_configuration! }

  def stub_chat(&ask)
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    if ask
      allow(client).to receive(:ask, &ask)
    else
      allow(client).to receive(:ask).and_return(
        RubyLLM::Message.new(role: :assistant, content: "hello",
          input_tokens: 100, output_tokens: 50, model_id: "gpt-4.1")
      )
    end
    allow(RubyLLM).to receive(:chat).and_return(client)
  end

  describe "RubyLLM::Agents.track" do
    let(:agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        def self.name = "TrackedCacheAgent"

        model "gpt-4.1"
        prompt "hi"
        cache_for 300
      end
    end

    before { stub_chat }

    it "counts every call, including the ones served from cache" do
      report = RubyLLM::Agents.track { 3.times { agent_class.call } }

      expect(report.call_count).to eq(3)
      expect(report.cached_count).to eq(2)
      expect(report.billable_count).to eq(1)
    end

    it "bills only the call that hit a provider" do
      report = RubyLLM::Agents.track { 3.times { agent_class.call } }

      expect(report.total_cost).to be_within(1e-9).of(RubyLLM::Agents::Execution.sum(:total_cost).to_f)
      expect(report.total_tokens).to eq(150)
    end

    it "reports what the cached calls would have cost" do
      report = RubyLLM::Agents.track { 3.times { agent_class.call } }

      expect(report.cache_savings).to be_within(1e-9).of(report.total_cost * 2)
    end

    it "marks cached entries in the cost breakdown" do
      report = RubyLLM::Agents.track { 2.times { agent_class.call } }

      expect(report.cost_breakdown.map { |r| r[:cached] }).to eq([false, true])
      expect(report.cost_breakdown.last[:cost]).to eq(0)
    end

    it "still totals correctly when nothing is cached" do
      uncached = Class.new(RubyLLM::Agents::Base) do
        def self.name = "UncachedTrackAgent"
        model "gpt-4.1"
        prompt "hi"
      end

      report = RubyLLM::Agents.track { 2.times { uncached.call } }

      expect(report.billable_count).to eq(2)
      expect(report.cached_count).to eq(0)
      expect(report.cache_savings).to eq(0)
    end
  end

  describe "streaming" do
    let(:streaming_agent) do
      Class.new(RubyLLM::Agents::Base) do
        def self.name = "StreamingCacheAgent"

        model "gpt-4.1"
        prompt "hi"
        cache_for 300
        streaming true
      end
    end

    before do
      stub_chat do |_prompt, **_opts, &block|
        block&.call(double("Chunk", content: "he"))
        block&.call(double("Chunk", content: "llo"))
        RubyLLM::Message.new(role: :assistant, content: "hello",
          input_tokens: 10, output_tokens: 5, model_id: "gpt-4.1")
      end
    end

    it "replays the cached response through the caller's block" do
      streaming_agent.call { |_c| }

      chunks = []
      streaming_agent.call { |c| chunks << c.content }

      expect(chunks.join).to eq("hello")
    end

    it "streams normally on the first, uncached call" do
      chunks = []
      streaming_agent.call { |c| chunks << c.content }

      expect(chunks).to eq(["he", "llo"])
    end

    it "does not raise when no block was given" do
      streaming_agent.call

      expect { streaming_agent.call }.not_to raise_error
    end
  end
end
