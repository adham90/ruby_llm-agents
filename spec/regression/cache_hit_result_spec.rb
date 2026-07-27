# frozen_string_literal: true

require "rails_helper"

# A cache hit used to return the stored Result verbatim: no way to tell it was
# cached, the original call's execution_id (so it could not be correlated with
# the execution row just written), and the original's cost replayed — so
# summing #total_cost across calls double-counted spend that never happened.
# The image agents already solved this with a distinct Cached*Result class; the
# pipeline cache path had no equivalent.
RSpec.describe "cache hit result" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
      c.cache_store = ActiveSupport::Cache::MemoryStore.new
    end
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "CacheHitAgent"

      model "gpt-4.1"
      prompt "hi"
      cache_for 300
    end
  end

  before do
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask).and_return(
      RubyLLM::Message.new(role: :assistant, content: "hello",
        input_tokens: 100, output_tokens: 50, model_id: "gpt-4.1")
    )
    allow(RubyLLM).to receive(:chat).and_return(client)
  end

  it "reports a fresh result as not cached" do
    expect(agent_class.call.cached?).to be false
  end

  it "reports a replayed result as cached" do
    agent_class.call

    expect(agent_class.call.cached?).to be true
  end

  it "points execution_id at the row written for this call, not the original" do
    first = agent_class.call
    second = agent_class.call

    expect(second.execution_id).not_to eq(first.execution_id)
    expect(second.execution_id).to eq(RubyLLM::Agents::Execution.order(:id).last.id)
  end

  it "exposes when the response was originally produced" do
    agent_class.call

    expect(agent_class.call.cached_at).to be_present
  end

  it "lets a caller aggregate spend without double-counting" do
    results = [agent_class.call, agent_class.call]

    billed = results.reject(&:cached?).sum { |r| r.total_cost.to_f }

    expect(results.sum { |r| r.total_cost.to_f }).to be > billed
    expect(billed).to be_within(1e-9).of(RubyLLM::Agents::Execution.sum(:total_cost).to_f)
  end

  it "does not mutate the stored entry, so repeated hits stay consistent" do
    agent_class.call
    2.times { expect(agent_class.call.cached?).to be true }
  end

  it "returns the value untouched when it cannot be marked" do
    middleware = RubyLLM::Agents::Pipeline::Middleware::Cache.new(->(c) { c }, agent_class)
    context = RubyLLM::Agents::Pipeline::Context.new(input: "x", agent_class: agent_class)

    expect(middleware.send(:mark_cached, "a bare string", context)).to eq("a bare string")
  end
end
