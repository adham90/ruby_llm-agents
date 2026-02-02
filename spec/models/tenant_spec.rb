# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Tenant, type: :model do
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenants)
      skip "Tenant table not available - run migration first"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
  end

  let(:tenant) { described_class.create!(tenant_id: "test_tenant", name: "Test Tenant") }

  describe "Trackable concern" do
    describe "#executions association" do
      it "has many executions via tenant_id" do
        association = described_class.reflect_on_association(:executions)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:primary_key]).to eq(:tenant_id)
        expect(association.options[:foreign_key]).to eq(:tenant_id)
      end
    end

    describe "cost tracking" do
      before do
        # Create executions for this tenant
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 0.50,
          tenant_id: tenant.tenant_id
        )

        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 0.25,
          tenant_id: tenant.tenant_id
        )

        # Create execution for yesterday
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 1.day.ago,
          created_at: 1.day.ago,
          status: "success",
          total_cost: 1.00,
          tenant_id: tenant.tenant_id
        )

        # Refresh counters so counter-based methods work
        tenant.refresh_counters!
      end

      it "returns total cost" do
        expect(tenant.cost).to eq(1.75)
      end

      it "returns cost for today (from counters)" do
        expect(tenant.cost_today).to eq(0.75)
      end

      it "returns cost for yesterday" do
        expect(tenant.cost_yesterday).to eq(1.00)
      end

      it "returns cost for this month (from counters)" do
        # Only includes executions from the current month
        # Yesterday's executions may be in the previous month (e.g., on the 1st)
        yesterday_in_current_month = 1.day.ago.to_date >= Date.current.beginning_of_month
        expected = yesterday_in_current_month ? 1.75 : 0.75
        expect(tenant.cost_this_month.to_f).to eq(expected)
      end

      it "returns cost for custom date range" do
        expect(tenant.cost(period: 2.days.ago..Time.current)).to eq(1.75)
      end
    end

    describe "token tracking" do
      before do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_tokens: 1000,
          tenant_id: tenant.tenant_id
        )

        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 1.day.ago,
          created_at: 1.day.ago,
          status: "success",
          total_tokens: 500,
          tenant_id: tenant.tenant_id
        )

        tenant.refresh_counters!
      end

      it "returns total tokens" do
        expect(tenant.tokens).to eq(1500)
      end

      it "returns tokens for today (from counters)" do
        expect(tenant.tokens_today).to eq(1000)
      end

      it "returns tokens for yesterday" do
        expect(tenant.tokens_yesterday).to eq(500)
      end
    end

    describe "execution count tracking" do
      before do
        3.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: Time.current,
            status: "success",
            tenant_id: tenant.tenant_id
          )
        end

        2.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: 1.day.ago,
            created_at: 1.day.ago,
            status: "success",
            tenant_id: tenant.tenant_id
          )
        end

        tenant.refresh_counters!
      end

      it "returns total execution count" do
        expect(tenant.execution_count).to eq(5)
      end

      it "returns executions for today (from counters)" do
        expect(tenant.executions_today).to eq(3)
      end

      it "returns executions for yesterday" do
        expect(tenant.executions_yesterday).to eq(2)
      end

      it "returns executions for this month (from counters)" do
        yesterday_in_current_month = 1.day.ago.to_date >= Date.current.beginning_of_month
        expected = yesterday_in_current_month ? 5 : 3
        expect(tenant.executions_this_month).to eq(expected)
      end
    end

    describe "#usage_summary" do
      before do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 0.50,
          total_tokens: 1000,
          tenant_id: tenant.tenant_id
        )
      end

      it "returns a complete usage summary" do
        summary = tenant.usage_summary
        expect(summary[:tenant_id]).to eq("test_tenant")
        expect(summary[:name]).to eq("Test Tenant")
        expect(summary[:period]).to eq(:this_month)
        expect(summary[:cost]).to eq(0.50)
        expect(summary[:tokens]).to eq(1000)
        expect(summary[:executions]).to eq(1)
      end

      it "accepts a custom period" do
        summary = tenant.usage_summary(period: :today)
        expect(summary[:period]).to eq(:today)
      end
    end

    describe "#usage_by_agent" do
      before do
        RubyLLM::Agents::Execution.create!(
          agent_type: "ChatAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 0.50,
          total_tokens: 1000,
          tenant_id: tenant.tenant_id
        )

        2.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "SummaryAgent",
            agent_version: "1.0",
            model_id: "gpt-3.5-turbo",
            started_at: Time.current,
            status: "success",
            total_cost: 0.10,
            total_tokens: 500,
            tenant_id: tenant.tenant_id
          )
        end
      end

      it "returns usage grouped by agent type" do
        usage = tenant.usage_by_agent

        expect(usage["ChatAgent"][:cost]).to eq(0.50)
        expect(usage["ChatAgent"][:tokens]).to eq(1000)
        expect(usage["ChatAgent"][:count]).to eq(1)

        expect(usage["SummaryAgent"][:cost]).to eq(0.20)
        expect(usage["SummaryAgent"][:tokens]).to eq(1000)
        expect(usage["SummaryAgent"][:count]).to eq(2)
      end
    end

    describe "#usage_by_model" do
      before do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 1.00,
          total_tokens: 500,
          tenant_id: tenant.tenant_id
        )

        2.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-3.5-turbo",
            started_at: Time.current,
            status: "success",
            total_cost: 0.05,
            total_tokens: 1000,
            tenant_id: tenant.tenant_id
          )
        end
      end

      it "returns usage grouped by model" do
        usage = tenant.usage_by_model

        expect(usage["gpt-4"][:cost]).to eq(1.00)
        expect(usage["gpt-4"][:tokens]).to eq(500)
        expect(usage["gpt-4"][:count]).to eq(1)

        expect(usage["gpt-3.5-turbo"][:cost]).to eq(0.10)
        expect(usage["gpt-3.5-turbo"][:tokens]).to eq(2000)
        expect(usage["gpt-3.5-turbo"][:count]).to eq(2)
      end
    end

    describe "#usage_by_day" do
      before do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_cost: 0.50,
          total_tokens: 500,
          tenant_id: tenant.tenant_id
        )

        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 1.day.ago,
          created_at: 1.day.ago,
          status: "success",
          total_cost: 1.00,
          total_tokens: 1000,
          tenant_id: tenant.tenant_id
        )
      end

      it "returns usage grouped by day" do
        usage = tenant.usage_by_day

        today = Date.current

        expect(usage[today][:cost]).to eq(0.50)
        expect(usage[today][:tokens]).to eq(500)
        expect(usage[today][:count]).to eq(1)

        # Yesterday may be in the previous month (e.g., on the 1st),
        # so only assert if it falls within :this_month scope
        yesterday = Date.current - 1
        if yesterday >= Date.current.beginning_of_month
          expect(usage[yesterday][:cost]).to eq(1.00)
          expect(usage[yesterday][:tokens]).to eq(1000)
          expect(usage[yesterday][:count]).to eq(1)
        end
      end
    end

    describe "#recent_executions" do
      before do
        5.times do |i|
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: Time.current - i.hours,
            created_at: Time.current - i.hours,
            status: "success",
            tenant_id: tenant.tenant_id
          )
        end
      end

      it "returns recent executions in descending order" do
        recent = tenant.recent_executions(limit: 3)
        expect(recent.count).to eq(3)
        expect(recent.first.created_at).to be > recent.last.created_at
      end

      it "defaults to 10 executions" do
        # Add more executions
        10.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: Time.current,
            status: "success",
            tenant_id: tenant.tenant_id
          )
        end

        recent = tenant.recent_executions
        expect(recent.count).to eq(10)
      end
    end

    describe "#failed_executions" do
      before do
        3.times do
          exec = RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: Time.current,
            status: "error",
            error_class: "TestError",
            tenant_id: tenant.tenant_id
          )
          exec.create_detail!(error_message: "Test error message")
        end

        2.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            agent_version: "1.0",
            model_id: "gpt-4",
            started_at: Time.current,
            status: "success",
            tenant_id: tenant.tenant_id
          )
        end
      end

      it "returns only failed executions" do
        failed = tenant.failed_executions
        expect(failed.count).to eq(3)
        expect(failed.all? { |e| e.status == "error" }).to be true
      end

      it "respects the limit parameter" do
        failed = tenant.failed_executions(limit: 2)
        expect(failed.count).to eq(2)
      end

      it "respects the period parameter" do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 2.days.ago,
          created_at: 2.days.ago,
          status: "error",
          tenant_id: tenant.tenant_id
        )

        failed_today = tenant.failed_executions(period: :today)
        expect(failed_today.count).to eq(3)
      end
    end
  end

  describe "class methods" do
    describe ".for" do
      let!(:existing_tenant) { described_class.create!(tenant_id: "lookup_test", name: "Lookup Test") }

      it "finds tenant by string tenant_id" do
        found = described_class.for("lookup_test")
        expect(found).to eq(existing_tenant)
      end

      it "returns nil for non-existent tenant" do
        expect(described_class.for("nonexistent")).to be_nil
      end

      it "returns nil for blank input" do
        expect(described_class.for("")).to be_nil
        expect(described_class.for(nil)).to be_nil
      end
    end

    describe ".for!" do
      it "creates tenant if not exists" do
        tenant = described_class.for!("new_tenant", name: "New Tenant")
        expect(tenant).to be_persisted
        expect(tenant.tenant_id).to eq("new_tenant")
        expect(tenant.name).to eq("New Tenant")
      end

      it "returns existing tenant without updating" do
        existing = described_class.create!(tenant_id: "existing", name: "Original Name")
        found = described_class.for!("existing", name: "Updated Name")
        expect(found).to eq(existing)
        expect(found.name).to eq("Original Name")
      end
    end
  end

  describe "scopes" do
    before do
      described_class.create!(tenant_id: "active_1", active: true)
      described_class.create!(tenant_id: "active_2", active: true)
      described_class.create!(tenant_id: "inactive_1", active: false)
    end

    it "filters active tenants" do
      expect(described_class.active.count).to eq(2)
    end

    it "filters inactive tenants" do
      expect(described_class.inactive.count).to eq(1)
    end
  end

  describe "instance methods" do
    describe "#active?" do
      it "returns true when active is true" do
        tenant = described_class.new(active: true)
        expect(tenant.active?).to be true
      end

      it "returns true when active is nil (default)" do
        tenant = described_class.new(active: nil)
        expect(tenant.active?).to be true
      end

      it "returns false when active is false" do
        tenant = described_class.new(active: false)
        expect(tenant.active?).to be false
      end
    end

    describe "#deactivate!" do
      it "sets active to false" do
        tenant.deactivate!
        expect(tenant.reload.active).to be false
      end
    end

    describe "#activate!" do
      it "sets active to true" do
        tenant.update!(active: false)
        tenant.activate!
        expect(tenant.reload.active).to be true
      end
    end

    describe "#linked?" do
      it "returns false when no tenant_record" do
        expect(tenant.linked?).to be false
      end
    end
  end
end
