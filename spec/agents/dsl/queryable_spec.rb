# frozen_string_literal: true

require "rails_helper"

# Define test agent classes outside the RSpec block so they're real constants
unless defined?(QueryTestAgent)
  class QueryTestAgent < RubyLLM::Agents::BaseAgent
    model "gpt-4o"
    param :query, required: true

    user "Search for {query}"
    system "You are a search assistant"
  end
end

unless defined?(OtherQueryTestAgent)
  class OtherQueryTestAgent < RubyLLM::Agents::BaseAgent
    model "gpt-4o-mini"
    param :topic, required: true

    user "Tell me about {topic}"
  end
end

RSpec.describe RubyLLM::Agents::DSL::Queryable do
  # ── Phase 1: .executions ──────────────────────────────────────────────

  describe ".executions" do
    it "returns an ActiveRecord::Relation" do
      expect(QueryTestAgent.executions).to be_a(ActiveRecord::Relation)
    end

    it "scopes to the agent type" do
      create(:execution, agent_type: "QueryTestAgent")
      create(:execution, agent_type: "QueryTestAgent")
      create(:execution, agent_type: "OtherQueryTestAgent")

      expect(QueryTestAgent.executions.count).to eq(2)
      expect(OtherQueryTestAgent.executions.count).to eq(1)
    end

    it "chains with status scopes" do
      create(:execution, agent_type: "QueryTestAgent", status: "success")
      create(:execution, agent_type: "QueryTestAgent", status: "error")
      create(:execution, agent_type: "QueryTestAgent", status: "timeout")

      expect(QueryTestAgent.executions.successful.count).to eq(1)
      expect(QueryTestAgent.executions.failed.count).to eq(2)
    end

    it "chains with time-based scopes" do
      create(:execution, agent_type: "QueryTestAgent", created_at: Time.current)
      create(:execution, agent_type: "QueryTestAgent", created_at: 2.days.ago,
        started_at: 2.days.ago, completed_at: 2.days.ago)

      expect(QueryTestAgent.executions.today.count).to eq(1)
    end

    it "chains with performance scopes" do
      create(:execution, agent_type: "QueryTestAgent", input_cost: 1.00, output_cost: 1.00)
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.005, output_cost: 0.005)

      expect(QueryTestAgent.executions.expensive(1.00).count).to eq(1)
    end

    it "chains with aggregation methods" do
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.75, output_cost: 0.75)
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.25, output_cost: 0.25)

      expect(QueryTestAgent.executions.total_cost_sum).to eq(2.00)
    end

    it "supports tenant scoping" do
      create(:execution, agent_type: "QueryTestAgent", tenant_id: "acme")
      create(:execution, agent_type: "QueryTestAgent", tenant_id: "beta")

      expect(QueryTestAgent.executions.by_tenant("acme").count).to eq(1)
    end

    it "returns empty relation when no executions exist" do
      expect(QueryTestAgent.executions.count).to eq(0)
      expect(QueryTestAgent.executions.to_a).to eq([])
    end

    it "does not include executions from other agents" do
      create(:execution, agent_type: "OtherQueryTestAgent")

      expect(QueryTestAgent.executions.count).to eq(0)
    end
  end

  # ── Phase 2: Convenience Methods ──────────────────────────────────────

  describe ".last_run" do
    it "returns the most recent execution" do
      create(:execution, agent_type: "QueryTestAgent", created_at: 1.hour.ago,
        started_at: 1.hour.ago, completed_at: 1.hour.ago)
      recent = create(:execution, agent_type: "QueryTestAgent", created_at: Time.current)

      expect(QueryTestAgent.last_run).to eq(recent)
    end

    it "returns nil when no executions exist" do
      expect(QueryTestAgent.last_run).to be_nil
    end

    it "only returns executions for this agent" do
      create(:execution, agent_type: "OtherQueryTestAgent", created_at: Time.current)

      expect(QueryTestAgent.last_run).to be_nil
    end
  end

  describe ".failures" do
    it "returns recent failed executions" do
      create(:execution, agent_type: "QueryTestAgent", status: "error")
      create(:execution, agent_type: "QueryTestAgent", status: "timeout")
      create(:execution, agent_type: "QueryTestAgent", status: "success")

      expect(QueryTestAgent.failures.count).to eq(2)
    end

    it "respects the since parameter" do
      create(:execution, agent_type: "QueryTestAgent", status: "error",
        created_at: 2.days.ago, started_at: 2.days.ago, completed_at: 2.days.ago)
      create(:execution, agent_type: "QueryTestAgent", status: "error",
        created_at: 1.hour.ago, started_at: 1.hour.ago, completed_at: 1.hour.ago)

      expect(QueryTestAgent.failures(since: 24.hours).count).to eq(1)
      expect(QueryTestAgent.failures(since: 7.days).count).to eq(2)
    end

    it "does not include successful executions" do
      create(:execution, agent_type: "QueryTestAgent", status: "success")

      expect(QueryTestAgent.failures.count).to eq(0)
    end
  end

  describe ".total_spent" do
    it "returns total cost for the agent" do
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.75, output_cost: 0.75)
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.25, output_cost: 0.25)
      create(:execution, agent_type: "OtherQueryTestAgent", input_cost: 50.00, output_cost: 50.00)

      expect(QueryTestAgent.total_spent).to eq(2.00)
    end

    it "filters by time window" do
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.50, output_cost: 0.50,
        created_at: 2.days.ago, started_at: 2.days.ago, completed_at: 2.days.ago)
      create(:execution, agent_type: "QueryTestAgent", input_cost: 0.25, output_cost: 0.25,
        created_at: 1.hour.ago, started_at: 1.hour.ago, completed_at: 1.hour.ago)

      expect(QueryTestAgent.total_spent(since: 24.hours)).to eq(0.50)
    end

    it "returns zero when no executions exist" do
      expect(QueryTestAgent.total_spent).to eq(0)
    end
  end

  describe ".stats" do
    it "returns a complete stats hash" do
      create(:execution, agent_type: "QueryTestAgent", status: "success",
        input_cost: 0.004, output_cost: 0.006, duration_ms: 500,
        input_tokens: 500, output_tokens: 500)
      create(:execution, agent_type: "QueryTestAgent", status: "success",
        input_cost: 0.008, output_cost: 0.012, duration_ms: 700,
        input_tokens: 750, output_tokens: 750)
      create(:execution, agent_type: "QueryTestAgent", status: "error",
        input_cost: 0.002, output_cost: 0.003, duration_ms: 200,
        input_tokens: 250, output_tokens: 250)

      result = QueryTestAgent.stats

      expect(result[:total]).to eq(3)
      expect(result[:successful]).to eq(2)
      expect(result[:failed]).to eq(1)
      expect(result[:success_rate]).to eq(66.7)
      expect(result[:total_cost]).to eq(0.035)
      expect(result[:total_tokens]).to eq(3000)
      expect(result[:avg_duration_ms]).to be_present
      expect(result[:avg_tokens]).to eq(1000)
    end

    it "returns zero stats when no executions exist" do
      result = QueryTestAgent.stats

      expect(result[:total]).to eq(0)
      expect(result[:success_rate]).to eq(0.0)
      expect(result[:total_cost]).to eq(0)
    end

    it "filters by time window" do
      create(:execution, agent_type: "QueryTestAgent", status: "success",
        input_cost: 0.40, output_cost: 0.60, created_at: 2.days.ago,
        started_at: 2.days.ago, completed_at: 2.days.ago)
      create(:execution, agent_type: "QueryTestAgent", status: "success",
        input_cost: 0.20, output_cost: 0.30, created_at: 1.hour.ago,
        started_at: 1.hour.ago, completed_at: 1.hour.ago)

      result = QueryTestAgent.stats(since: 24.hours)
      expect(result[:total]).to eq(1)
      expect(result[:total_cost]).to eq(0.50)
    end
  end

  describe ".cost_by_model" do
    it "returns cost breakdown by model" do
      create(:execution, agent_type: "QueryTestAgent", model_id: "gpt-4o",
        input_cost: 0.40, output_cost: 0.60)
      create(:execution, agent_type: "QueryTestAgent", model_id: "gpt-4o",
        input_cost: 0.80, output_cost: 1.20)
      create(:execution, agent_type: "QueryTestAgent", model_id: "gpt-4o-mini",
        input_cost: 0.04, output_cost: 0.06)

      result = QueryTestAgent.cost_by_model

      expect(result["gpt-4o"][:count]).to eq(2)
      expect(result["gpt-4o"][:total_cost]).to eq(3.00)
      expect(result["gpt-4o-mini"][:count]).to eq(1)
      expect(result["gpt-4o-mini"][:total_cost]).to eq(0.10)
    end

    it "returns empty hash when no executions exist" do
      expect(QueryTestAgent.cost_by_model).to eq({})
    end

    it "filters by time window" do
      create(:execution, agent_type: "QueryTestAgent", model_id: "gpt-4o",
        input_cost: 2.00, output_cost: 3.00, created_at: 2.days.ago,
        started_at: 2.days.ago, completed_at: 2.days.ago)
      create(:execution, agent_type: "QueryTestAgent", model_id: "gpt-4o",
        input_cost: 0.40, output_cost: 0.60, created_at: 1.hour.ago,
        started_at: 1.hour.ago, completed_at: 1.hour.ago)

      result = QueryTestAgent.cost_by_model(since: 24.hours)
      expect(result["gpt-4o"][:count]).to eq(1)
      expect(result["gpt-4o"][:total_cost]).to eq(1.00)
    end
  end

  describe ".with_params" do
    it "filters by parameter values" do
      e1 = create(:execution, agent_type: "QueryTestAgent")
      e1.detail.update!(parameters: {"user_id" => "u123", "category" => "billing"})
      e2 = create(:execution, agent_type: "QueryTestAgent")
      e2.detail.update!(parameters: {"user_id" => "u456", "category" => "support"})

      results = QueryTestAgent.with_params(user_id: "u123")
      expect(results.count).to eq(1)
      expect(results.first).to eq(e1)
    end

    it "filters by multiple parameter values" do
      e1 = create(:execution, agent_type: "QueryTestAgent")
      e1.detail.update!(parameters: {"user_id" => "u123", "category" => "billing"})
      e2 = create(:execution, agent_type: "QueryTestAgent")
      e2.detail.update!(parameters: {"user_id" => "u123", "category" => "support"})

      results = QueryTestAgent.with_params(user_id: "u123", category: "billing")
      expect(results.count).to eq(1)
      expect(results.first).to eq(e1)
    end

    it "returns empty when no match" do
      create(:execution, agent_type: "QueryTestAgent")

      expect(QueryTestAgent.with_params(user_id: "nonexistent").count).to eq(0)
    end
  end
end
