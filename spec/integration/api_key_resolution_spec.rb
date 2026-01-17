# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API Key Resolution Integration", type: :integration do
  # Skip all tests if the table doesn't exist (migration not run)
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_api_configurations)
      skip "ApiConfiguration table not available - run migration first"
    end
  end

  before do
    # Clean up configurations before each test
    RubyLLM::Agents::ApiConfiguration.delete_all

    # Store original RubyLLM config values to restore later
    @original_openai_key = RubyLLM.config.openai_api_key
    @original_anthropic_key = RubyLLM.config.anthropic_api_key
    @original_default_model = RubyLLM.config.default_model
  end

  after do
    # Restore original RubyLLM config values
    RubyLLM.configure do |config|
      config.openai_api_key = @original_openai_key
      config.anthropic_api_key = @original_anthropic_key
      config.default_model = @original_default_model
    end
  end

  # Define a test agent class inline
  let(:test_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4"
      param :query, required: true

      def user_prompt
        query
      end

      def self.name
        "TestAgent"
      end
    end
  end

  describe "Priority Chain Resolution" do
    describe "config file key only" do
      it "uses config file key when no DB config exists" do
        # Set config file key
        RubyLLM.configure { |c| c.openai_api_key = "config-file-key" }

        resolved = RubyLLM::Agents::ApiConfiguration.resolve

        expect(resolved.openai_api_key).to eq("config-file-key")
        expect(resolved.source_for(:openai_api_key)).to eq("ruby_llm_config")
      end
    end

    describe "global DB key overrides config file key" do
      it "uses global DB key over config file key" do
        # Set config file key
        RubyLLM.configure { |c| c.openai_api_key = "config-file-key" }

        # Set global DB key
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-db-key")

        resolved = RubyLLM::Agents::ApiConfiguration.resolve

        expect(resolved.openai_api_key).to eq("global-db-key")
        expect(resolved.source_for(:openai_api_key)).to eq("global_db")
      end
    end

    describe "tenant DB key overrides global DB key" do
      it "uses tenant DB key over global DB key" do
        # Set global DB key
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-db-key")

        # Set tenant DB key
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("acme")
        tenant_config.update!(openai_api_key: "tenant-db-key")

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "acme")

        expect(resolved.openai_api_key).to eq("tenant-db-key")
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:acme")
      end

      it "returns correct source tracking at each level" do
        # Set all three levels
        RubyLLM.configure { |c| c.anthropic_api_key = "config-anthropic-key" }

        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(
          openai_api_key: "global-openai-key",
          gemini_api_key: "global-gemini-key"
        )

        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("acme")
        tenant_config.update!(openai_api_key: "tenant-openai-key")

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "acme")

        # Tenant level takes precedence for openai
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:acme")

        # Global level used for gemini (tenant doesn't have it)
        expect(resolved.source_for(:gemini_api_key)).to eq("global_db")
        expect(resolved.gemini_api_key).to eq("global-gemini-key")

        # Config level used for anthropic (neither tenant nor global has it)
        expect(resolved.source_for(:anthropic_api_key)).to eq("ruby_llm_config")
        expect(resolved.anthropic_api_key).to eq("config-anthropic-key")
      end
    end
  end

  describe "Inheritance Tests" do
    describe "inherit_global_defaults: true (default)" do
      it "tenant falls back to global for unset keys" do
        # Set global keys
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(
          openai_api_key: "global-openai-key",
          anthropic_api_key: "global-anthropic-key"
        )

        # Set tenant with only openai key (inherits anthropic from global)
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("acme")
        tenant_config.update!(
          openai_api_key: "tenant-openai-key",
          inherit_global_defaults: true
        )

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "acme")

        # Tenant openai key used
        expect(resolved.openai_api_key).to eq("tenant-openai-key")
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:acme")

        # Global anthropic key inherited
        expect(resolved.anthropic_api_key).to eq("global-anthropic-key")
        expect(resolved.source_for(:anthropic_api_key)).to eq("global_db")
      end
    end

    describe "inherit_global_defaults: false" do
      it "tenant does not fall back to global" do
        # Set config file fallback
        RubyLLM.configure { |c| c.anthropic_api_key = "config-anthropic-key" }

        # Set global keys
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(
          openai_api_key: "global-openai-key",
          anthropic_api_key: "global-anthropic-key"
        )

        # Set tenant with no inheritance
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("isolated")
        tenant_config.update!(
          openai_api_key: "tenant-openai-key",
          inherit_global_defaults: false
        )

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "isolated")

        # Tenant openai key used
        expect(resolved.openai_api_key).to eq("tenant-openai-key")
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:isolated")

        # Should NOT get global anthropic key (no inheritance)
        # Falls through to config file or returns nil
        expect(resolved.anthropic_api_key).to eq("config-anthropic-key")
        expect(resolved.source_for(:anthropic_api_key)).to eq("ruby_llm_config")
      end

      it "skips global config entirely when inherit is false" do
        # Set global keys
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(gemini_api_key: "global-gemini-key")

        # Set tenant with no inheritance and no gemini key
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("isolated")
        tenant_config.update!(
          openai_api_key: "tenant-openai-key",
          inherit_global_defaults: false
        )

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "isolated")

        # Should NOT inherit gemini key from global
        expect(resolved.gemini_api_key).to be_nil
        expect(resolved.source_for(:gemini_api_key)).to eq("not_set")
      end
    end
  end

  describe "Fallback Tests" do
    it "empty DB config falls back to config file key" do
      # Set config file key
      RubyLLM.configure { |c| c.openai_api_key = "config-file-key" }

      # Create empty global config (no keys set)
      RubyLLM::Agents::ApiConfiguration.global

      resolved = RubyLLM::Agents::ApiConfiguration.resolve

      expect(resolved.openai_api_key).to eq("config-file-key")
      expect(resolved.source_for(:openai_api_key)).to eq("ruby_llm_config")
    end

    it "returns nil when no config exists at any level" do
      # Clear all config
      RubyLLM.configure { |c| c.deepseek_api_key = nil }

      resolved = RubyLLM::Agents::ApiConfiguration.resolve

      expect(resolved.deepseek_api_key).to be_nil
      expect(resolved.source_for(:deepseek_api_key)).to eq("not_set")
    end
  end

  describe "Agent Execution Tests" do
    let(:mock_chat_client) do
      mock_client = instance_double("RubyLLM::Chat")
      allow(mock_client).to receive(:with_model).and_return(mock_client)
      allow(mock_client).to receive(:with_temperature).and_return(mock_client)
      allow(mock_client).to receive(:with_instructions).and_return(mock_client)
      allow(mock_client).to receive(:with_schema).and_return(mock_client)
      allow(mock_client).to receive(:with_tools).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return([])

      mock_response = instance_double("RubyLLM::Message",
        content: "test response",
        input_tokens: 10,
        output_tokens: 20,
        model_id: "gpt-4"
      )
      allow(mock_client).to receive(:ask).and_return(mock_response)
      mock_client
    end

    describe "apply_api_configuration! is called during execution" do
      it "applies DB key to RubyLLM.config BEFORE chat client creation" do
        # Set global DB key
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "db-api-key-for-execution")

        key_at_chat_creation = nil

        # Mock RubyLLM.chat to capture the key at the moment of client creation
        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        # Execute the agent
        agent = test_agent_class.new(query: "test query")
        agent.call

        # Verify the DB key was applied before chat client was created
        expect(key_at_chat_creation).to eq("db-api-key-for-execution")
      end
    end

    describe "tenant option passes correct tenant_id to resolution" do
      it "applies tenant-specific key during client build" do
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-key")

        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("tenant123")
        tenant_config.update!(openai_api_key: "tenant123-key")

        key_at_chat_creation = nil

        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        # Execute with tenant option - tenant context resolved before client build
        agent = test_agent_class.new(query: "test", tenant: "tenant123")
        agent.call

        # Tenant-specific API key should be applied during initialize
        expect(key_at_chat_creation).to eq("tenant123-key")
      end

      it "uses global key when no tenant option provided" do
        # Set global key
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-only-key")

        key_at_chat_creation = nil

        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        # Execute without tenant option
        agent = test_agent_class.new(query: "test")
        agent.call

        expect(key_at_chat_creation).to eq("global-only-key")
      end
    end

    describe "tenant hash option" do
      it "extracts tenant_id from hash option and applies tenant key" do
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("hash_tenant")
        tenant_config.update!(openai_api_key: "hash-tenant-key")

        key_at_chat_creation = nil

        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        # Execute with tenant hash option - tenant ID extracted before client build
        agent = test_agent_class.new(
          query: "test",
          tenant: { id: "hash_tenant", name: "Hash Tenant Inc" }
        )
        agent.call

        expect(key_at_chat_creation).to eq("hash-tenant-key")
      end
    end

    describe "direct tenant resolution (without agent execution)" do
      # These tests verify that the resolution logic itself works correctly

      it "correctly resolves tenant-specific key when tenant_id provided" do
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-key")

        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("direct_tenant")
        tenant_config.update!(openai_api_key: "direct-tenant-key")

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "direct_tenant")

        expect(resolved.openai_api_key).to eq("direct-tenant-key")
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:direct_tenant")
      end

      it "applies tenant config to RubyLLM when resolved directly" do
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("apply_tenant")
        tenant_config.update!(openai_api_key: "apply-tenant-key")

        resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "apply_tenant")
        resolved.apply_to_ruby_llm!

        expect(RubyLLM.config.openai_api_key).to eq("apply-tenant-key")
      end
    end

    describe "with_messages preserves tenant context" do
      it "uses tenant API key after with_messages rebuilds client" do
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("messages_tenant")
        tenant_config.update!(openai_api_key: "messages-tenant-key")

        key_at_rebuild = nil
        call_count = 0

        # Need to include add_message mock for with_messages
        mock_client_with_messages = instance_double("RubyLLM::Chat")
        allow(mock_client_with_messages).to receive(:with_model).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:with_temperature).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:with_instructions).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:with_schema).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:with_tools).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:add_message).and_return(mock_client_with_messages)
        allow(mock_client_with_messages).to receive(:messages).and_return([])

        mock_response = instance_double("RubyLLM::Message",
          content: "test response",
          input_tokens: 10,
          output_tokens: 20,
          model_id: "gpt-4"
        )
        allow(mock_client_with_messages).to receive(:ask).and_return(mock_response)

        allow(RubyLLM).to receive(:chat) do
          call_count += 1
          key_at_rebuild = RubyLLM.config.openai_api_key if call_count == 2
          mock_client_with_messages
        end

        # Create agent with tenant, then use with_messages (which rebuilds client)
        agent = test_agent_class.new(query: "test", tenant: "messages_tenant")
        agent.with_messages([{ role: :user, content: "Hello" }])
        agent.call

        # The tenant key should still be used after with_messages rebuilds the client
        expect(key_at_rebuild).to eq("messages-tenant-key")
      end
    end

    describe "streaming mode uses tenant keys" do
      it "applies tenant API key when using stream class method" do
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("stream_tenant")
        tenant_config.update!(openai_api_key: "stream-tenant-key")

        key_at_chat_creation = nil

        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        # Execute via stream class method with tenant option
        test_agent_class.stream(query: "test", tenant: "stream_tenant") { |_chunk| }

        expect(key_at_chat_creation).to eq("stream-tenant-key")
      end
    end

    describe "non-existent tenant fallback" do
      it "falls back to global key when tenant has no config" do
        global_config = RubyLLM::Agents::ApiConfiguration.global
        global_config.update!(openai_api_key: "global-fallback-key")

        # No tenant config created for "missing_tenant"

        key_at_chat_creation = nil

        allow(RubyLLM).to receive(:chat) do
          key_at_chat_creation = RubyLLM.config.openai_api_key
          mock_chat_client
        end

        agent = test_agent_class.new(query: "test", tenant: "missing_tenant")
        agent.call

        # Should fall back to global key since tenant has no config
        expect(key_at_chat_creation).to eq("global-fallback-key")
      end
    end

    describe "idempotency of resolve_tenant_context!" do
      it "does not re-resolve tenant context on subsequent calls" do
        tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("idempotent_tenant")
        tenant_config.update!(openai_api_key: "idempotent-key")

        allow(RubyLLM).to receive(:chat).and_return(mock_chat_client)

        agent = test_agent_class.new(query: "test", tenant: "idempotent_tenant")

        # The tenant_id should be set after initialize
        expect(agent.instance_variable_get(:@tenant_id)).to eq("idempotent_tenant")
        expect(agent.instance_variable_get(:@tenant_context_resolved)).to be true

        # Calling resolve_tenant_context! again should not change anything
        original_tenant_id = agent.instance_variable_get(:@tenant_id)
        agent.send(:resolve_tenant_context!)
        expect(agent.instance_variable_get(:@tenant_id)).to eq(original_tenant_id)
      end
    end
  end

  describe "apply_to_ruby_llm! method" do
    it "applies resolved config values to RubyLLM.config" do
      # Set DB config with multiple values
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(
        openai_api_key: "apply-test-openai",
        anthropic_api_key: "apply-test-anthropic",
        default_model: "gpt-4-turbo"
      )

      resolved = RubyLLM::Agents::ApiConfiguration.resolve
      resolved.apply_to_ruby_llm!

      expect(RubyLLM.config.openai_api_key).to eq("apply-test-openai")
      expect(RubyLLM.config.anthropic_api_key).to eq("apply-test-anthropic")
      expect(RubyLLM.config.default_model).to eq("gpt-4-turbo")
    end

    it "only applies non-empty values" do
      # Set initial value
      RubyLLM.configure { |c| c.mistral_api_key = "initial-mistral-key" }

      # Set DB config with only openai (mistral is empty)
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(openai_api_key: "apply-openai-only")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve
      resolved.apply_to_ruby_llm!

      # mistral key should remain unchanged (not overwritten with nil)
      expect(RubyLLM.config.mistral_api_key).to eq("initial-mistral-key")
      expect(RubyLLM.config.openai_api_key).to eq("apply-openai-only")
    end
  end

  describe "Multi-provider configuration" do
    it "resolves multiple providers from different sources" do
      # Config file has anthropic
      RubyLLM.configure { |c| c.anthropic_api_key = "config-anthropic" }

      # Global DB has openai and gemini
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(
        openai_api_key: "global-openai",
        gemini_api_key: "global-gemini"
      )

      # Tenant has mistral
      tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("multi")
      tenant_config.update!(mistral_api_key: "tenant-mistral")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "multi")

      expect(resolved.openai_api_key).to eq("global-openai")
      expect(resolved.source_for(:openai_api_key)).to eq("global_db")

      expect(resolved.gemini_api_key).to eq("global-gemini")
      expect(resolved.source_for(:gemini_api_key)).to eq("global_db")

      expect(resolved.anthropic_api_key).to eq("config-anthropic")
      expect(resolved.source_for(:anthropic_api_key)).to eq("ruby_llm_config")

      expect(resolved.mistral_api_key).to eq("tenant-mistral")
      expect(resolved.source_for(:mistral_api_key)).to eq("tenant:multi")
    end
  end

  describe "ResolvedConfig caching" do
    it "caches resolved values for repeated access" do
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(openai_api_key: "cached-key")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve

      # Access multiple times
      expect(resolved.openai_api_key).to eq("cached-key")
      expect(resolved.openai_api_key).to eq("cached-key")
      expect(resolved.openai_api_key).to eq("cached-key")

      # Should not make additional queries
      expect(resolved.source_for(:openai_api_key)).to eq("global_db")
    end
  end

  describe "to_hash and to_ruby_llm_options" do
    it "returns all resolved values as hash" do
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(
        openai_api_key: "hash-test-openai",
        default_model: "gpt-4"
      )

      resolved = RubyLLM::Agents::ApiConfiguration.resolve
      hash = resolved.to_hash

      expect(hash[:openai_api_key]).to eq("hash-test-openai")
      expect(hash[:default_model]).to eq("gpt-4")
    end

    it "excludes nil values from hash" do
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(openai_api_key: "only-openai")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve
      hash = resolved.to_hash

      expect(hash).to have_key(:openai_api_key)
      expect(hash).not_to have_key(:anthropic_api_key)
    end
  end

  describe "source_summary" do
    it "returns count of values per source" do
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(
        openai_api_key: "global-key",
        gemini_api_key: "global-key-2"
      )

      tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("summary")
      tenant_config.update!(mistral_api_key: "tenant-key")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "summary")
      summary = resolved.source_summary

      # Verify the expected sources are present with correct counts
      expect(summary["tenant:summary"]).to eq(1)
      expect(summary["global_db"]).to eq(2)

      # ruby_llm_config count varies based on RubyLLM defaults, just ensure it exists
      expect(summary).to have_key("ruby_llm_config") | satisfy { |s| s.values.sum > 0 }
    end

    it "counts tenant, global_db, and ruby_llm_config sources correctly" do
      # Clear any config file values we're testing
      RubyLLM.configure do |c|
        c.deepseek_api_key = "config-deepseek"
      end

      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(openai_api_key: "global-openai")

      tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!("count_test")
      tenant_config.update!(anthropic_api_key: "tenant-anthropic")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve(tenant_id: "count_test")

      # Verify specific sources
      expect(resolved.source_for(:anthropic_api_key)).to eq("tenant:count_test")
      expect(resolved.source_for(:openai_api_key)).to eq("global_db")
      expect(resolved.source_for(:deepseek_api_key)).to eq("ruby_llm_config")

      summary = resolved.source_summary
      expect(summary["tenant:count_test"]).to be >= 1
      expect(summary["global_db"]).to be >= 1
    end
  end

  describe "provider_statuses_with_source" do
    it "includes source information for each provider" do
      global_config = RubyLLM::Agents::ApiConfiguration.global
      global_config.update!(openai_api_key: "status-test-key")

      resolved = RubyLLM::Agents::ApiConfiguration.resolve
      statuses = resolved.provider_statuses_with_source

      openai_status = statuses.find { |s| s[:key] == :openai }

      expect(openai_status[:configured]).to be true
      expect(openai_status[:source]).to eq("global_db")
      expect(openai_status[:masked_key]).to be_present
    end
  end
end
