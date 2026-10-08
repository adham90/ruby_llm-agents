# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution::Breakdown do
  let(:execution_class) { RubyLLM::Agents::Execution }

  def cost(input)
    {input_cost: input, output_cost: 0}
  end

  before do
    create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o", duration_ms: 1000,
      input_tokens: 100, output_tokens: 0, **cost(1.0))
    create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o", duration_ms: 3000,
      input_tokens: 300, output_tokens: 0, **cost(3.0))
    create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o", chosen_model_id: "gpt-4o-mini",
      duration_ms: 500, input_tokens: 50, output_tokens: 0, **cost(0.5))
    create(:execution, :failed, agent_type: "SummaryAgent", model_id: "claude-sonnet", error_class: "Net::ReadTimeout",
      duration_ms: 200, input_tokens: 10, output_tokens: 0, **cost(0.2))
    create(:execution, :failed, agent_type: "SummaryAgent", model_id: "claude-sonnet", error_class: "Net::ReadTimeout",
      duration_ms: 400, input_tokens: 10, output_tokens: 0, **cost(0.4))
    create(:execution, :failed, agent_type: "SearchAgent", model_id: "gpt-4o", error_class: "JSON::ParserError",
      duration_ms: 100, input_tokens: 10, output_tokens: 0, **cost(0.1))
    create(:execution, :timeout, agent_type: "SummaryAgent", model_id: "claude-sonnet",
      duration_ms: nil, input_tokens: 0, output_tokens: 0, total_tokens: 0, **cost(0))
    create(:execution, agent_type: "SummaryAgent", model_id: "claude-sonnet", cache_hit: true,
      duration_ms: 10, input_tokens: 0, output_tokens: 0, total_tokens: 0, **cost(0))
  end

  subject(:breakdown) { execution_class.breakdown }

  it "reads the scope with a single query" do
    queries = capture_sql do
      result = execution_class.breakdown
      result.totals
      result.agent_stats
      result.model_stats
      result.configured_model_usage
      result.top_errors
      result.error_cost
      result.cache_savings
    end

    expect(queries.size).to eq(1)
  end

  it "respects the scope it is called on" do
    expect(execution_class.where(agent_type: "SummaryAgent").breakdown.totals[:total]).to eq(4)
    expect(execution_class.where("created_at < ?", 1.day.ago).breakdown.totals[:total]).to eq(0)
  end

  describe "#totals" do
    it "sums counts, cost and tokens and splits them by status" do
      expect(breakdown.totals).to include(
        total: 8, success: 4, errors: 3, timeouts: 1, tokens: 480
      )
      expect(breakdown.totals[:cost]).to be_within(1e-9).of(5.2)
    end

    it "averages duration over the executions that have one" do
      # 1000 + 3000 + 500 + 200 + 400 + 100 + 10 over 7 rows; the timeout has none
      expect(breakdown.totals[:avg_duration_ms]).to eq(5210 / 7)
    end

    it "reports success and error rates as percentages" do
      expect(breakdown.totals[:success_rate]).to eq(50.0)
      expect(breakdown.totals[:error_rate]).to eq(50.0)
    end

    it "reports the most recent execution as a Time" do
      expect(breakdown.totals[:last_seen]).to be_within(5.seconds).of(Time.current)
      expect(breakdown.totals[:last_seen]).to respond_to(:to_time)
    end

    it "is all zeros for an empty scope" do
      empty = execution_class.none.breakdown

      expect(empty.totals).to include(total: 0, cost: 0, tokens: 0, avg_duration_ms: 0,
        success_rate: 0.0, error_rate: 0.0, last_seen: nil)
    end
  end

  describe "#agent_stats" do
    it "matches a per-agent aggregate" do
      stats = breakdown.agent_stats

      expect(stats.keys).to contain_exactly("SearchAgent", "SummaryAgent")
      expect(stats["SearchAgent"]).to include(count: 4, total_tokens: 460, success_rate: 75.0)
      expect(stats["SearchAgent"][:total_cost]).to be_within(1e-9).of(4.6)
      expect(stats["SearchAgent"][:avg_cost]).to be_within(1e-6).of(1.15)
      expect(stats["SearchAgent"][:avg_duration_ms]).to eq(4600 / 4)
      expect(stats["SummaryAgent"]).to include(count: 4, success_rate: 25.0)
    end
  end

  describe "#model_stats" do
    it "bills a fallback's spend to the model that actually ran" do
      stats = breakdown.model_stats.index_by { |m| m[:model_id] }

      expect(stats.keys).to contain_exactly("gpt-4o", "gpt-4o-mini", "claude-sonnet")
      expect(stats["gpt-4o-mini"]).to include(executions: 1, total_tokens: 50)
      expect(stats["gpt-4o"][:executions]).to eq(3)
      expect(stats["gpt-4o"][:total_cost]).to be_within(1e-9).of(4.1)
    end

    it "sorts by cost and reports each model's share" do
      stats = breakdown.model_stats

      expect(stats.map { |m| m[:model_id] }).to eq(%w[gpt-4o claude-sonnet gpt-4o-mini])
      expect(stats.first[:cost_percentage]).to eq((4.1 / 5.2 * 100).round(1))
      expect(stats.first[:cost_per_1k_tokens]).to eq((4.1 / 410 * 1000).round(4))
    end
  end

  describe "#configured_model_usage" do
    it "groups on the model the agent asked for" do
      usage = breakdown.configured_model_usage.index_by { |m| m[:model_id] }

      expect(usage.keys).to contain_exactly("gpt-4o", "claude-sonnet")
      expect(usage["gpt-4o"]).to include(runs: 4, tokens: 460)
      expect(usage["gpt-4o"][:cost_per_run]).to be_within(1e-9).of(4.6 / 4)
    end
  end

  describe "#top_errors" do
    it "ranks error classes by frequency, ignoring timeouts" do
      errors = breakdown.top_errors

      expect(errors.map { |e| [e[:error_class], e[:count]] })
        .to eq([["Net::ReadTimeout", 2], ["JSON::ParserError", 1]])
      expect(errors.first[:percentage]).to eq(66.7)
      expect(errors.first[:last_seen]).to be_within(5.seconds).of(Time.current)
    end

    it "honours the limit" do
      expect(breakdown.top_errors(limit: 1).size).to eq(1)
    end

    it "labels errors recorded without a class" do
      create(:execution, status: "error", error_class: nil)

      expect(execution_class.breakdown.top_errors.map { |e| e[:error_class] }).to include("Unknown Error")
    end
  end

  describe "#error_cost" do
    it "totals what failed executions cost and lists the costliest pairs" do
      error_cost = breakdown.error_cost

      expect(error_cost[:total_count]).to eq(3)
      expect(error_cost[:total_cost]).to be_within(1e-9).of(0.7)
      expect(error_cost[:breakdown].map { |e| [e[:error_class], e[:agent_type], e[:count]] })
        .to eq([["Net::ReadTimeout", "SummaryAgent", 2], ["JSON::ParserError", "SearchAgent", 1]])
      expect(error_cost[:breakdown].first[:cost]).to be_within(1e-9).of(0.6)
    end
  end

  describe "#cache_savings" do
    it "estimates each hit at the mean cost of a miss" do
      savings = breakdown.cache_savings

      expect(savings).to include(count: 1, hit_rate: 12.5, total_executions: 8)
      expect(savings[:estimated_savings]).to be_within(1e-6).of(5.2 / 7)
    end

    it "is empty for an empty scope" do
      expect(execution_class.none.breakdown.cache_savings)
        .to eq(count: 0, estimated_savings: 0, hit_rate: 0, total_executions: 0)
    end
  end

  describe "#for_agents" do
    it "narrows every figure to the named agents" do
      narrowed = breakdown.for_agents(%w[SummaryAgent])

      expect(narrowed.totals[:total]).to eq(4)
      expect(narrowed.agent_stats.keys).to eq(%w[SummaryAgent])
      expect(narrowed.model_stats.map { |m| m[:model_id] }).to eq(%w[claude-sonnet])
    end

    it "merges an agent's previous names" do
      expect(breakdown.for_agents(%w[SearchAgent SummaryAgent]).totals[:total]).to eq(8)
    end
  end

  describe "#rows" do
    it "rebuilds an identical breakdown, including across a cache round trip" do
      store = ActiveSupport::Cache::MemoryStore.new
      store.write("breakdown", breakdown.rows)
      rebuilt = described_class.new(store.read("breakdown"))

      expect(rebuilt.totals).to eq(breakdown.totals)
      expect(rebuilt.model_stats).to eq(breakdown.model_stats)
      expect(rebuilt.top_errors).to eq(breakdown.top_errors)
    end
  end

  describe "the aggregations built on it" do
    it "agree with the breakdown for the same scope" do
      scope = execution_class.where(agent_type: "SearchAgent")

      expect(execution_class.model_stats(scope: scope)).to eq(scope.breakdown.model_stats)
      expect(execution_class.top_errors(scope: scope, limit: 3)).to eq(scope.breakdown.top_errors(limit: 3))
      expect(execution_class.cache_savings(scope: scope)).to eq(scope.breakdown.cache_savings)
      expect(execution_class.batch_agent_stats(scope: scope)).to eq(scope.breakdown.agent_stats)
    end
  end
end
