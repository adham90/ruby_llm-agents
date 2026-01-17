# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ApiConfigurationsController, type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  # Skip all tests if the table doesn't exist (migration not run)
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_api_configurations)
      skip "ApiConfiguration table not available - run migration first"
    end
  end

  before do
    RubyLLM::Agents::ApiConfiguration.delete_all
  end

  describe "GET #show" do
    it "returns http success" do
      get :show
      expect(response).to have_http_status(:ok)
    end

    it "assigns @config" do
      get :show
      expect(assigns(:config)).to be_a(RubyLLM::Agents::ApiConfiguration)
    end

    it "assigns @resolved" do
      get :show
      expect(assigns(:resolved)).to be_a(RubyLLM::Agents::ResolvedConfig)
    end

    it "assigns @provider_statuses" do
      get :show
      expect(assigns(:provider_statuses)).to be_an(Array)
    end

    it "creates global config if not exists" do
      expect { get :show }.to change { RubyLLM::Agents::ApiConfiguration.count }.by(1)
    end
  end

  describe "GET #edit" do
    it "returns http success" do
      get :edit
      expect(response).to have_http_status(:ok)
    end

    it "assigns @config" do
      get :edit
      expect(assigns(:config)).to be_a(RubyLLM::Agents::ApiConfiguration)
      expect(assigns(:config).scope_type).to eq("global")
    end
  end

  describe "PATCH #update" do
    let!(:config) { RubyLLM::Agents::ApiConfiguration.global }

    context "with valid params" do
      it "updates the configuration" do
        patch :update, params: {
          api_configuration: {
            openai_api_key: "sk-new-key",
            default_model: "gpt-4"
          }
        }
        config.reload
        expect(config.openai_api_key).to eq("sk-new-key")
        expect(config.default_model).to eq("gpt-4")
      end

      it "redirects to edit" do
        patch :update, params: { api_configuration: { default_model: "gpt-4" } }
        expect(response).to redirect_to(edit_api_configuration_path)
      end

      it "sets a flash notice" do
        patch :update, params: { api_configuration: { default_model: "gpt-4" } }
        expect(flash[:notice]).to be_present
      end

      it "ignores blank API keys" do
        config.update!(openai_api_key: "existing-key")
        patch :update, params: {
          api_configuration: {
            openai_api_key: "",
            default_model: "gpt-4"
          }
        }
        config.reload
        expect(config.openai_api_key).to eq("existing-key")
      end
    end
  end

  describe "GET #tenant" do
    before do
      # Create a tenant budget for the test
      if ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_tenant_budgets)
        RubyLLM::Agents::TenantBudget.find_or_create_by!(tenant_id: "test_tenant")
      end
    end

    it "returns http success" do
      get :tenant, params: { tenant_id: "test_tenant" }
      expect(response).to have_http_status(:ok)
    end

    it "assigns @tenant_id" do
      get :tenant, params: { tenant_id: "test_tenant" }
      expect(assigns(:tenant_id)).to eq("test_tenant")
    end

    it "assigns @config for the tenant" do
      RubyLLM::Agents::ApiConfiguration.for_tenant!("test_tenant")
      get :tenant, params: { tenant_id: "test_tenant" }
      expect(assigns(:config).scope_id).to eq("test_tenant")
    end

    it "assigns @resolved" do
      get :tenant, params: { tenant_id: "test_tenant" }
      expect(assigns(:resolved)).to be_a(RubyLLM::Agents::ResolvedConfig)
    end
  end

  describe "GET #edit_tenant" do
    it "returns http success" do
      get :edit_tenant, params: { tenant_id: "test_tenant" }
      expect(response).to have_http_status(:ok)
    end

    it "assigns @tenant_id" do
      get :edit_tenant, params: { tenant_id: "test_tenant" }
      expect(assigns(:tenant_id)).to eq("test_tenant")
    end

    it "creates tenant config if not exists" do
      expect {
        get :edit_tenant, params: { tenant_id: "new_tenant" }
      }.to change { RubyLLM::Agents::ApiConfiguration.count }.by(1)
    end
  end

  describe "PATCH #update_tenant" do
    let(:tenant_id) { "test_tenant" }
    let!(:config) { RubyLLM::Agents::ApiConfiguration.for_tenant!(tenant_id) }

    context "with valid params" do
      it "updates the tenant configuration" do
        patch :update_tenant, params: {
          tenant_id: tenant_id,
          api_configuration: {
            openai_api_key: "sk-tenant-key",
            inherit_global_defaults: false
          }
        }
        config.reload
        expect(config.openai_api_key).to eq("sk-tenant-key")
        expect(config.inherit_global_defaults).to be false
      end

      it "redirects to tenant edit" do
        patch :update_tenant, params: {
          tenant_id: tenant_id,
          api_configuration: { default_model: "gpt-4" }
        }
        expect(response).to redirect_to(edit_tenant_api_configuration_path(tenant_id))
      end

      it "sets a flash notice" do
        patch :update_tenant, params: {
          tenant_id: tenant_id,
          api_configuration: { default_model: "gpt-4" }
        }
        expect(flash[:notice]).to be_present
      end
    end
  end

  describe "parameter filtering" do
    it "permits API key attributes" do
      patch :update, params: {
        api_configuration: {
          openai_api_key: "test",
          anthropic_api_key: "test",
          gemini_api_key: "test"
        }
      }
      expect(response).to redirect_to(edit_api_configuration_path)
    end

    it "permits endpoint attributes" do
      patch :update, params: {
        api_configuration: {
          openai_api_base: "https://custom.api.com",
          ollama_api_base: "http://localhost:11434"
        }
      }
      expect(response).to redirect_to(edit_api_configuration_path)
    end

    it "permits connection settings" do
      patch :update, params: {
        api_configuration: {
          request_timeout: 60,
          max_retries: 3
        }
      }
      expect(response).to redirect_to(edit_api_configuration_path)
    end

    it "permits inherit_global_defaults for tenant" do
      RubyLLM::Agents::ApiConfiguration.for_tenant!("test")
      patch :update_tenant, params: {
        tenant_id: "test",
        api_configuration: {
          inherit_global_defaults: true
        }
      }
      expect(response).to redirect_to(edit_tenant_api_configuration_path("test"))
    end
  end
end
