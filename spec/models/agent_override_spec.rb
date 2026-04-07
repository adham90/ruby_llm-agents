# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AgentOverride, type: :model do
  before do
    described_class.delete_all
  end

  describe "validations" do
    it "requires agent_type" do
      override = described_class.new(settings: {"model" => "gpt-4o"})
      expect(override).not_to be_valid
      expect(override.errors[:agent_type]).to include("can't be blank")
    end

    it "enforces unique agent_type" do
      described_class.create!(agent_type: "TestAgent", settings: {"model" => "gpt-4o"})

      duplicate = described_class.new(agent_type: "TestAgent", settings: {"model" => "gpt-4o-mini"})
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:agent_type]).to include("has already been taken")
    end
  end

  describe "settings storage" do
    it "stores and retrieves a hash of settings" do
      override = described_class.create!(
        agent_type: "TestAgent",
        settings: {"model" => "gpt-4o-mini", "temperature" => 0.5}
      )
      override.reload

      expect(override.settings).to eq({"model" => "gpt-4o-mini", "temperature" => 0.5})
    end

    it "defaults to empty hash" do
      override = described_class.create!(agent_type: "EmptyAgent")
      expect(override.settings).to eq({})
    end
  end

  describe "#[]" do
    it "returns the value for a field" do
      override = described_class.create!(
        agent_type: "TestAgent",
        settings: {"model" => "gpt-4o-mini"}
      )

      expect(override[:model]).to eq("gpt-4o-mini")
      expect(override["model"]).to eq("gpt-4o-mini")
    end

    it "returns nil for missing fields" do
      override = described_class.create!(
        agent_type: "TestAgent",
        settings: {"model" => "gpt-4o-mini"}
      )

      expect(override[:temperature]).to be_nil
    end
  end

  describe "cache busting callbacks" do
    it "calls clear_override_cache! on the agent class after save" do
      # Create a mock agent class
      mock_class = Class.new do
        def self.name = "CacheBustTestAgent"

        def self.clear_override_cache!
          @cache_busted = true
        end

        def self.cache_busted?
          @cache_busted == true
        end

        def self.respond_to?(method, *)
          method == :clear_override_cache! || super
        end
      end

      stub_const("CacheBustTestAgent", mock_class)

      described_class.create!(
        agent_type: "CacheBustTestAgent",
        settings: {"model" => "gpt-4o"}
      )

      expect(CacheBustTestAgent.cache_busted?).to be true
    end

    it "calls clear_override_cache! on the agent class after destroy" do
      mock_class = Class.new do
        def self.name = "DestroyBustTestAgent"

        def self.clear_override_cache!
          @cache_busted = true
        end

        def self.cache_busted?
          @cache_busted == true
        end

        def self.respond_to?(method, *)
          method == :clear_override_cache! || super
        end
      end

      stub_const("DestroyBustTestAgent", mock_class)

      override = described_class.create!(
        agent_type: "DestroyBustTestAgent",
        settings: {"model" => "gpt-4o"}
      )

      # Reset the flag
      DestroyBustTestAgent.instance_variable_set(:@cache_busted, false)

      override.destroy
      expect(DestroyBustTestAgent.cache_busted?).to be true
    end

    it "does not error when agent class is not found" do
      expect {
        described_class.create!(
          agent_type: "NonexistentAgent",
          settings: {"model" => "gpt-4o"}
        )
      }.not_to raise_error
    end
  end

  describe "updated_by" do
    it "stores who last changed the override" do
      override = described_class.create!(
        agent_type: "TestAgent",
        settings: {"model" => "gpt-4o"},
        updated_by: "admin@example.com"
      )
      override.reload

      expect(override.updated_by).to eq("admin@example.com")
    end
  end
end
