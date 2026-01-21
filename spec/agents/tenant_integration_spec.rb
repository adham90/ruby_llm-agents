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

  describe "tenant resolution" do
    it "accepts tenant: param with object" do
      agent = test_agent_class.new(tenant: organization)

      expect(agent.resolved_tenant_id).to eq("test-org")
      # resolve_tenant returns { id: ..., object: ... } in new architecture
      resolved = agent.send(:resolve_tenant)
      expect(resolved[:object]).to eq(organization)
    end

    it "returns nil when no tenant passed" do
      agent = test_agent_class.new

      expect(agent.resolved_tenant_id).to be_nil
    end

    it "raises when tenant is a string" do
      agent = test_agent_class.new(tenant: "string-tenant")
      expect {
        agent.resolved_tenant_id
      }.to raise_error(ArgumentError, /tenant must be a Hash or respond to :llm_tenant_id/)
    end

    it "raises when tenant doesn't respond to llm_tenant_id" do
      agent = test_agent_class.new(tenant: Object.new)
      expect {
        agent.resolved_tenant_id
      }.to raise_error(ArgumentError, /tenant must be a Hash or respond to :llm_tenant_id/)
    end

    context "with custom tenant method in agent" do
      # NOTE: In the new architecture, custom tenant methods are no longer supported.
      # Tenants must be passed via the tenant: param at initialization.
      # If custom tenant resolution is needed, it should be done before calling the agent.
      it "requires tenant to be passed via tenant: param instead of custom method" do
        # Custom tenant methods are not supported in the new architecture
        # The agent must be initialized with the tenant: param
        agent = test_agent_class.new(tenant: organization)

        expect(agent.resolved_tenant_id).to eq("test-org")
      end
    end

    context "with Hash tenant config" do
      it "extracts id from hash" do
        agent = test_agent_class.new(tenant: { id: "hash-tenant", daily_limit: 100 })

        expect(agent.resolved_tenant_id).to eq("hash-tenant")
        # In new architecture, runtime config is part of the tenant hash itself
        resolved = agent.send(:resolve_tenant)
        expect(resolved[:daily_limit]).to eq(100)
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
      resolved = agent.send(:resolve_tenant)
      expect(resolved[:object]).to eq(mock_tenant)
    end
  end

  describe "api_keys integration" do
    # NOTE: API key resolution has been moved to the middleware pipeline in the new architecture.
    # These tests are pending re-implementation for the pipeline architecture.
    # The middleware would need to apply tenant API keys before execution.

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

    describe "tenant API key resolution" do
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

      it "extracts api_keys config from tenant object via llm_api_keys method" do
        # Create org with API keys
        org = api_keys_org

        # Build a mock chat client for the test
        mock_client = double("RubyLLM::Chat")
        allow(mock_client).to receive(:with_model).and_return(mock_client)
        allow(mock_client).to receive(:with_temperature).and_return(mock_client)
        allow(mock_client).to receive(:with_instructions).and_return(mock_client)
        allow(mock_client).to receive(:with_schema).and_return(mock_client)
        allow(mock_client).to receive(:with_tools).and_return(mock_client)
        allow(mock_client).to receive(:with_thinking).and_return(mock_client)
        allow(mock_client).to receive(:add_message).and_return(mock_client)
        allow(mock_client).to receive(:messages).and_return([])

        mock_response = double("RubyLLM::Message",
          content: "test response",
          input_tokens: 10,
          output_tokens: 20,
          model_id: "gpt-4",
          usage: { input_tokens: 10, output_tokens: 20 },
          finish_reason: "stop"
        )
        allow(mock_client).to receive(:ask).and_return(mock_response)

        key_at_execution = nil
        allow(RubyLLM).to receive(:chat) do
          key_at_execution = RubyLLM.config.openai_api_key
          mock_client
        end

        # Execute agent with tenant object
        agent = test_agent_class.new(tenant: org)
        agent.call

        # Verify that the tenant object's API key was applied
        expect(key_at_execution).to eq("sk-test-openai-123")
      end

      it "applies gemini key from tenant object method" do
        org = api_keys_org

        mock_client = double("RubyLLM::Chat")
        allow(mock_client).to receive(:with_model).and_return(mock_client)
        allow(mock_client).to receive(:with_temperature).and_return(mock_client)
        allow(mock_client).to receive(:with_instructions).and_return(mock_client)
        allow(mock_client).to receive(:with_schema).and_return(mock_client)
        allow(mock_client).to receive(:with_tools).and_return(mock_client)
        allow(mock_client).to receive(:with_thinking).and_return(mock_client)
        allow(mock_client).to receive(:add_message).and_return(mock_client)
        allow(mock_client).to receive(:messages).and_return([])

        mock_response = double("RubyLLM::Message",
          content: "test response",
          input_tokens: 10,
          output_tokens: 20,
          model_id: "gpt-4",
          usage: { input_tokens: 10, output_tokens: 20 },
          finish_reason: "stop"
        )
        allow(mock_client).to receive(:ask).and_return(mock_response)

        allow(RubyLLM).to receive(:chat).and_return(mock_client)

        # Execute agent with tenant object
        agent = test_agent_class.new(tenant: org)
        agent.call

        # Verify that the gemini key from method was applied
        expect(RubyLLM.config.gemini_api_key).to eq("test-gemini-key")
      end

      it "tenant object api_keys are applied via middleware before execution" do
        org = api_keys_org

        mock_client = double("RubyLLM::Chat")
        allow(mock_client).to receive(:with_model).and_return(mock_client)
        allow(mock_client).to receive(:with_temperature).and_return(mock_client)
        allow(mock_client).to receive(:with_instructions).and_return(mock_client)
        allow(mock_client).to receive(:with_schema).and_return(mock_client)
        allow(mock_client).to receive(:with_tools).and_return(mock_client)
        allow(mock_client).to receive(:with_thinking).and_return(mock_client)
        allow(mock_client).to receive(:add_message).and_return(mock_client)
        allow(mock_client).to receive(:messages).and_return([])

        mock_response = double("RubyLLM::Message",
          content: "test response",
          input_tokens: 10,
          output_tokens: 20,
          model_id: "gpt-4",
          usage: { input_tokens: 10, output_tokens: 20 },
          finish_reason: "stop"
        )
        allow(mock_client).to receive(:ask).and_return(mock_response)

        openai_key_during_execution = nil
        anthropic_key_during_execution = nil

        allow(RubyLLM).to receive(:chat) do
          openai_key_during_execution = RubyLLM.config.openai_api_key
          anthropic_key_during_execution = RubyLLM.config.anthropic_api_key
          mock_client
        end

        agent = test_agent_class.new(tenant: org)
        agent.call

        # Both keys should be applied from tenant object before the chat client is created
        expect(openai_key_during_execution).to eq("sk-test-openai-123")
        expect(anthropic_key_during_execution).to eq("sk-test-anthropic-456")
      end
    end
  end
end
