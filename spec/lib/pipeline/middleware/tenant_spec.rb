# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Tenant do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      **options
    )
  end

  describe "#call" do
    context "with no tenant" do
      it "sets tenant fields to nil" do
        context = build_context
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to be_nil
        expect(result.tenant_object).to be_nil
        expect(result.tenant_config).to be_nil
      end

      it "calls the next middleware" do
        context = build_context
        expect(app).to receive(:call).with(context).and_return(context)

        middleware.call(context)
      end
    end

    context "with no tenant but tenant_resolver configured" do
      around do |example|
        original_multi_tenancy = RubyLLM::Agents.configuration.multi_tenancy_enabled
        original_resolver = RubyLLM::Agents.configuration.tenant_resolver

        example.run
      ensure
        RubyLLM::Agents.configuration.multi_tenancy_enabled = original_multi_tenancy
        RubyLLM::Agents.configuration.tenant_resolver = original_resolver
      end

      it "falls back to tenant_resolver when multi-tenancy is enabled" do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = true
        RubyLLM::Agents.configuration.tenant_resolver = -> { "resolved_123" }

        context = build_context
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("resolved_123")
        expect(result.tenant_object).to be_nil
        expect(result.tenant_config).to be_nil
      end

      it "returns nil when resolver returns nil" do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = true
        RubyLLM::Agents.configuration.tenant_resolver = -> {}

        context = build_context
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to be_nil
      end

      it "does not use resolver when multi-tenancy is disabled" do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
        RubyLLM::Agents.configuration.tenant_resolver = -> { "should_not_use" }

        context = build_context
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to be_nil
      end

      it "converts numeric resolver result to string" do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = true
        RubyLLM::Agents.configuration.tenant_resolver = -> { 42 }

        context = build_context
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("42")
      end

      it "prefers explicit tenant over resolver" do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = true
        RubyLLM::Agents.configuration.tenant_resolver = -> { "resolved_123" }

        context = build_context(tenant: {id: "explicit"})
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("explicit")
      end

      context "when resolver returns an object with llm_tenant_id" do
        let(:tenant_object_class) do
          Class.new do
            def llm_tenant_id
              "org_resolved"
            end

            def llm_config
              {model_override: "gpt-4o"}
            end
          end
        end

        it "extracts tenant_id from the resolved object" do
          resolved_obj = tenant_object_class.new
          RubyLLM::Agents.configuration.multi_tenancy_enabled = true
          RubyLLM::Agents.configuration.tenant_resolver = -> { resolved_obj }

          context = build_context
          allow(app).to receive(:call).with(context).and_return(context)

          result = middleware.call(context)

          expect(result.tenant_id).to eq("org_resolved")
        end

        it "sets tenant_object to the resolved object" do
          resolved_obj = tenant_object_class.new
          RubyLLM::Agents.configuration.multi_tenancy_enabled = true
          RubyLLM::Agents.configuration.tenant_resolver = -> { resolved_obj }

          context = build_context
          allow(app).to receive(:call).with(context).and_return(context)

          result = middleware.call(context)

          expect(result.tenant_object).to eq(resolved_obj)
        end

        it "extracts tenant_config via llm_config" do
          resolved_obj = tenant_object_class.new
          RubyLLM::Agents.configuration.multi_tenancy_enabled = true
          RubyLLM::Agents.configuration.tenant_resolver = -> { resolved_obj }

          context = build_context
          allow(app).to receive(:call).with(context).and_return(context)

          result = middleware.call(context)

          expect(result.tenant_config).to eq({model_override: "gpt-4o"})
        end

        it "handles resolved objects without llm_config" do
          simple_obj = Class.new do
            def llm_tenant_id
              "simple_resolved"
            end
          end.new

          RubyLLM::Agents.configuration.multi_tenancy_enabled = true
          RubyLLM::Agents.configuration.tenant_resolver = -> { simple_obj }

          context = build_context
          allow(app).to receive(:call).with(context).and_return(context)

          result = middleware.call(context)

          expect(result.tenant_id).to eq("simple_resolved")
          expect(result.tenant_object).to eq(simple_obj)
          expect(result.tenant_config).to be_nil
        end

        it "applies API keys from the resolved tenant object" do
          tenant_with_keys = Class.new do
            def llm_tenant_id
              "keys_resolved"
            end

            def llm_api_keys
              {openai: "sk-resolved-key"}
            end
          end.new

          saved_openai = RubyLLM.config.openai_api_key

          RubyLLM::Agents.configuration.multi_tenancy_enabled = true
          RubyLLM::Agents.configuration.tenant_resolver = -> { tenant_with_keys }

          context = build_context
          allow(app).to receive(:call).with(context).and_return(context)

          middleware.call(context)

          expect(RubyLLM.config.openai_api_key).to eq("sk-resolved-key")
        ensure
          RubyLLM.configure { |c| c.openai_api_key = saved_openai }
        end
      end
    end

    context "with hash tenant" do
      it "extracts tenant_id from hash" do
        context = build_context(tenant: {id: "org_123"})
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("org_123")
        expect(result.tenant_object).to be_nil
      end

      it "extracts tenant_object from hash with :object key" do
        mock_tenant = Object.new
        context = build_context(tenant: {id: "org_123", object: mock_tenant})
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("org_123")
        expect(result.tenant_object).to eq(mock_tenant)
      end

      it "extracts additional config from hash excluding :id and :object" do
        mock_tenant = Object.new
        context = build_context(tenant: {id: "org_123", object: mock_tenant, budget_limit: 100.0})
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("org_123")
        expect(result.tenant_object).to eq(mock_tenant)
        expect(result.tenant_config).to eq({budget_limit: 100.0})
      end

      it "converts numeric id to string" do
        context = build_context(tenant: {id: 123})
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("123")
      end
    end

    context "with object tenant" do
      let(:tenant_object) do
        Class.new do
          def llm_tenant_id
            "tenant_456"
          end

          def llm_config
            {model_override: "gpt-4"}
          end
        end.new
      end

      it "extracts tenant_id from object" do
        context = build_context(tenant: tenant_object)
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("tenant_456")
        expect(result.tenant_object).to eq(tenant_object)
      end

      it "extracts config from object with llm_config" do
        context = build_context(tenant: tenant_object)
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_config).to eq({model_override: "gpt-4"})
      end

      it "handles objects without llm_config" do
        simple_tenant = Class.new do
          def llm_tenant_id
            "simple_tenant"
          end
        end.new

        context = build_context(tenant: simple_tenant)
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("simple_tenant")
        expect(result.tenant_config).to be_nil
      end
    end

    context "with invalid tenant" do
      it "raises ArgumentError for objects without llm_tenant_id" do
        invalid_tenant = Object.new
        context = build_context(tenant: invalid_tenant)

        expect { middleware.call(context) }.to raise_error(ArgumentError, /must respond to :llm_tenant_id/)
      end
    end
  end

  describe "API key application from tenant object" do
    around do |example|
      # Save original RubyLLM config
      saved_openai = RubyLLM.config.openai_api_key
      saved_anthropic = RubyLLM.config.anthropic_api_key

      example.run

      # Restore original config
      RubyLLM.configure do |config|
        config.openai_api_key = saved_openai
        config.anthropic_api_key = saved_anthropic
      end
    end

    context "with tenant object providing llm_api_keys" do
      let(:tenant_with_keys) do
        Class.new do
          def llm_tenant_id
            "tenant_with_keys"
          end

          def llm_api_keys
            {openai: "sk-tenant-object-key"}
          end
        end.new
      end

      it "applies API keys from tenant object" do
        context = build_context(tenant: tenant_with_keys)
        allow(app).to receive(:call).with(context).and_return(context)

        middleware.call(context)

        expect(RubyLLM.config.openai_api_key).to eq("sk-tenant-object-key")
      end
    end

    context "error handling" do
      it "continues execution if API key resolution fails" do
        # Create a tenant object that raises an error
        error_tenant = Class.new do
          def llm_tenant_id
            "error_tenant"
          end

          def llm_api_keys
            raise StandardError, "API key lookup failed"
          end
        end.new

        context = build_context(tenant: error_tenant)
        allow(app).to receive(:call).with(context).and_return(context)

        # Should not raise, just log warning
        expect { middleware.call(context) }.not_to raise_error
      end
    end
  end
end
