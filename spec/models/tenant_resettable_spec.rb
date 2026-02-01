# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Tenant::Resettable, type: :model do
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
      tenant_id: "reset_test",
      daily_cost_spent: 10.0,
      monthly_cost_spent: 50.0,
      daily_tokens_used: 1000,
      monthly_tokens_used: 5000,
      daily_executions_count: 5,
      monthly_executions_count: 20,
      daily_error_count: 1,
      monthly_error_count: 3,
      daily_reset_date: Date.current,
      monthly_reset_date: Date.current.beginning_of_month
    )
  end

  describe "#ensure_daily_reset!" do
    it "does nothing when daily_reset_date is today" do
      tenant.ensure_daily_reset!
      expect(tenant.daily_cost_spent).to eq(10.0)
      expect(tenant.daily_tokens_used).to eq(1000)
    end

    it "resets daily counters when date has rolled over" do
      tenant.update_columns(daily_reset_date: Date.yesterday)
      tenant.ensure_daily_reset!

      expect(tenant.daily_cost_spent).to eq(0)
      expect(tenant.daily_tokens_used).to eq(0)
      expect(tenant.daily_executions_count).to eq(0)
      expect(tenant.daily_error_count).to eq(0)
      expect(tenant.daily_reset_date).to eq(Date.current)
    end

    it "resets daily counters when daily_reset_date is nil" do
      tenant.update_columns(daily_reset_date: nil)
      tenant.ensure_daily_reset!

      expect(tenant.daily_cost_spent).to eq(0)
      expect(tenant.daily_reset_date).to eq(Date.current)
    end

    it "does not reset monthly counters" do
      tenant.update_columns(daily_reset_date: Date.yesterday)
      tenant.ensure_daily_reset!

      expect(tenant.monthly_cost_spent).to eq(50.0)
      expect(tenant.monthly_tokens_used).to eq(5000)
    end
  end

  describe "#ensure_monthly_reset!" do
    it "does nothing when monthly_reset_date is current month" do
      tenant.ensure_monthly_reset!
      expect(tenant.monthly_cost_spent).to eq(50.0)
    end

    it "resets monthly counters when month has rolled over" do
      tenant.update_columns(monthly_reset_date: 1.month.ago.beginning_of_month)
      tenant.ensure_monthly_reset!

      expect(tenant.monthly_cost_spent).to eq(0)
      expect(tenant.monthly_tokens_used).to eq(0)
      expect(tenant.monthly_executions_count).to eq(0)
      expect(tenant.monthly_error_count).to eq(0)
      expect(tenant.monthly_reset_date).to eq(Date.current.beginning_of_month)
    end

    it "does not reset daily counters" do
      tenant.update_columns(monthly_reset_date: 1.month.ago.beginning_of_month)
      tenant.ensure_monthly_reset!

      expect(tenant.daily_cost_spent).to eq(10.0)
    end
  end

  describe "#refresh_counters!" do
    let(:tenant) do
      RubyLLM::Agents::Tenant.create!(tenant_id: "refresh_test")
    end

    before do
      # Create executions for today
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent", agent_version: "1.0", model_id: "gpt-4",
        started_at: Time.current, status: "success",
        total_cost: 0.50, total_tokens: 1000, tenant_id: tenant.tenant_id
      )
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent", agent_version: "1.0", model_id: "gpt-4",
        started_at: Time.current, status: "error",
        total_cost: 0.10, total_tokens: 200, tenant_id: tenant.tenant_id
      )
    end

    it "recalculates all counters from executions" do
      tenant.refresh_counters!

      expect(tenant.daily_cost_spent).to eq(0.60)
      expect(tenant.daily_tokens_used).to eq(1200)
      expect(tenant.daily_executions_count).to eq(2)
      expect(tenant.daily_error_count).to eq(1)
      expect(tenant.monthly_cost_spent).to eq(0.60)
      expect(tenant.monthly_tokens_used).to eq(1200)
      expect(tenant.monthly_executions_count).to eq(2)
      expect(tenant.monthly_error_count).to eq(1)
    end

    it "sets last execution metadata" do
      tenant.refresh_counters!

      expect(tenant.last_execution_at).to be_present
      expect(tenant.last_execution_status).to eq("error").or eq("success")
    end

    it "sets reset dates to current period" do
      tenant.refresh_counters!

      expect(tenant.daily_reset_date).to eq(Date.current)
      expect(tenant.monthly_reset_date).to eq(Date.current.beginning_of_month)
    end
  end

  describe ".refresh_all_counters!" do
    it "refreshes all tenants" do
      t1 = RubyLLM::Agents::Tenant.create!(tenant_id: "refresh_all_1")
      t2 = RubyLLM::Agents::Tenant.create!(tenant_id: "refresh_all_2")

      # Verify it runs without error and sets reset dates
      RubyLLM::Agents::Tenant.refresh_all_counters!

      expect(t1.reload.daily_reset_date).to eq(Date.current)
      expect(t2.reload.daily_reset_date).to eq(Date.current)
    end
  end

  describe ".refresh_active_counters!" do
    it "only refreshes active tenants" do
      active = RubyLLM::Agents::Tenant.create!(tenant_id: "active_refresh", active: true)
      inactive = RubyLLM::Agents::Tenant.create!(tenant_id: "inactive_refresh", active: false)

      # The active tenant should be refreshed
      expect(RubyLLM::Agents::Tenant.active).to include(active)
      expect(RubyLLM::Agents::Tenant.active).not_to include(inactive)
    end
  end
end
