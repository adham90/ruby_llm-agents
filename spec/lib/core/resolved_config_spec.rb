# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ResolvedConfig do
  # Mock ApiConfiguration constants
  before do
    stub_const("RubyLLM::Agents::ApiConfiguration::API_KEY_ATTRIBUTES", %i[
      openai_api_key anthropic_api_key gemini_api_key
    ])
    stub_const("RubyLLM::Agents::ApiConfiguration::NON_KEY_ATTRIBUTES", %i[
      default_model request_timeout
    ])
    stub_const("RubyLLM::Agents::ApiConfiguration::ENDPOINT_ATTRIBUTES", %i[
      openai_api_base
    ])
    stub_const("RubyLLM::Agents::ApiConfiguration::MODEL_ATTRIBUTES", %i[
      default_model default_embedding_model
    ])
    stub_const("RubyLLM::Agents::ApiConfiguration::CONNECTION_ATTRIBUTES", %i[
      request_timeout max_retries
    ])
    stub_const("RubyLLM::Agents::ApiConfiguration::PROVIDERS", {
      openai: { key_attr: :openai_api_key, name: "OpenAI", capabilities: [:chat] },
      anthropic: { key_attr: :anthropic_api_key, name: "Anthropic", capabilities: [:chat] }
    })
  end

  # Mock config objects
  let(:mock_tenant_config) do
    instance_double(RubyLLM::Agents::ApiConfiguration,
      scope_id: "tenant-123",
      has_value?: false,
      inherit_global_defaults: true
    )
  end

  let(:mock_global_config) do
    instance_double(RubyLLM::Agents::ApiConfiguration,
      has_value?: false
    )
  end

  let(:mock_ruby_llm_config) do
    double("RubyLLMConfig",
      openai_api_key: "sk-test-key",
      anthropic_api_key: nil,
      gemini_api_key: nil,
      default_model: "gpt-4o",
      request_timeout: 30
    )
  end

  subject(:resolved_config) do
    described_class.new(
      tenant_config: mock_tenant_config,
      global_config: mock_global_config,
      ruby_llm_config: mock_ruby_llm_config
    )
  end

  describe "#initialize" do
    it "accepts tenant, global, and ruby_llm configs" do
      expect(resolved_config.tenant_config).to eq(mock_tenant_config)
      expect(resolved_config.global_config).to eq(mock_global_config)
      expect(resolved_config.ruby_llm_config).to eq(mock_ruby_llm_config)
    end

    it "initializes with nil configs" do
      config = described_class.new(
        tenant_config: nil,
        global_config: nil,
        ruby_llm_config: nil
      )
      expect(config.tenant_config).to be_nil
    end
  end

  describe "#resolve" do
    context "when tenant has the value" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).with(:openai_api_key).and_return(true)
        allow(mock_tenant_config).to receive(:openai_api_key).and_return("tenant-key")
      end

      it "returns the tenant value" do
        expect(resolved_config.resolve(:openai_api_key)).to eq("tenant-key")
      end
    end

    context "when global has the value" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).with(:openai_api_key).and_return(false)
        allow(mock_global_config).to receive(:has_value?).with(:openai_api_key).and_return(true)
        allow(mock_global_config).to receive(:openai_api_key).and_return("global-key")
      end

      it "returns the global value" do
        expect(resolved_config.resolve(:openai_api_key)).to eq("global-key")
      end
    end

    context "when falling back to ruby_llm config" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).and_return(false)
        allow(mock_global_config).to receive(:has_value?).and_return(false)
      end

      it "returns the ruby_llm value" do
        expect(resolved_config.resolve(:openai_api_key)).to eq("sk-test-key")
      end
    end

    it "caches resolved values" do
      allow(mock_tenant_config).to receive(:has_value?).and_return(false)
      allow(mock_global_config).to receive(:has_value?).and_return(false)

      # First call
      resolved_config.resolve(:openai_api_key)
      # Second call should use cache
      resolved_config.resolve(:openai_api_key)

      # ruby_llm_config should only be accessed once due to caching
      expect(mock_ruby_llm_config).to have_received(:openai_api_key).once
    end
  end

  describe "#source_for" do
    context "when value comes from tenant" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).with(:openai_api_key).and_return(true)
      end

      it "returns tenant source label" do
        expect(resolved_config.source_for(:openai_api_key)).to eq("tenant:tenant-123")
      end
    end

    context "when value comes from global" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).and_return(false)
        allow(mock_global_config).to receive(:has_value?).with(:openai_api_key).and_return(true)
      end

      it "returns global_db source label" do
        expect(resolved_config.source_for(:openai_api_key)).to eq("global_db")
      end
    end

    context "when value comes from ruby_llm config" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).and_return(false)
        allow(mock_global_config).to receive(:has_value?).and_return(false)
      end

      it "returns ruby_llm_config source label" do
        expect(resolved_config.source_for(:openai_api_key)).to eq("ruby_llm_config")
      end
    end

    context "when value is not set anywhere" do
      before do
        allow(mock_tenant_config).to receive(:has_value?).and_return(false)
        allow(mock_global_config).to receive(:has_value?).and_return(false)
        allow(mock_ruby_llm_config).to receive(:anthropic_api_key).and_return(nil)
      end

      it "returns not_set source label" do
        expect(resolved_config.source_for(:anthropic_api_key)).to eq("not_set")
      end
    end
  end

  describe "#to_hash" do
    before do
      allow(mock_tenant_config).to receive(:has_value?).and_return(false)
      allow(mock_global_config).to receive(:has_value?).and_return(false)
    end

    it "returns hash of all resolved values" do
      hash = resolved_config.to_hash
      expect(hash).to be_a(Hash)
      expect(hash[:openai_api_key]).to eq("sk-test-key")
    end

    it "excludes blank values" do
      hash = resolved_config.to_hash
      expect(hash).not_to have_key(:anthropic_api_key)
    end
  end

  describe "#method_missing (dynamic accessors)" do
    before do
      allow(mock_tenant_config).to receive(:has_value?).and_return(false)
      allow(mock_global_config).to receive(:has_value?).and_return(false)
    end

    it "provides direct access to resolvable attributes" do
      expect(resolved_config.openai_api_key).to eq("sk-test-key")
    end

    it "raises NoMethodError for unknown attributes" do
      expect { resolved_config.unknown_attribute }.to raise_error(NoMethodError)
    end
  end

  describe "#respond_to_missing?" do
    it "returns true for resolvable attributes" do
      expect(resolved_config.respond_to?(:openai_api_key)).to be true
    end

    it "returns false for unknown attributes" do
      expect(resolved_config.respond_to?(:unknown_attribute)).to be false
    end
  end

  describe "#mask_string" do
    it "masks strings longer than 8 characters" do
      result = resolved_config.mask_string("sk-test-key-12345")
      expect(result).to eq("sk****2345")
    end

    it "masks short strings completely" do
      result = resolved_config.mask_string("short")
      expect(result).to eq("****")
    end

    it "returns nil for blank strings" do
      expect(resolved_config.mask_string("")).to be_nil
      expect(resolved_config.mask_string(nil)).to be_nil
    end
  end

  describe "#has_db_config?" do
    it "returns true when tenant config present" do
      expect(resolved_config.has_db_config?).to be true
    end

    it "returns true when global config present" do
      config = described_class.new(
        tenant_config: nil,
        global_config: mock_global_config,
        ruby_llm_config: mock_ruby_llm_config
      )
      expect(config.has_db_config?).to be true
    end

    it "returns false when no db config" do
      config = described_class.new(
        tenant_config: nil,
        global_config: nil,
        ruby_llm_config: mock_ruby_llm_config
      )
      expect(config.has_db_config?).to be false
    end
  end

  describe "#source_summary" do
    before do
      allow(mock_tenant_config).to receive(:has_value?).and_return(false)
      allow(mock_global_config).to receive(:has_value?).and_return(false)
    end

    it "returns counts by source" do
      summary = resolved_config.source_summary
      expect(summary).to be_a(Hash)
      expect(summary["ruby_llm_config"]).to be >= 1
    end
  end

  describe "inheritance behavior" do
    context "when tenant does not inherit global defaults" do
      before do
        allow(mock_tenant_config).to receive(:inherit_global_defaults).and_return(false)
        allow(mock_tenant_config).to receive(:has_value?).and_return(false)
        allow(mock_global_config).to receive(:has_value?).with(:openai_api_key).and_return(true)
        allow(mock_global_config).to receive(:openai_api_key).and_return("global-key")
      end

      it "skips global config" do
        # When inherit_global_defaults is false, should skip global and go to ruby_llm
        expect(resolved_config.resolve(:openai_api_key)).to eq("sk-test-key")
      end
    end
  end

  describe ".resolvable_attributes" do
    it "returns frozen array of all resolvable attributes" do
      attrs = described_class.resolvable_attributes
      expect(attrs).to be_frozen
      expect(attrs).to include(:openai_api_key)
      expect(attrs).to include(:default_model)
    end
  end
end
