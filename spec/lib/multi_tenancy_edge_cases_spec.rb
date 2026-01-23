# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "Multi-tenancy Edge Cases" do
  # Helper to create tenant-aware agent
  def create_tenant_agent_class(options = {}, &block)
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :query, required: true

      class_eval(&block) if block

      def user_prompt
        query
      end

      def self.name
        "TenantTestAgent"
      end
    end
  end

  let(:mock_response) do
    build_mock_response(content: "Test response", input_tokens: 100, output_tokens: 50)
  end

  let(:mock_chat) do
    build_mock_chat_client(response: mock_response)
  end

  before do
    stub_agent_configuration
    stub_ruby_llm_chat(mock_chat)
  end

  describe "tenant isolation" do
    context "when executing agents for different tenants" do
      let(:agent_class) do
        create_tenant_agent_class do
          def resolve_tenant
            @options[:tenant]
          end
        end
      end

      it "maintains tenant context through execution" do
        agent = agent_class.new(query: "test", tenant: { id: "tenant-123" })
        expect(agent.resolved_tenant_id).to eq("tenant-123")
      end

      it "resolves different tenant contexts independently" do
        agent_a = agent_class.new(query: "test", tenant: { id: "tenant-a" })
        agent_b = agent_class.new(query: "test", tenant: { id: "tenant-b" })

        expect(agent_a.resolved_tenant_id).to eq("tenant-a")
        expect(agent_b.resolved_tenant_id).to eq("tenant-b")
      end
    end
  end

  describe "concurrent tenant executions" do
    let(:agent_class) do
      create_tenant_agent_class do
        def resolve_tenant
          @options[:tenant]
        end
      end
    end

    it "handles concurrent executions from different tenants" do
      threads = []
      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      %w[tenant-1 tenant-2 tenant-3].each do |tenant_id|
        threads << Thread.new do
          begin
            agent = agent_class.new(query: "test", tenant: { id: tenant_id })
            result = agent.call
            results << { tenant: tenant_id, success: result.success? }
          rescue StandardError => e
            errors << { tenant: tenant_id, error: e.message }
          end
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      expect(results.size).to eq(3)
      expect(results.all? { |r| r[:success] }).to be true
    end
  end

  describe "tenant budget isolation" do
    let(:agent_class) do
      create_tenant_agent_class do
        def resolve_tenant
          @options[:tenant]
        end
      end
    end

    before do
      # Create tenant budgets with correct schema columns
      RubyLLM::Agents::TenantBudget.create!(
        tenant_id: "budget-tenant-a",
        name: "Budget A",
        daily_limit: 100.00,
        monthly_limit: 1000.00
      )

      RubyLLM::Agents::TenantBudget.create!(
        tenant_id: "budget-tenant-b",
        name: "Budget B",
        daily_limit: 50.00,
        monthly_limit: 500.00
      )
    end

    it "queries budget for correct tenant" do
      budget_a = RubyLLM::Agents::TenantBudget.where(tenant_id: "budget-tenant-a").first
      budget_b = RubyLLM::Agents::TenantBudget.where(tenant_id: "budget-tenant-b").first

      expect(budget_a.daily_limit).to eq(100.00)
      expect(budget_b.daily_limit).to eq(50.00)
    end

    it "does not mix tenant budget data" do
      budgets_a = RubyLLM::Agents::TenantBudget.where(tenant_id: "budget-tenant-a")
      budgets_b = RubyLLM::Agents::TenantBudget.where(tenant_id: "budget-tenant-b")

      expect(budgets_a.pluck(:tenant_id).uniq).to eq(["budget-tenant-a"])
      expect(budgets_b.pluck(:tenant_id).uniq).to eq(["budget-tenant-b"])
    end
  end

  describe "execution scoping by tenant" do
    let(:agent_class) do
      create_tenant_agent_class do
        def resolve_tenant
          @options[:tenant]
        end
      end
    end

    before do
      # Create executions for multiple tenants
      RubyLLM::Agents::Execution.create!(
        agent_type: "TenantTestAgent",
        model_id: "gpt-4o",
        input_tokens: 100,
        output_tokens: 50,
        total_cost: 0.01,
        duration_ms: 100,
        status: "success",
        tenant_id: "scope-tenant-a",
        started_at: Time.current
      )

      RubyLLM::Agents::Execution.create!(
        agent_type: "TenantTestAgent",
        model_id: "gpt-4o",
        input_tokens: 200,
        output_tokens: 100,
        total_cost: 0.02,
        duration_ms: 150,
        status: "success",
        tenant_id: "scope-tenant-b",
        started_at: Time.current
      )

      RubyLLM::Agents::Execution.create!(
        agent_type: "OtherAgent",
        model_id: "gpt-4o",
        input_tokens: 50,
        output_tokens: 25,
        total_cost: 0.005,
        duration_ms: 50,
        status: "success",
        tenant_id: "scope-tenant-a",
        started_at: Time.current
      )
    end

    it "scopes executions by tenant" do
      tenant_a_executions = RubyLLM::Agents::Execution.by_tenant("scope-tenant-a")
      tenant_b_executions = RubyLLM::Agents::Execution.by_tenant("scope-tenant-b")

      expect(tenant_a_executions.count).to eq(2)
      expect(tenant_b_executions.count).to eq(1)
    end

    it "calculates tenant-specific costs" do
      tenant_a_cost = RubyLLM::Agents::Execution.by_tenant("scope-tenant-a").sum(:total_cost)
      tenant_b_cost = RubyLLM::Agents::Execution.by_tenant("scope-tenant-b").sum(:total_cost)

      expect(tenant_a_cost).to eq(0.015)
      expect(tenant_b_cost).to eq(0.02)
    end

    it "supports combined scopes with tenant" do
      executions = RubyLLM::Agents::Execution
        .by_tenant("scope-tenant-a")
        .where(agent_type: "TenantTestAgent")

      expect(executions.count).to eq(1)
    end
  end

  describe "tenant resolution edge cases" do
    it "handles nil tenant gracefully" do
      agent_class = create_tenant_agent_class do
        def resolve_tenant
          nil
        end
      end

      agent = agent_class.new(query: "test")
      expect(agent.resolved_tenant_id).to be_nil

      # Should still execute successfully
      result = agent.call
      expect(result).to be_a(RubyLLM::Agents::Result)
    end

    it "handles tenant without id key" do
      agent_class = create_tenant_agent_class do
        def resolve_tenant
          { name: "Test Tenant", settings: {} }
        end
      end

      agent = agent_class.new(query: "test")
      expect(agent.resolved_tenant_id).to be_nil
    end

    it "handles tenant with string id" do
      agent_class = create_tenant_agent_class do
        def resolve_tenant
          { id: "string-tenant-id" }
        end
      end

      agent = agent_class.new(query: "test")
      expect(agent.resolved_tenant_id).to eq("string-tenant-id")
    end

    it "handles tenant with integer id" do
      agent_class = create_tenant_agent_class do
        def resolve_tenant
          { id: 12345 }
        end
      end

      agent = agent_class.new(query: "test")
      expect(agent.resolved_tenant_id).to eq("12345")
    end

    it "handles tenant object with id method" do
      tenant_object = OpenStruct.new(id: "object-tenant-123")

      agent_class = create_tenant_agent_class do
        param :tenant_obj, required: false

        def resolve_tenant
          tenant_obj
        end
      end

      agent = agent_class.new(query: "test", tenant_obj: tenant_object)
      # OpenStruct should work like a hash for tenant resolution
      expect(agent.resolve_tenant).to eq(tenant_object)
    end
  end

  describe "tenant switching scenarios" do
    let(:agent_class) do
      create_tenant_agent_class do
        def resolve_tenant
          @options[:tenant]
        end
      end
    end

    it "handles switching tenants between executions" do
      agent_a = agent_class.new(query: "test", tenant: { id: "switch-a" })
      agent_b = agent_class.new(query: "test", tenant: { id: "switch-b" })

      result_a = agent_a.call
      result_b = agent_b.call

      # Verify both agents executed successfully with their respective tenant contexts
      expect(result_a.success?).to be true
      expect(result_b.success?).to be true

      # Verify tenant IDs are correctly resolved
      expect(agent_a.resolved_tenant_id).to eq("switch-a")
      expect(agent_b.resolved_tenant_id).to eq("switch-b")
    end
  end

  describe "tenant with special characters" do
    let(:agent_class) do
      create_tenant_agent_class do
        def resolve_tenant
          @options[:tenant]
        end
      end
    end

    it "handles tenant_id with special characters" do
      special_ids = [
        "tenant-with-dashes",
        "tenant_with_underscores",
        "tenant.with.dots",
        "tenant:with:colons",
        "UUID-12345678-1234-1234-1234-123456789012"
      ]

      special_ids.each do |tenant_id|
        agent = agent_class.new(query: "test", tenant: { id: tenant_id })
        expect(agent.resolved_tenant_id).to eq(tenant_id)
      end
    end
  end

  describe "execution analytics by tenant" do
    before do
      # Create diverse executions for analytics testing
      3.times do |i|
        RubyLLM::Agents::Execution.create!(
          agent_type: "AnalyticsAgent",
          model_id: "gpt-4o",
          input_tokens: 100 * (i + 1),
          output_tokens: 50 * (i + 1),
          total_cost: 0.01 * (i + 1),
          duration_ms: 100 * (i + 1),
          status: "success",
          tenant_id: "analytics-tenant",
          started_at: i.days.ago,
          created_at: i.days.ago
        )
      end
    end

    it "aggregates metrics correctly for a tenant" do
      tenant_executions = RubyLLM::Agents::Execution.by_tenant("analytics-tenant")

      total_cost = tenant_executions.sum(:total_cost)
      total_tokens = tenant_executions.sum(:input_tokens) + tenant_executions.sum(:output_tokens)
      avg_duration = tenant_executions.average(:duration_ms)

      expect(total_cost).to eq(0.06) # 0.01 + 0.02 + 0.03
      expect(total_tokens).to eq(900) # (100+50) + (200+100) + (300+150)
      expect(avg_duration).to eq(200) # (100 + 200 + 300) / 3
    end

    it "calculates daily breakdown for tenant" do
      daily_costs = RubyLLM::Agents::Execution
        .by_tenant("analytics-tenant")
        .group("DATE(created_at)")
        .sum(:total_cost)

      expect(daily_costs.keys.count).to eq(3)
    end
  end
end
