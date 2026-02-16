# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tenant auto-creation on agent execution" do
  # Simulate the real-world scenario:
  # - A host app has Organizations already in the database
  # - The gem is installed with multi-tenancy enabled
  # - Pre-existing organizations have NO row in ruby_llm_agents_tenants
  # - When an agent runs with tenant: organization, the Tenant record should be created

  before(:all) do
    ActiveRecord::Base.connection.execute <<-SQL
      CREATE TABLE IF NOT EXISTS auto_create_test_organizations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR(255),
        slug VARCHAR(255),
        created_at DATETIME,
        updated_at DATETIME
      )
    SQL

    # Organization with budget: true and limits (simulates a real host app model)
    unless Object.const_defined?(:AutoCreateTestOrg)
      Object.const_set(:AutoCreateTestOrg, Class.new(ActiveRecord::Base) do
        self.table_name = "auto_create_test_organizations"

        include RubyLLM::Agents::LLMTenant

        llm_tenant(
          id: :slug,
          name: :name,
          budget: true,
          limits: {
            daily_cost: 50,
            monthly_cost: 500
          },
          enforcement: :hard
        )

        def to_s
          name || "Org ##{id}"
        end
      end)
    end

    # Organization without budget DSL (just basic llm_tenant)
    unless Object.const_defined?(:BasicAutoCreateTestOrg)
      Object.const_set(:BasicAutoCreateTestOrg, Class.new(ActiveRecord::Base) do
        self.table_name = "auto_create_test_organizations"

        include RubyLLM::Agents::LLMTenant

        llm_tenant id: :slug

        def to_s
          name || "Org ##{id}"
        end
      end)
    end

    # Test agent that produces a simple response
    unless Object.const_defined?(:AutoCreateTenantTestAgent)
      Object.const_set(:AutoCreateTenantTestAgent, Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def user_prompt
          "Hello"
        end
      end)
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS auto_create_test_organizations")
    Object.send(:remove_const, :AutoCreateTestOrg) if Object.const_defined?(:AutoCreateTestOrg)
    Object.send(:remove_const, :BasicAutoCreateTestOrg) if Object.const_defined?(:BasicAutoCreateTestOrg)
    Object.send(:remove_const, :AutoCreateTenantTestAgent) if Object.const_defined?(:AutoCreateTenantTestAgent)
  end

  # Enable multi-tenancy so execution records include tenant_id
  around do |example|
    original_multi_tenancy = RubyLLM::Agents.configuration.multi_tenancy_enabled
    RubyLLM::Agents.configuration.multi_tenancy_enabled = true

    example.run
  ensure
    RubyLLM::Agents.configuration.multi_tenancy_enabled = original_multi_tenancy
  end

  # Stub the LLM call so we don't hit real APIs
  before do
    mock_response = build_mock_response(content: "test response", input_tokens: 10, output_tokens: 20)
    mock_client = build_mock_chat_client(response: mock_response)
    stub_ruby_llm_chat(mock_client)
  end

  # Helper: insert a row directly to bypass the after_create callback,
  # simulating a pre-existing organization that was created before the gem was installed.
  def insert_pre_existing_org(name:, slug:)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO auto_create_test_organizations (name, slug, created_at, updated_at) " \
      "VALUES ('#{name}', '#{slug}', datetime('now'), datetime('now'))"
    )
  end

  describe "pre-existing organization without Tenant record" do
    it "has no Tenant record before agent execution" do
      insert_pre_existing_org(name: "Pre-existing Corp", slug: "pre-existing-corp")
      org = BasicAutoCreateTestOrg.find_by(slug: "pre-existing-corp")

      # Verify: no Tenant record exists (this is the bug scenario)
      expect(RubyLLM::Agents::Tenant.find_by(tenant_id: "pre-existing-corp")).to be_nil
      expect(RubyLLM::Agents::Tenant.find_by(tenant_record: org)).to be_nil
    end

    it "auto-creates a Tenant record when the agent executes with this organization" do
      insert_pre_existing_org(name: "Acme Corp", slug: "acme-corp")
      org = AutoCreateTestOrg.find_by(slug: "acme-corp")

      # Precondition: no Tenant row
      expect(RubyLLM::Agents::Tenant.find_by(tenant_id: "acme-corp")).to be_nil

      # Run agent with this tenant
      AutoCreateTenantTestAgent.call(tenant: org)

      # Verify: Tenant record was auto-created with polymorphic link
      tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: "acme-corp")
      expect(tenant).to be_present
      expect(tenant.name).to eq("Acme Corp")
      expect(tenant.tenant_record_type).to eq("AutoCreateTestOrg")
      expect(tenant.tenant_record_id).to eq(org.id.to_s)
    end

    it "auto-creates with budget limits from the LLMTenant DSL" do
      insert_pre_existing_org(name: "Budget Corp", slug: "budget-corp")
      org = AutoCreateTestOrg.find_by(slug: "budget-corp")

      AutoCreateTenantTestAgent.call(tenant: org)

      tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: "budget-corp")
      expect(tenant).to be_present
      expect(tenant.daily_limit).to eq(50)
      expect(tenant.monthly_limit).to eq(500)
      expect(tenant.enforcement).to eq("hard")
      expect(tenant.inherit_global_defaults).to be true
    end

    it "auto-creates a basic Tenant record when no limits are configured" do
      insert_pre_existing_org(name: "Basic Corp", slug: "basic-corp")
      org = BasicAutoCreateTestOrg.find_by(slug: "basic-corp")

      AutoCreateTenantTestAgent.call(tenant: org)

      tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: "basic-corp")
      expect(tenant).to be_present
      expect(tenant.name).to eq("Basic Corp")
      expect(tenant.tenant_record_type).to eq("BasicAutoCreateTestOrg")
      expect(tenant.daily_limit).to be_nil
      expect(tenant.monthly_limit).to be_nil
    end
  end

  describe "does not duplicate on repeated executions" do
    it "creates the Tenant record only once across multiple agent calls" do
      insert_pre_existing_org(name: "Repeat Corp", slug: "repeat-corp")
      org = AutoCreateTestOrg.find_by(slug: "repeat-corp")

      # First call creates the record
      expect {
        AutoCreateTenantTestAgent.call(tenant: org)
      }.to change { RubyLLM::Agents::Tenant.where(tenant_id: "repeat-corp").count }.from(0).to(1)

      # Second call does not duplicate
      expect {
        AutoCreateTenantTestAgent.call(tenant: org)
      }.not_to change { RubyLLM::Agents::Tenant.where(tenant_id: "repeat-corp").count }

      # Third call — still no duplicate
      expect {
        AutoCreateTenantTestAgent.call(tenant: org)
      }.not_to change { RubyLLM::Agents::Tenant.where(tenant_id: "repeat-corp").count }
    end
  end

  describe "newly created organizations (after_create still works)" do
    it "creates Tenant record via after_create callback as before" do
      org = AutoCreateTestOrg.create!(name: "New Corp", slug: "new-corp")

      # after_create should have created the record
      tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: "new-corp")
      expect(tenant).to be_present
      expect(tenant.daily_limit).to eq(50)
      expect(tenant.monthly_limit).to eq(500)
    end

    it "does not duplicate when agent runs after after_create already created the record" do
      org = AutoCreateTestOrg.create!(name: "Fresh Corp", slug: "fresh-corp")

      # after_create already created the Tenant
      expect(RubyLLM::Agents::Tenant.where(tenant_id: "fresh-corp").count).to eq(1)

      # Agent execution should not create another
      expect {
        AutoCreateTenantTestAgent.call(tenant: org)
      }.not_to change { RubyLLM::Agents::Tenant.where(tenant_id: "fresh-corp").count }
    end
  end

  describe "hash-based tenant auto-creation" do
    it "creates a minimal Tenant record for hash tenants" do
      expect(RubyLLM::Agents::Tenant.find_by(tenant_id: "hash-only-tenant")).to be_nil

      AutoCreateTenantTestAgent.call(tenant: { id: "hash-only-tenant" })

      tenant = RubyLLM::Agents::Tenant.find_by(tenant_id: "hash-only-tenant")
      expect(tenant).to be_present
      expect(tenant.tenant_record_type).to be_nil
    end

    it "does not duplicate hash tenants on repeated calls" do
      expect {
        AutoCreateTenantTestAgent.call(tenant: { id: "hash-repeat" })
      }.to change { RubyLLM::Agents::Tenant.where(tenant_id: "hash-repeat").count }.from(0).to(1)

      expect {
        AutoCreateTenantTestAgent.call(tenant: { id: "hash-repeat" })
      }.not_to change { RubyLLM::Agents::Tenant.where(tenant_id: "hash-repeat").count }
    end
  end

  describe "execution records reference the correct tenant" do
    it "records the tenant_id on executions for pre-existing organizations" do
      insert_pre_existing_org(name: "Tracked Corp", slug: "tracked-corp")
      org = AutoCreateTestOrg.find_by(slug: "tracked-corp")

      AutoCreateTenantTestAgent.call(tenant: org)

      execution = RubyLLM::Agents::Execution.order(id: :desc).find_by(
        agent_type: "AutoCreateTenantTestAgent",
        tenant_id: "tracked-corp"
      )
      expect(execution).to be_present
      expect(execution.tenant_id).to eq("tracked-corp")
    end

    it "Tenant.for finds the auto-created record by tenant object" do
      insert_pre_existing_org(name: "Findable Corp", slug: "findable-corp")
      org = AutoCreateTestOrg.find_by(slug: "findable-corp")

      # Before: Tenant.for returns nil
      expect(RubyLLM::Agents::Tenant.for(org)).to be_nil

      AutoCreateTenantTestAgent.call(tenant: org)

      # After: Tenant.for returns the auto-created record
      tenant = RubyLLM::Agents::Tenant.for(org)
      expect(tenant).to be_present
      expect(tenant.tenant_id).to eq("findable-corp")
      expect(tenant.tenant_record).to eq(org)
    end
  end

  describe "no tenant (single-tenant mode)" do
    it "does not create any Tenant record" do
      initial_count = RubyLLM::Agents::Tenant.count

      AutoCreateTenantTestAgent.call

      expect(RubyLLM::Agents::Tenant.count).to eq(initial_count)
    end
  end
end
