# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent tenant integration" do
  # Create test table and model
  before(:all) do
    ActiveRecord::Base.connection.execute <<-SQL
      CREATE TABLE IF NOT EXISTS tenant_test_organizations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR(255),
        slug VARCHAR(255),
        created_at DATETIME,
        updated_at DATETIME
      )
    SQL

    # Define named test class for polymorphic associations to work
    unless Object.const_defined?(:TenantTestOrganization)
      Object.const_set(:TenantTestOrganization, Class.new(ActiveRecord::Base) do
        self.table_name = "tenant_test_organizations"

        include RubyLLM::Agents::LLMTenant

        llm_tenant id: :slug

        def to_s
          name
        end
      end)
    end

    # Define named test agent class
    unless Object.const_defined?(:TenantTestAgent)
      Object.const_set(:TenantTestAgent, Class.new(RubyLLM::Agents::Base) do
        model "gpt-4"
        version "1.0"

        def user_prompt
          "Hello"
        end
      end)
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS tenant_test_organizations")
    Object.send(:remove_const, :TenantTestOrganization) if Object.const_defined?(:TenantTestOrganization)
    Object.send(:remove_const, :TenantTestAgent) if Object.const_defined?(:TenantTestAgent)
    Object.send(:remove_const, :CustomTenantTestAgent) if Object.const_defined?(:CustomTenantTestAgent)
  end

  let(:organization_class) { TenantTestOrganization }
  let(:test_agent_class) { TenantTestAgent }

  let(:organization) do
    organization_class.create!(name: "Test Org", slug: "test-org")
  end

  # Define an agent with custom tenant method - needs to be dynamic due to organization reference
  let(:custom_tenant_agent_class) do
    org = organization

    # Clean up previous definition if exists
    Object.send(:remove_const, :CustomTenantTestAgent) if Object.const_defined?(:CustomTenantTestAgent)

    Object.const_set(:CustomTenantTestAgent, Class.new(RubyLLM::Agents::Base) do
      model "gpt-4"
      version "1.0"

      param :org_id

      define_method(:tenant) do
        org
      end

      def user_prompt
        "Hello with custom tenant"
      end
    end)
  end

  describe "#resolve_tenant_context!" do
    it "accepts tenant: param with object" do
      agent = test_agent_class.new(tenant: organization)

      expect(agent.resolved_tenant_id).to eq("test-org")
      expect(agent.resolved_tenant).to eq(organization)
    end

    it "returns nil when no tenant passed" do
      agent = test_agent_class.new

      expect(agent.resolved_tenant_id).to be_nil
      expect(agent.resolved_tenant).to be_nil
    end

    it "raises when tenant is a string" do
      expect {
        test_agent_class.new(tenant: "string-tenant")
      }.to raise_error(ArgumentError, /must be an object with llm_tenant_id/)
    end

    it "raises when tenant doesn't respond to llm_tenant_id" do
      expect {
        test_agent_class.new(tenant: Object.new)
      }.to raise_error(ArgumentError, /must respond to :llm_tenant_id/)
    end

    context "with custom tenant method in agent" do
      it "uses the overridden tenant method" do
        agent = custom_tenant_agent_class.new(org_id: 123)

        expect(agent.resolved_tenant_id).to eq("test-org")
        expect(agent.resolved_tenant).to eq(organization)
      end
    end

    context "with Hash tenant config" do
      it "extracts id from hash" do
        agent = test_agent_class.new(tenant: { id: "hash-tenant", daily_limit: 100 })

        expect(agent.resolved_tenant_id).to eq("hash-tenant")
        expect(agent.runtime_tenant_config).to eq({ daily_limit: 100 })
      end
    end
  end

  describe "tenant object interface" do
    let(:mock_tenant) do
      # Create a simple object that responds to llm_tenant_id
      mock = Object.new
      def mock.llm_tenant_id
        "mock-tenant-123"
      end
      mock
    end

    it "accepts any object responding to llm_tenant_id" do
      agent = test_agent_class.new(tenant: mock_tenant)

      expect(agent.resolved_tenant_id).to eq("mock-tenant-123")
      expect(agent.resolved_tenant).to eq(mock_tenant)
    end
  end
end
