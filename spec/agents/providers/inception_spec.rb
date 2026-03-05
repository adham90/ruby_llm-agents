# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Providers::Inception do
  describe "provider registration" do
    it "is registered with RubyLLM as :inception" do
      expect(RubyLLM::Provider.resolve(:inception)).to eq(described_class)
    end

    it "appears in the providers list" do
      expect(RubyLLM::Provider.providers).to have_key(:inception)
    end
  end

  describe ".slug" do
    it "returns 'inception'" do
      expect(described_class.slug).to eq("inception")
    end
  end

  describe ".configuration_requirements" do
    it "requires inception_api_key" do
      expect(described_class.configuration_requirements).to eq(%i[inception_api_key])
    end
  end

  describe ".capabilities" do
    it "returns the Capabilities module" do
      expect(described_class.capabilities).to eq(described_class::Capabilities)
    end
  end

  describe "inheritance" do
    it "inherits from RubyLLM::Providers::OpenAI" do
      expect(described_class.superclass).to eq(RubyLLM::Providers::OpenAI)
    end
  end

  describe "instance methods" do
    let(:config) { OpenStruct.new(inception_api_key: "test-inception-key-123") }
    let(:provider) { described_class.new(config) }

    describe "#api_base" do
      it "returns the Inception API base URL" do
        expect(provider.api_base).to eq("https://api.inceptionlabs.ai/v1")
      end
    end

    describe "#headers" do
      it "includes bearer authorization header" do
        expect(provider.headers).to eq(
          "Authorization" => "Bearer test-inception-key-123"
        )
      end

      it "uses the configured API key" do
        config.inception_api_key = "different-key"
        expect(provider.headers["Authorization"]).to eq("Bearer different-key")
      end
    end

    describe "#slug" do
      it "returns 'inception'" do
        expect(provider.slug).to eq("inception")
      end
    end

    describe "#configured?" do
      it "returns true when api key is set" do
        expect(provider.configured?).to be true
      end

      it "raises ConfigurationError when api key is nil" do
        config_without_key = OpenStruct.new(inception_api_key: nil)
        expect { described_class.new(config_without_key) }
          .to raise_error(RubyLLM::ConfigurationError, /inception_api_key/)
      end
    end
  end

  describe "configuration extension" do
    it "adds inception_api_key to RubyLLM::Configuration" do
      expect(RubyLLM.config).to respond_to(:inception_api_key)
      expect(RubyLLM.config).to respond_to(:inception_api_key=)
    end

    it "allows setting inception_api_key via RubyLLM.configure" do
      original_key = RubyLLM.config.inception_api_key
      begin
        RubyLLM.configure do |config|
          config.inception_api_key = "configured-key"
        end
        expect(RubyLLM.config.inception_api_key).to eq("configured-key")
      ensure
        RubyLLM.config.inception_api_key = original_key
      end
    end
  end
end
