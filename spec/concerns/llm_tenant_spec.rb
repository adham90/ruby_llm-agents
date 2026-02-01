# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::LLMTenant do
  # Create a test model class for testing the concern
  before(:all) do
    # Create test tables if they don't exist
    ActiveRecord::Base.connection.execute <<-SQL
      CREATE TABLE IF NOT EXISTS test_organizations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR(255),
        slug VARCHAR(255),
        created_at DATETIME,
        updated_at DATETIME
      )
    SQL

    # Define named test class for polymorphic associations to work
    unless Object.const_defined?(:TestOrganization)
      Object.const_set(:TestOrganization, Class.new(ActiveRecord::Base) do
        self.table_name = "test_organizations"

        include RubyLLM::Agents::LLMTenant

        def to_s
          name || "Organization ##{id}"
        end
      end)
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_organizations")
    Object.send(:remove_const, :TestOrganization) if Object.const_defined?(:TestOrganization)
  end

  # Use the named test model
  let(:test_model_class) { TestOrganization }

  let(:organization) do
    test_model_class.create!(name: "Acme Corp", slug: "acme-corp")
  end

  describe ".llm_tenant" do
    it "adds llm_executions association" do
      expect(test_model_class.reflect_on_association(:llm_executions)).to be_present
    end

    it "adds llm_tenant_record association" do
      expect(test_model_class.reflect_on_association(:llm_tenant_record)).to be_present
    end

    it "provides llm_budget as a method for backward compatibility" do
      expect(test_model_class.instance_methods).to include(:llm_budget)
    end

    it "stores options in class attribute with defaults" do
      expect(test_model_class.llm_tenant_options).to eq({})
    end

    context "with custom options" do
      before(:all) do
        unless Object.const_defined?(:CustomOptionsOrg)
          Object.const_set(:CustomOptionsOrg, Class.new(ActiveRecord::Base) do
            self.table_name = "test_organizations"

            include RubyLLM::Agents::LLMTenant

            llm_tenant(
              id: :slug,
              name: :name,
              limits: { daily_cost: 100, monthly_cost: 1000 },
              enforcement: :hard
            )
          end)
        end
      end

      after(:all) do
        Object.send(:remove_const, :CustomOptionsOrg) if Object.const_defined?(:CustomOptionsOrg)
      end

      let(:custom_model_class) { CustomOptionsOrg }

      it "stores custom options" do
        expect(custom_model_class.llm_tenant_options[:id]).to eq(:slug)
        expect(custom_model_class.llm_tenant_options[:name]).to eq(:name)
        expect(custom_model_class.llm_tenant_options[:enforcement]).to eq(:hard)
      end

      it "normalizes limits" do
        limits = custom_model_class.llm_tenant_options[:limits]
        expect(limits[:daily_cost]).to eq(100)
        expect(limits[:monthly_cost]).to eq(1000)
      end

      it "sets budget: true when limits are provided" do
        expect(custom_model_class.llm_tenant_options[:budget]).to be true
      end
    end
  end

  describe "#llm_tenant_id" do
    context "with default id method" do
      it "returns id as string" do
        expect(organization.llm_tenant_id).to eq(organization.id.to_s)
      end
    end

    context "with custom id method" do
      before(:all) do
        unless Object.const_defined?(:CustomIdOrg)
          Object.const_set(:CustomIdOrg, Class.new(ActiveRecord::Base) do
            self.table_name = "test_organizations"

            include RubyLLM::Agents::LLMTenant

            llm_tenant id: :slug
          end)
        end
      end

      after(:all) do
        Object.send(:remove_const, :CustomIdOrg) if Object.const_defined?(:CustomIdOrg)
      end

      let(:custom_org) do
        CustomIdOrg.create!(name: "Acme Corp", slug: "acme-corp")
      end

      it "returns custom method result as string" do
        expect(custom_org.llm_tenant_id).to eq("acme-corp")
      end
    end
  end

  describe "#llm_cost" do
    before do
      # Create some test executions
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_cost: 0.50,
        tenant_record: organization
      )

      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_cost: 0.25,
        tenant_record: organization
      )
    end

    it "returns total cost for all executions" do
      expect(organization.llm_cost).to eq(0.75)
    end

    it "returns cost for today" do
      expect(organization.llm_cost_today).to eq(0.75)
    end
  end

  describe "#llm_tokens" do
    before do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_tokens: 1000,
        tenant_record: organization
      )
    end

    it "returns total tokens" do
      expect(organization.llm_tokens).to eq(1000)
    end

    it "returns tokens for today" do
      expect(organization.llm_tokens_today).to eq(1000)
    end
  end

  describe "#llm_execution_count" do
    before do
      2.times do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          tenant_record: organization
        )
      end
    end

    it "returns execution count" do
      expect(organization.llm_execution_count).to eq(2)
    end

    it "returns executions for today" do
      expect(organization.llm_executions_today).to eq(2)
    end

    it "returns executions for this month" do
      expect(organization.llm_executions_this_month).to eq(2)
    end
  end

  describe "#llm_usage_summary" do
    before do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_cost: 0.50,
        total_tokens: 1000,
        tenant_record: organization
      )
    end

    it "returns a complete usage summary" do
      summary = organization.llm_usage_summary
      expect(summary[:cost]).to eq(0.50)
      expect(summary[:tokens]).to eq(1000)
      expect(summary[:executions]).to eq(1)
      expect(summary[:period]).to eq(:this_month)
    end
  end

  describe "#llm_budget" do
    it "returns existing budget" do
      budget = RubyLLM::Agents::TenantBudget.create!(
        tenant_id: organization.llm_tenant_id,
        tenant_record: organization,
        daily_limit: 100.0
      )

      expect(organization.llm_budget).to eq(budget)
    end

    it "builds new budget if none exists" do
      budget = organization.llm_budget
      expect(budget).to be_a(RubyLLM::Agents::TenantBudget)
      expect(budget.tenant_id).to eq(organization.llm_tenant_id)
      expect(budget).not_to be_persisted
    end
  end

  describe "#llm_configure_budget" do
    it "configures and saves the budget" do
      organization.llm_configure_budget do |budget|
        budget.daily_limit = 50.0
        budget.enforcement = "hard"
      end

      expect(organization.llm_budget).to be_persisted
      expect(organization.llm_budget.daily_limit).to eq(50.0)
      expect(organization.llm_budget.enforcement).to eq("hard")
    end
  end

  describe "auto-create budget" do
    before(:all) do
      unless Object.const_defined?(:AutoBudgetOrg)
        Object.const_set(:AutoBudgetOrg, Class.new(ActiveRecord::Base) do
          self.table_name = "test_organizations"

          include RubyLLM::Agents::LLMTenant

          llm_tenant(
            budget: true,
            limits: {
              daily_cost: 100,
              monthly_cost: 1000,
              daily_executions: 500
            },
            enforcement: :hard
          )

          def to_s
            name || "Org ##{id}"
          end
        end)
      end
    end

    after(:all) do
      Object.send(:remove_const, :AutoBudgetOrg) if Object.const_defined?(:AutoBudgetOrg)
    end

    let(:auto_budget_class) { AutoBudgetOrg }

    it "creates budget on model creation" do
      org = auto_budget_class.create!(name: "Auto Budget Org", slug: "auto-budget")

      expect(org.llm_budget).to be_persisted
      expect(org.llm_budget.daily_limit).to eq(100)
      expect(org.llm_budget.monthly_limit).to eq(1000)
      expect(org.llm_budget.daily_execution_limit).to eq(500)
      expect(org.llm_budget.enforcement).to eq("hard")
      expect(org.llm_budget.name).to eq("Auto Budget Org")
    end
  end

  describe ".llm_tenant with api_keys" do
    before(:all) do
      unless Object.const_defined?(:ApiKeysOrg)
        Object.const_set(:ApiKeysOrg, Class.new(ActiveRecord::Base) do
          self.table_name = "test_organizations"

          include RubyLLM::Agents::LLMTenant

          # Simulate encrypted columns
          attr_accessor :openai_api_key, :anthropic_api_key

          llm_tenant(
            id: :slug,
            api_keys: {
              openai: :openai_api_key,
              anthropic: :anthropic_api_key,
              gemini: :fetch_gemini_key
            }
          )

          def fetch_gemini_key
            "gemini-key-from-vault"
          end
        end)
      end
    end

    after(:all) do
      Object.send(:remove_const, :ApiKeysOrg) if Object.const_defined?(:ApiKeysOrg)
    end

    let(:api_keys_class) { ApiKeysOrg }

    it "stores api_keys option in class options" do
      expect(api_keys_class.llm_tenant_options[:api_keys]).to eq({
        openai: :openai_api_key,
        anthropic: :anthropic_api_key,
        gemini: :fetch_gemini_key
      })
    end

    describe "#llm_api_keys" do
      let(:org) do
        api_keys_class.create!(name: "API Keys Org", slug: "api-keys-org")
      end

      it "resolves api keys from columns" do
        org.openai_api_key = "sk-openai-123"
        org.anthropic_api_key = "sk-ant-456"

        keys = org.llm_api_keys
        expect(keys[:openai]).to eq("sk-openai-123")
        expect(keys[:anthropic]).to eq("sk-ant-456")
      end

      it "resolves api keys from methods" do
        keys = org.llm_api_keys
        expect(keys[:gemini]).to eq("gemini-key-from-vault")
      end

      it "excludes blank values" do
        org.openai_api_key = ""
        org.anthropic_api_key = nil

        keys = org.llm_api_keys
        expect(keys).not_to have_key(:openai)
        expect(keys).not_to have_key(:anthropic)
        expect(keys[:gemini]).to eq("gemini-key-from-vault")
      end

      it "returns empty hash when no api_keys configured" do
        expect(organization.llm_api_keys).to eq({})
      end
    end
  end

  describe "period scoping" do
    before do
      # Create an execution from yesterday
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: 1.day.ago,
        created_at: 1.day.ago,
        status: "success",
        total_cost: 1.0,
        tenant_record: organization
      )

      # Create an execution from today
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "success",
        total_cost: 0.5,
        tenant_record: organization
      )
    end

    it "filters by today" do
      expect(organization.llm_cost_today).to eq(0.5)
    end

    it "filters by this month" do
      # Yesterday may be in the previous month (e.g., on the 1st)
      yesterday_in_current_month = 1.day.ago.to_date >= Date.current.beginning_of_month
      expected = yesterday_in_current_month ? 1.5 : 0.5
      expect(organization.llm_cost_this_month).to eq(expected)
    end

    it "supports custom date ranges" do
      expect(organization.llm_cost(period: 2.days.ago..Time.current)).to eq(1.5)
    end

    it "filters tokens by this month" do
      expect(organization.llm_tokens_this_month).to eq(0)
    end

    it "filters by yesterday" do
      expect(organization.llm_cost(period: :yesterday)).to eq(1.0)
    end

    it "filters by this week" do
      # Note: 1.day.ago might not be in the same week if today is Monday
      # all_week uses Monday as start of week by default
      if 1.day.ago.all_week == Time.current.all_week
        expect(organization.llm_cost(period: :this_week)).to eq(1.5)
      else
        # If yesterday was in a different week (e.g., today is Monday),
        # only today's execution should be counted
        expect(organization.llm_cost(period: :this_week)).to eq(0.5)
      end
    end
  end

  describe "#llm_budget_status" do
    it "returns budget status from tenant model" do
      tenant = organization.llm_tenant
      tenant.daily_limit = 100.0
      tenant.enforcement = "soft"
      tenant.save!
      tenant.update_columns(
        daily_cost_spent: 50.0, daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      status = organization.llm_budget_status
      expect(status[:enabled]).to be true
      expect(status[:global_daily][:percentage_used]).to eq(50.0)
    end
  end

  describe "#llm_within_budget?" do
    it "returns true when budget is disabled" do
      tenant = organization.llm_tenant
      tenant.enforcement = "none"
      tenant.save!

      expect(organization.llm_within_budget?).to be true
    end

    it "returns true when under budget" do
      tenant = organization.llm_tenant
      tenant.daily_limit = 100.0
      tenant.enforcement = "soft"
      tenant.save!
      tenant.update_columns(
        daily_cost_spent: 50.0, daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      expect(organization.llm_within_budget?(type: :daily_cost)).to be true
    end

    it "returns false when over budget" do
      tenant = organization.llm_tenant
      tenant.daily_limit = 100.0
      tenant.enforcement = "soft"
      tenant.save!
      tenant.update_columns(
        daily_cost_spent: 100.0, daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      expect(organization.llm_within_budget?(type: :daily_cost)).to be false
    end

    it "supports different budget types" do
      tenant = organization.llm_tenant
      tenant.monthly_limit = 1000.0
      tenant.daily_token_limit = 100000
      tenant.enforcement = "soft"
      tenant.save!
      tenant.update_columns(
        monthly_cost_spent: 750.0, daily_tokens_used: 90000,
        daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      expect(organization.llm_within_budget?(type: :monthly_cost)).to be true
      expect(organization.llm_within_budget?(type: :daily_tokens)).to be true
    end
  end

  describe "#llm_remaining_budget" do
    it "returns remaining budget from counters" do
      tenant = organization.llm_tenant
      tenant.daily_limit = 100.0
      tenant.enforcement = "soft"
      tenant.save!
      tenant.update_columns(
        daily_cost_spent: 50.0, daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      expect(organization.llm_remaining_budget(type: :daily_cost)).to eq(50.0)
    end

    it "returns remaining for different budget types" do
      tenant = organization.llm_tenant
      tenant.assign_attributes(
        monthly_limit: 1000.0,
        daily_token_limit: 100000, monthly_token_limit: 500000,
        daily_execution_limit: 200, monthly_execution_limit: 1000,
        enforcement: "soft"
      )
      tenant.save!
      tenant.update_columns(
        monthly_cost_spent: 800.0,
        daily_tokens_used: 90000, monthly_tokens_used: 450000,
        daily_executions_count: 100, monthly_executions_count: 500,
        daily_reset_date: Date.current,
        monthly_reset_date: Date.current.beginning_of_month
      )
      tenant.reload

      expect(organization.llm_remaining_budget(type: :monthly_cost)).to eq(200.0)
      expect(organization.llm_remaining_budget(type: :daily_tokens)).to eq(10000)
      expect(organization.llm_remaining_budget(type: :monthly_tokens)).to eq(50000)
      expect(organization.llm_remaining_budget(type: :daily_executions)).to eq(100)
      expect(organization.llm_remaining_budget(type: :monthly_executions)).to eq(500)
    end
  end

  describe "#llm_check_budget!" do
    it "delegates to tenant.check_budget!" do
      tenant = organization.llm_tenant
      expect(tenant).to receive(:check_budget!).with("TestOrganization")

      organization.llm_check_budget!
    end
  end
end
