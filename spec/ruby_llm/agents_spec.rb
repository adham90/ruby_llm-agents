# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents do
  it "has a version number" do
    expect(RubyLLM::Agents::VERSION).not_to be_nil
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(RubyLLM::Agents::Configuration)
    end

    it "returns the same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe ".configure" do
    it "yields configuration to block" do
      described_class.configure do |config|
        expect(config).to be_a(RubyLLM::Agents::Configuration)
      end
    end

    it "allows setting configuration options" do
      described_class.configure do |config|
        config.default_model = "gpt-4-turbo"
      end

      expect(described_class.configuration.default_model).to eq("gpt-4-turbo")
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      described_class.configure { |c| c.default_model = "custom-model" }
      described_class.reset_configuration!

      expect(described_class.configuration.default_model).to eq("gemini-2.0-flash")
    end
  end
end
