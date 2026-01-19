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

  describe "api_keys integration" do
    # Create org class with api_keys DSL
    before(:all) do
      ActiveRecord::Base.connection.execute <<-SQL
        CREATE TABLE IF NOT EXISTS api_keys_test_orgs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name VARCHAR(255),
          slug VARCHAR(255),
          openai_key VARCHAR(255),
          anthropic_key VARCHAR(255),
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL

      unless Object.const_defined?(:ApiKeysTestOrg)
        Object.const_set(:ApiKeysTestOrg, Class.new(ActiveRecord::Base) do
          self.table_name = "api_keys_test_orgs"

          include RubyLLM::Agents::LLMTenant

          llm_tenant(
            id: :slug,
            api_keys: {
              openai: :openai_key,
              anthropic: :anthropic_key,
              gemini: :fetch_gemini_key
            }
          )

          def fetch_gemini_key
            "test-gemini-key"
          end
        end)
      end
    end

    after(:all) do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS api_keys_test_orgs")
      Object.send(:remove_const, :ApiKeysTestOrg) if Object.const_defined?(:ApiKeysTestOrg)
    end

    let(:api_keys_org_class) { ApiKeysTestOrg }

    let(:api_keys_org) do
      api_keys_org_class.create!(
        name: "API Keys Org",
        slug: "api-keys-org",
        openai_key: "sk-test-openai-123",
        anthropic_key: "sk-test-anthropic-456"
      )
    end

    # Use around hook to guarantee cleanup of RubyLLM config
    around do |example|
      saved_openai = RubyLLM.config.openai_api_key
      saved_anthropic = RubyLLM.config.anthropic_api_key
      saved_gemini = RubyLLM.config.gemini_api_key

      example.run

      RubyLLM.configure do |config|
        config.openai_api_key = saved_openai
        config.anthropic_api_key = saved_anthropic
        config.gemini_api_key = saved_gemini
      end
    end

    describe "#apply_tenant_object_api_keys!" do
      it "applies api keys from tenant object to RubyLLM config" do
        agent = test_agent_class.new(tenant: api_keys_org)
        agent.send(:resolve_tenant_context!)

        agent.send(:apply_tenant_object_api_keys!)

        expect(RubyLLM.config.openai_api_key).to eq("sk-test-openai-123")
        expect(RubyLLM.config.anthropic_api_key).to eq("sk-test-anthropic-456")
      end

      it "applies api keys from custom methods" do
        agent = test_agent_class.new(tenant: api_keys_org)
        agent.send(:resolve_tenant_context!)

        agent.send(:apply_tenant_object_api_keys!)

        expect(RubyLLM.config.gemini_api_key).to eq("test-gemini-key")
      end

      it "does nothing when tenant has no llm_api_keys method" do
        agent = test_agent_class.new(tenant: organization)
        agent.send(:resolve_tenant_context!)

        expect {
          agent.send(:apply_tenant_object_api_keys!)
        }.not_to raise_error
      end
    end

    describe "#apply_runtime_tenant_api_keys!" do
      it "applies api keys from runtime hash config" do
        agent = test_agent_class.new(
          tenant: {
            id: "hash-tenant",
            api_keys: {
              openai: "runtime-openai-key",
              anthropic: "runtime-anthropic-key"
            }
          }
        )
        agent.send(:resolve_tenant_context!)

        agent.send(:apply_runtime_tenant_api_keys!)

        expect(RubyLLM.config.openai_api_key).to eq("runtime-openai-key")
        expect(RubyLLM.config.anthropic_api_key).to eq("runtime-anthropic-key")
      end

      it "does nothing when runtime config has no api_keys" do
        agent = test_agent_class.new(tenant: { id: "simple-tenant" })
        agent.send(:resolve_tenant_context!)

        expect {
          agent.send(:apply_runtime_tenant_api_keys!)
        }.not_to raise_error
      end
    end

    describe "precedence" do
      it "tenant object api_keys take precedence over runtime api_keys" do
        # This tests that when both are available, the tenant object's keys are used
        # since apply_tenant_object_api_keys! is called before apply_runtime_tenant_api_keys!
        agent = test_agent_class.new(tenant: api_keys_org)
        agent.send(:resolve_tenant_context!)

        agent.send(:apply_api_configuration!)

        # Should use tenant object's key, not any default
        expect(RubyLLM.config.openai_api_key).to eq("sk-test-openai-123")
      end
    end
  end
end
