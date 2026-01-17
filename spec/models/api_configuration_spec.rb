# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ApiConfiguration, type: :model do
  # Skip all tests if the table doesn't exist (migration not run)
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_api_configurations)
      skip "ApiConfiguration table not available - run migration first"
    end
  end

  before do
    # Clean up before each test
    described_class.delete_all
  end

  describe "validations" do
    it "requires scope_type" do
      config = described_class.new(scope_type: nil)
      expect(config).not_to be_valid
      expect(config.errors[:scope_type]).to include("can't be blank")
    end

    it "validates scope_type inclusion" do
      config = described_class.new(scope_type: "invalid")
      expect(config).not_to be_valid
      expect(config.errors[:scope_type]).to be_present
    end

    it "accepts valid scope_types" do
      %w[global tenant].each do |scope|
        config = described_class.new(scope_type: scope)
        config.scope_id = "test" if scope == "tenant"
        expect(config.errors[:scope_type]).to be_empty if config.valid?
      end
    end

    it "requires scope_id to be nil for global scope" do
      config = described_class.new(scope_type: "global", scope_id: "some_id")
      expect(config).not_to be_valid
      expect(config.errors[:scope_id]).to include("must be nil for global scope")
    end

    it "requires scope_id to be present for tenant scope" do
      config = described_class.new(scope_type: "tenant", scope_id: nil)
      expect(config).not_to be_valid
      expect(config.errors[:scope_id]).to include("must be present for tenant scope")
    end

    it "validates uniqueness of scope_id scoped to scope_type" do
      described_class.create!(scope_type: "tenant", scope_id: "tenant_1")
      duplicate = described_class.new(scope_type: "tenant", scope_id: "tenant_1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:scope_id]).to include("has already been taken")
    end
  end

  describe "encryption" do
    it "encrypts API keys" do
      config = described_class.create!(
        scope_type: "global",
        openai_api_key: "sk-test-key-12345"
      )

      # Reload to ensure encryption worked
      config.reload
      expect(config.openai_api_key).to eq("sk-test-key-12345")

      # Verify the raw database value is encrypted (not plaintext)
      # Rails encryption stores the value as an encrypted string in the same column
      raw_value = described_class.connection.select_value(
        "SELECT openai_api_key FROM ruby_llm_agents_api_configurations WHERE id = #{config.id}"
      )
      expect(raw_value).not_to eq("sk-test-key-12345")
      expect(raw_value).to be_present # Should have encrypted content
    end
  end

  describe "scopes" do
    before do
      described_class.create!(scope_type: "global")
      described_class.create!(scope_type: "tenant", scope_id: "tenant_1")
      described_class.create!(scope_type: "tenant", scope_id: "tenant_2")
    end

    describe ".global_config" do
      it "returns only global configuration" do
        result = described_class.global_config
        expect(result.count).to eq(1)
        expect(result.first.scope_type).to eq("global")
      end
    end

    describe ".tenant_configs" do
      it "returns only tenant configurations" do
        result = described_class.tenant_configs
        expect(result.count).to eq(2)
        expect(result.pluck(:scope_type).uniq).to eq(["tenant"])
      end
    end

    describe ".for_scope" do
      it "returns configuration for specific scope" do
        result = described_class.for_scope("tenant", "tenant_1")
        expect(result.count).to eq(1)
        expect(result.first.scope_id).to eq("tenant_1")
      end
    end
  end

  describe ".global" do
    it "returns existing global configuration" do
      created = described_class.create!(scope_type: "global")
      found = described_class.global
      expect(found).to eq(created)
    end

    it "creates global configuration if not exists" do
      expect { described_class.global }.to change { described_class.count }.by(1)
      expect(described_class.global.scope_type).to eq("global")
    end
  end

  describe ".for_tenant" do
    it "returns tenant configuration" do
      created = described_class.create!(scope_type: "tenant", scope_id: "my_tenant")
      found = described_class.for_tenant("my_tenant")
      expect(found).to eq(created)
    end

    it "returns nil for non-existent tenant" do
      expect(described_class.for_tenant("unknown")).to be_nil
    end

    it "returns nil for blank tenant_id" do
      expect(described_class.for_tenant("")).to be_nil
      expect(described_class.for_tenant(nil)).to be_nil
    end
  end

  describe ".for_tenant!" do
    it "returns existing tenant configuration" do
      created = described_class.create!(scope_type: "tenant", scope_id: "my_tenant")
      found = described_class.for_tenant!("my_tenant")
      expect(found).to eq(created)
    end

    it "creates tenant configuration if not exists" do
      expect { described_class.for_tenant!("new_tenant") }.to change { described_class.count }.by(1)
      config = described_class.for_tenant!("new_tenant")
      expect(config.scope_type).to eq("tenant")
      expect(config.scope_id).to eq("new_tenant")
    end

    it "raises error for blank tenant_id" do
      expect { described_class.for_tenant!("") }.to raise_error(ArgumentError)
      expect { described_class.for_tenant!(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".resolve" do
    it "returns a ResolvedConfig object" do
      result = described_class.resolve
      expect(result).to be_a(RubyLLM::Agents::ResolvedConfig)
    end

    it "includes tenant config when tenant_id provided" do
      described_class.create!(scope_type: "tenant", scope_id: "test_tenant", openai_api_key: "tenant-key")
      result = described_class.resolve(tenant_id: "test_tenant")
      expect(result.tenant_config).to be_present
    end

    it "includes global config" do
      described_class.create!(scope_type: "global", openai_api_key: "global-key")
      result = described_class.resolve
      expect(result.global_config).to be_present
    end
  end

  describe "#has_value?" do
    it "returns true when attribute has value" do
      config = described_class.new(openai_api_key: "sk-test")
      expect(config.has_value?(:openai_api_key)).to be true
    end

    it "returns false when attribute is nil" do
      config = described_class.new(openai_api_key: nil)
      expect(config.has_value?(:openai_api_key)).to be false
    end

    it "returns false when attribute is blank" do
      config = described_class.new(openai_api_key: "")
      expect(config.has_value?(:openai_api_key)).to be false
    end

    it "returns false for non-existent attribute" do
      config = described_class.new
      expect(config.has_value?(:nonexistent_attr)).to be false
    end
  end

  describe "#masked_key" do
    it "masks API key for display" do
      config = described_class.new(openai_api_key: "sk-abcdefghijklmnop")
      expect(config.masked_key(:openai_api_key)).to eq("sk****mnop")
    end

    it "returns nil for blank key" do
      config = described_class.new(openai_api_key: nil)
      expect(config.masked_key(:openai_api_key)).to be_nil
    end

    it "returns masked value for short keys" do
      config = described_class.new(openai_api_key: "short")
      expect(config.masked_key(:openai_api_key)).to eq("****")
    end
  end

  describe "#source_label" do
    it "returns 'Global' for global scope" do
      config = described_class.new(scope_type: "global")
      expect(config.source_label).to eq("Global")
    end

    it "returns 'Tenant: ID' for tenant scope" do
      config = described_class.new(scope_type: "tenant", scope_id: "acme")
      expect(config.source_label).to eq("Tenant: acme")
    end
  end

  describe "#to_ruby_llm_config" do
    it "returns hash with present values only" do
      config = described_class.new(
        openai_api_key: "sk-test",
        anthropic_api_key: nil,
        default_model: "gpt-4"
      )

      result = config.to_ruby_llm_config

      expect(result[:openai_api_key]).to eq("sk-test")
      expect(result[:default_model]).to eq("gpt-4")
      expect(result).not_to have_key(:anthropic_api_key)
    end
  end

  describe "#provider_statuses" do
    it "returns array of provider status hashes" do
      config = described_class.new(
        openai_api_key: "sk-test",
        anthropic_api_key: nil
      )

      statuses = config.provider_statuses

      openai_status = statuses.find { |s| s[:key] == :openai }
      expect(openai_status[:configured]).to be true
      expect(openai_status[:masked_key]).to be_present

      anthropic_status = statuses.find { |s| s[:key] == :anthropic }
      expect(anthropic_status[:configured]).to be false
      expect(anthropic_status[:masked_key]).to be_nil
    end
  end

  describe "PROVIDERS constant" do
    it "defines all expected providers" do
      expected_providers = %i[openai anthropic gemini deepseek mistral perplexity openrouter gpustack xai ollama bedrock vertexai]
      expect(described_class::PROVIDERS.keys).to match_array(expected_providers)
    end

    it "includes required attributes for each provider" do
      described_class::PROVIDERS.each do |key, info|
        expect(info).to have_key(:name)
        expect(info).to have_key(:key_attr)
        expect(info).to have_key(:capabilities)
      end
    end
  end
end
