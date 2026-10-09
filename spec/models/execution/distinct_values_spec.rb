# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution, ".distinct_values" do
  before do
    create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o", tenant_id: "acme")
    create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o-mini", tenant_id: "acme")
    create(:execution, agent_type: "SummaryAgent", model_id: "gpt-4o", tenant_id: nil)
    create(:execution, agent_type: "Billing::InvoiceAgent", model_id: "claude-sonnet", tenant_id: "globex")
  end

  it "returns each value once, sorted" do
    expect(described_class.distinct_values(:agent_type))
      .to eq(%w[Billing::InvoiceAgent SearchAgent SummaryAgent])
    expect(described_class.distinct_values(:model_id)).to eq(%w[claude-sonnet gpt-4o gpt-4o-mini])
  end

  it "leaves out nil" do
    expect(described_class.distinct_values(:tenant_id)).to eq(%w[acme globex])
  end

  it "accepts the column as a string" do
    expect(described_class.distinct_values("tenant_id")).to eq(%w[acme globex])
  end

  it "returns an empty list for an empty table" do
    described_class.delete_all

    expect(described_class.distinct_values(:agent_type)).to eq([])
  end

  it "agrees with a plain DISTINCT for every indexed dropdown column" do
    %i[agent_type model_id tenant_id].each do |column|
      expect(described_class.distinct_values(column))
        .to eq(described_class.where.not(column => nil).distinct.pluck(column).sort)
    end
  end

  it "walks the index instead of scanning with DISTINCT" do
    queries = capture_sql { described_class.distinct_values(:agent_type) }

    expect(queries.size).to eq(1)
    expect(queries.first).to match(/WITH RECURSIVE/)
    expect(queries.first).not_to match(/DISTINCT/)
  end

  it "probes the index once per distinct value, however many rows share it" do
    create_list(:execution, 20, agent_type: "SearchAgent")

    expect(described_class.distinct_values(:agent_type))
      .to eq(%w[Billing::InvoiceAgent SearchAgent SummaryAgent])
  end

  it "falls back to DISTINCT on a filtered relation, and honours the filter" do
    scope = described_class.where(tenant_id: "acme")
    queries = capture_sql { expect(scope.distinct_values(:model_id)).to eq(%w[gpt-4o gpt-4o-mini]) }

    expect(queries.first).to match(/SELECT DISTINCT/)
    expect(queries.first).to match(/tenant_id/)
  end

  it "falls back to DISTINCT on a joined relation" do
    queries = capture_sql do
      expect(described_class.joins(:detail).distinct_values(:model_id)).to eq(%w[claude-sonnet gpt-4o gpt-4o-mini])
    end

    expect(queries.first).to match(/SELECT DISTINCT/)
    expect(queries.first).to match(/INNER JOIN/)
  end

  it "falls back to DISTINCT for a column no index leads with" do
    create(:execution, finish_reason: "stop")
    create(:execution, finish_reason: "length")

    queries = capture_sql { expect(described_class.distinct_values(:finish_reason)).to eq(%w[length stop]) }

    expect(queries.first).to match(/SELECT DISTINCT/)
  end

  it "rejects anything that is not a column" do
    expect { described_class.distinct_values("agent_type; DROP TABLE users") }
      .to raise_error(ArgumentError, /Unknown column/)
  end
end
