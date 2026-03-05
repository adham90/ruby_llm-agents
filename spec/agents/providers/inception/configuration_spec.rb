# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inception API key configuration" do
  after do
    # Clean up: reset the key after each test
    RubyLLM.config.inception_api_key = nil
  end

  describe "via RubyLLM::Agents.configure" do
    it "accepts inception_api_key" do
      RubyLLM::Agents.configure do |config|
        config.inception_api_key = "test-agents-key"
      end

      expect(RubyLLM::Agents.configuration.inception_api_key).to eq("test-agents-key")
    end

    it "forwards inception_api_key to RubyLLM.config" do
      RubyLLM::Agents.configure do |config|
        config.inception_api_key = "forwarded-key"
      end

      expect(RubyLLM.config.inception_api_key).to eq("forwarded-key")
    end

    it "reads inception_api_key from RubyLLM.config" do
      RubyLLM.configure do |config|
        config.inception_api_key = "upstream-key"
      end

      expect(RubyLLM::Agents.configuration.inception_api_key).to eq("upstream-key")
    end
  end

  describe "via RubyLLM.configure" do
    it "accepts inception_api_key directly" do
      RubyLLM.configure do |config|
        config.inception_api_key = "direct-key"
      end

      expect(RubyLLM.config.inception_api_key).to eq("direct-key")
    end
  end

  describe "FORWARDED_RUBY_LLM_ATTRIBUTES" do
    it "includes inception_api_key" do
      expect(RubyLLM::Agents::Configuration::FORWARDED_RUBY_LLM_ATTRIBUTES).to include(:inception_api_key)
    end
  end

  describe "sensitive attributes" do
    it "marks inception_api_key as sensitive" do
      expect(RubyLLM::Agents::Configuration::SENSITIVE_ATTRIBUTES).to include(:inception_api_key)
    end

    it "redacts api_keys in to_h output by default" do
      RubyLLM::Agents.configure do |config|
        config.inception_api_key = "secret-key-123"
      end

      hash = RubyLLM::Agents.configuration.to_h(include_sensitive: false)
      expect(hash[:api_keys]).to eq("(hidden, pass include_sensitive: true)")
    end

    it "shows inception_api_key when include_sensitive is true" do
      RubyLLM::Agents.configure do |config|
        config.inception_api_key = "visible-key"
      end

      hash = RubyLLM::Agents.configuration.to_h(include_sensitive: true)
      expect(hash[:api_keys][:inception_api_key]).to eq("visible-key")
    end
  end
end
