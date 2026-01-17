# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ResolvedConfig do
  # Skip all tests if the table doesn't exist (migration not run)
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:ruby_llm_agents_api_configurations)
      skip "ApiConfiguration table not available - run migration first"
    end
  end

  let(:tenant_config) { nil }
  let(:global_config) { nil }
  let(:ruby_llm_config) { nil }

  subject(:resolved) do
    described_class.new(
      tenant_config: tenant_config,
      global_config: global_config,
      ruby_llm_config: ruby_llm_config
    )
  end

  before do
    RubyLLM::Agents::ApiConfiguration.delete_all
  end

  describe "#initialize" do
    it "stores the configuration sources" do
      expect(resolved.tenant_config).to eq(tenant_config)
      expect(resolved.global_config).to eq(global_config)
      expect(resolved.ruby_llm_config).to eq(ruby_llm_config)
    end
  end

  describe "#resolve" do
    context "with tenant config only" do
      let(:tenant_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "tenant",
          scope_id: "test",
          openai_api_key: "tenant-key"
        )
      end

      it "returns tenant value" do
        expect(resolved.resolve(:openai_api_key)).to eq("tenant-key")
      end
    end

    context "with global config only" do
      let(:global_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "global",
          openai_api_key: "global-key"
        )
      end

      it "returns global value" do
        expect(resolved.resolve(:openai_api_key)).to eq("global-key")
      end
    end

    context "with both tenant and global config" do
      let(:tenant_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "tenant",
          scope_id: "test",
          openai_api_key: "tenant-key",
          inherit_global_defaults: true
        )
      end

      let(:global_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "global",
          openai_api_key: "global-key",
          anthropic_api_key: "global-anthropic"
        )
      end

      it "prefers tenant value over global" do
        expect(resolved.resolve(:openai_api_key)).to eq("tenant-key")
      end

      it "falls back to global for missing tenant value" do
        expect(resolved.resolve(:anthropic_api_key)).to eq("global-anthropic")
      end
    end

    context "with inherit_global_defaults false" do
      let(:tenant_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "tenant",
          scope_id: "test",
          openai_api_key: "tenant-key",
          inherit_global_defaults: false
        )
      end

      let(:global_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "global",
          anthropic_api_key: "global-anthropic"
        )
      end

      it "does not fall back to global" do
        expect(resolved.resolve(:anthropic_api_key)).to be_nil
      end
    end

    it "caches resolved values" do
      allow(resolved).to receive(:resolve_attribute).and_call_original
      resolved.resolve(:openai_api_key)
      resolved.resolve(:openai_api_key)
      expect(resolved).to have_received(:resolve_attribute).once
    end
  end

  describe "#source_for" do
    context "with tenant value" do
      let(:tenant_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "tenant",
          scope_id: "acme",
          openai_api_key: "tenant-key"
        )
      end

      it "returns tenant source" do
        expect(resolved.source_for(:openai_api_key)).to eq("tenant:acme")
      end
    end

    context "with global value" do
      let(:global_config) do
        RubyLLM::Agents::ApiConfiguration.create!(
          scope_type: "global",
          openai_api_key: "global-key"
        )
      end

      it "returns global_db source" do
        expect(resolved.source_for(:openai_api_key)).to eq("global_db")
      end
    end

    context "with no value" do
      it "returns not_set" do
        expect(resolved.source_for(:openai_api_key)).to eq("not_set")
      end
    end
  end

  describe "#to_hash" do
    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        openai_api_key: "test-key",
        default_model: "gpt-4"
      )
    end

    it "returns hash of all resolved values" do
      hash = resolved.to_hash
      expect(hash[:openai_api_key]).to eq("test-key")
      expect(hash[:default_model]).to eq("gpt-4")
    end

    it "excludes nil values" do
      hash = resolved.to_hash
      expect(hash).not_to have_key(:anthropic_api_key)
    end
  end

  describe "#to_ruby_llm_options" do
    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        openai_api_key: "test-key",
        default_model: "gpt-4"
      )
    end

    it "returns hash for RubyLLM configuration" do
      options = resolved.to_ruby_llm_options
      expect(options).to be_a(Hash)
      expect(options[:openai_api_key]).to eq("test-key")
    end
  end

  describe "#apply_to_ruby_llm!" do
    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        openai_api_key: "test-key"
      )
    end

    it "calls RubyLLM.configure" do
      config_double = double("config")
      allow(config_double).to receive(:respond_to?).and_return(true)
      allow(config_double).to receive(:openai_api_key=)
      expect(RubyLLM).to receive(:configure).and_yield(config_double)
      resolved.apply_to_ruby_llm!
    end

    it "does nothing when options are empty" do
      empty_resolved = described_class.new(
        tenant_config: nil,
        global_config: nil,
        ruby_llm_config: nil
      )
      expect(RubyLLM).not_to receive(:configure)
      empty_resolved.apply_to_ruby_llm!
    end
  end

  describe "dynamic attribute accessors" do
    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        openai_api_key: "test-key",
        anthropic_api_key: "anthropic-key"
      )
    end

    it "responds to API key attributes" do
      expect(resolved).to respond_to(:openai_api_key)
      expect(resolved).to respond_to(:anthropic_api_key)
    end

    it "returns resolved values via accessor methods" do
      expect(resolved.openai_api_key).to eq("test-key")
      expect(resolved.anthropic_api_key).to eq("anthropic-key")
    end
  end

  describe "#provider_statuses_with_source" do
    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        openai_api_key: "test-key"
      )
    end

    it "returns array of provider status with source info" do
      statuses = resolved.provider_statuses_with_source

      openai_status = statuses.find { |s| s[:key] == :openai }
      expect(openai_status[:configured]).to be true
      expect(openai_status[:source]).to eq("global_db")
      expect(openai_status[:masked_key]).to be_present
    end
  end

  describe "#has_db_config?" do
    context "with tenant config" do
      let(:tenant_config) do
        RubyLLM::Agents::ApiConfiguration.new(scope_type: "tenant", scope_id: "test")
      end

      it "returns true" do
        expect(resolved.has_db_config?).to be true
      end
    end

    context "with global config" do
      let(:global_config) do
        RubyLLM::Agents::ApiConfiguration.new(scope_type: "global")
      end

      it "returns true" do
        expect(resolved.has_db_config?).to be true
      end
    end

    context "with no config" do
      it "returns false" do
        expect(resolved.has_db_config?).to be false
      end
    end
  end

  describe "#source_summary" do
    let(:tenant_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "tenant",
        scope_id: "test",
        openai_api_key: "tenant-key",
        inherit_global_defaults: true
      )
    end

    let(:global_config) do
      RubyLLM::Agents::ApiConfiguration.create!(
        scope_type: "global",
        anthropic_api_key: "global-key"
      )
    end

    it "returns summary counts per source" do
      summary = resolved.source_summary
      expect(summary["tenant:test"]).to eq(1)
      expect(summary["global_db"]).to eq(1)
    end
  end
end
