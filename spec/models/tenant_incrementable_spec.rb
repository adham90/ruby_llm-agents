# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Tenant::Incrementable, type: :model do
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenants)
      skip "Tenant table not available - run migration first"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
  end

  let(:tenant) do
    RubyLLM::Agents::Tenant.create!(
      tenant_id: "increment_test",
      daily_reset_date: Date.current,
      monthly_reset_date: Date.current.beginning_of_month
    )
  end

  describe "#record_execution!" do
    it "increments all counters atomically" do
      tenant.record_execution!(cost: 0.50, tokens: 1000)

      expect(tenant.daily_cost_spent).to eq(0.50)
      expect(tenant.monthly_cost_spent).to eq(0.50)
      expect(tenant.daily_tokens_used).to eq(1000)
      expect(tenant.monthly_tokens_used).to eq(1000)
      expect(tenant.daily_executions_count).to eq(1)
      expect(tenant.monthly_executions_count).to eq(1)
      expect(tenant.daily_error_count).to eq(0)
      expect(tenant.monthly_error_count).to eq(0)
    end

    it "accumulates across multiple calls" do
      tenant.record_execution!(cost: 0.50, tokens: 1000)
      tenant.record_execution!(cost: 0.25, tokens: 500)

      expect(tenant.daily_cost_spent).to eq(0.75)
      expect(tenant.daily_tokens_used).to eq(1500)
      expect(tenant.daily_executions_count).to eq(2)
    end

    it "increments error counters for error executions" do
      tenant.record_execution!(cost: 0.10, tokens: 200, error: true)

      expect(tenant.daily_error_count).to eq(1)
      expect(tenant.monthly_error_count).to eq(1)
      expect(tenant.daily_executions_count).to eq(1)
      expect(tenant.last_execution_status).to eq("error")
    end

    it "sets last_execution_at and last_execution_status" do
      tenant.record_execution!(cost: 0.50, tokens: 1000)

      expect(tenant.last_execution_at).to be_within(2.seconds).of(Time.current)
      expect(tenant.last_execution_status).to eq("success")
    end

    it "sets status to error when error: true" do
      tenant.record_execution!(cost: 0.10, tokens: 200, error: true)
      expect(tenant.last_execution_status).to eq("error")
    end

    it "triggers daily reset if date has rolled over" do
      tenant.update_columns(
        daily_cost_spent: 100.0,
        daily_reset_date: Date.yesterday
      )

      tenant.record_execution!(cost: 0.50, tokens: 1000)

      # After reset + increment, should only have the new execution's cost
      expect(tenant.daily_cost_spent).to eq(0.50)
    end
  end
end
