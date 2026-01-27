# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Tenant::Configurable do
  let(:tenant) { RubyLLM::Agents::Tenant.create!(tenant_id: "test_tenant_#{SecureRandom.hex(4)}") }

  after { tenant.destroy }

  describe "association" do
    it "has one api_configuration" do
      expect(tenant).to respond_to(:api_configuration)
    end

    it "creates api_configuration with correct scope" do
      config = tenant.api_configuration!

      expect(config.scope_type).to eq("tenant")
      expect(config.scope_id).to eq(tenant.tenant_id)
    end

    it "destroys api_configuration when tenant is destroyed" do
      config = tenant.api_configuration!
      config_id = config.id

      tenant.destroy

      expect(RubyLLM::Agents::ApiConfiguration.find_by(id: config_id)).to be_nil
    end
  end

  describe "#api_key_for" do
    context "without api_configuration" do
      it "returns nil" do
        expect(tenant.api_key_for(:openai)).to be_nil
      end
    end

    context "with api_configuration" do
      before do
        tenant.api_configuration!.update!(openai_api_key: "sk-test-key")
      end

      it "returns the API key for the provider" do
        expect(tenant.api_key_for(:openai)).to eq("sk-test-key")
      end

      it "returns nil for unconfigured providers" do
        expect(tenant.api_key_for(:anthropic)).to be_nil
      end

      it "handles string provider names" do
        expect(tenant.api_key_for("openai")).to eq("sk-test-key")
      end
    end
  end

  describe "#has_custom_api_keys?" do
    it "returns false without configuration" do
      expect(tenant.has_custom_api_keys?).to be false
    end

    it "returns true with configuration" do
      tenant.api_configuration!
      expect(tenant.has_custom_api_keys?).to be true
    end
  end

  describe "#effective_api_configuration" do
    it "returns a resolved configuration" do
      config = tenant.effective_api_configuration
      expect(config).to be_a(RubyLLM::Agents::ResolvedConfig)
    end
  end

  describe "#api_configuration!" do
    it "creates configuration if not exists" do
      expect { tenant.api_configuration! }.to change {
        RubyLLM::Agents::ApiConfiguration.count
      }.by(1)
    end

    it "returns existing configuration if exists" do
      existing = tenant.api_configuration!
      expect(tenant.api_configuration!).to eq(existing)
    end
  end

  describe "#configure_api" do
    it "yields the configuration" do
      expect { |b| tenant.configure_api(&b) }.to yield_with_args(RubyLLM::Agents::ApiConfiguration)
    end

    it "saves the configuration" do
      tenant.configure_api do |config|
        config.openai_api_key = "sk-new-key"
      end

      expect(tenant.api_key_for(:openai)).to eq("sk-new-key")
    end

    it "returns the configuration" do
      result = tenant.configure_api { |c| c.anthropic_api_key = "sk-ant-test" }
      expect(result).to be_a(RubyLLM::Agents::ApiConfiguration)
    end
  end

  describe "#provider_configured?" do
    before { tenant.api_configuration!.update!(gemini_api_key: "gemini-key") }

    it "returns true for configured providers" do
      expect(tenant.provider_configured?(:gemini)).to be true
    end

    it "returns false for unconfigured providers" do
      expect(tenant.provider_configured?(:openai)).to be false
    end
  end

  describe "#configured_providers" do
    context "without configuration" do
      it "returns empty array" do
        expect(tenant.configured_providers).to eq([])
      end
    end

    context "with configuration" do
      before do
        tenant.api_configuration!.update!(
          openai_api_key: "sk-openai",
          anthropic_api_key: "sk-anthropic"
        )
      end

      it "returns list of configured provider symbols" do
        providers = tenant.configured_providers
        expect(providers).to include(:openai)
        expect(providers).to include(:anthropic)
        expect(providers).not_to include(:gemini)
      end
    end
  end

  describe "#default_model" do
    it "returns nil without configuration" do
      expect(tenant.default_model).to be_nil
    end

    it "returns the default model when configured" do
      tenant.api_configuration!.update!(default_model: "gpt-4o")
      expect(tenant.default_model).to eq("gpt-4o")
    end
  end

  describe "#default_embedding_model" do
    it "returns nil without configuration" do
      expect(tenant.default_embedding_model).to be_nil
    end

    it "returns the default embedding model when configured" do
      tenant.api_configuration!.update!(default_embedding_model: "text-embedding-3-small")
      expect(tenant.default_embedding_model).to eq("text-embedding-3-small")
    end
  end
end
