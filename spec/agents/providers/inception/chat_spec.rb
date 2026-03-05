# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Providers::Inception::Chat do
  let(:config) { OpenStruct.new(inception_api_key: "test-key") }
  let(:provider) { RubyLLM::Agents::Providers::Inception.new(config) }

  describe "#format_role" do
    it "converts :user to string" do
      expect(provider.format_role(:user)).to eq("user")
    end

    it "converts :assistant to string" do
      expect(provider.format_role(:assistant)).to eq("assistant")
    end

    it "converts :system to string" do
      expect(provider.format_role(:system)).to eq("system")
    end

    it "passes through string roles unchanged" do
      expect(provider.format_role("user")).to eq("user")
    end
  end
end
