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

    context "with hash tenant" do
      it "extracts tenant_id from hash" do
        context = build_context(tenant: { id: "org_123" })
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("org_123")
        expect(result.tenant_object).to be_nil
      end

      it "extracts additional config from hash" do
        context = build_context(tenant: { id: "org_123", budget_limit: 100.0 })
        allow(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)

        expect(result.tenant_id).to eq("org_123")
        expect(result.tenant_config).to eq({ budget_limit: 100.0 })
      end

      it "converts numeric id to string" do
        context = build_context(tenant: { id: 123 })
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
            { model_override: "gpt-4" }
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

        expect(result.tenant_config).to eq({ model_override: "gpt-4" })
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
end
