# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Moderator do
  let(:moderator_class) do
    Class.new(described_class) do
      def self.name
        "TestModerator"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_moderation_model = "omni-moderation-latest"
    end
  end

  describe ".agent_type" do
    it "returns :moderation" do
      expect(moderator_class.agent_type).to eq(:moderation)
    end
  end

  describe ".model" do
    it "sets and gets the model" do
      moderator_class.model "text-moderation-stable"
      expect(moderator_class.model).to eq("text-moderation-stable")
    end

    it "defaults to config default_moderation_model" do
      expect(moderator_class.model).to eq("omni-moderation-latest")
    end

    it "falls back to 'omni-moderation-latest' when not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(moderator_class.model).to eq("omni-moderation-latest")
    end
  end

  describe ".threshold" do
    it "sets and gets the threshold" do
      moderator_class.threshold 0.7
      expect(moderator_class.threshold).to eq(0.7)
    end

    it "returns nil by default" do
      expect(moderator_class.threshold).to be_nil
    end

    it "accepts boundary values" do
      moderator_class.threshold 0.0
      expect(moderator_class.threshold).to eq(0.0)

      moderator_class.threshold 1.0
      expect(moderator_class.threshold).to eq(1.0)
    end
  end

  describe ".categories" do
    it "sets and gets categories" do
      moderator_class.categories :hate, :violence, :harassment
      expect(moderator_class.categories).to eq([:hate, :violence, :harassment])
    end

    it "accepts array syntax" do
      moderator_class.categories [:hate, :violence]
      expect(moderator_class.categories).to eq([:hate, :violence])
    end

    it "converts strings to symbols" do
      moderator_class.categories "hate", "violence"
      expect(moderator_class.categories).to eq([:hate, :violence])
    end

    it "returns nil by default" do
      expect(moderator_class.categories).to be_nil
    end
  end

  describe "#initialize" do
    it "requires text parameter" do
      expect {
        moderator_class.new(text: "Hello")
      }.not_to raise_error
    end

    it "stores the text" do
      moderator = moderator_class.new(text: "Content to moderate")
      expect(moderator.text).to eq("Content to moderate")
    end

    it "accepts runtime threshold override" do
      moderator_class.threshold 0.5
      moderator = moderator_class.new(text: "test", threshold: 0.9)

      expect(moderator.send(:resolved_threshold)).to eq(0.9)
    end

    it "accepts runtime categories override" do
      moderator_class.categories :hate
      moderator = moderator_class.new(text: "test", categories: [:violence, :harassment])

      expect(moderator.send(:resolved_categories)).to eq([:violence, :harassment])
    end
  end

  describe "#user_prompt" do
    it "returns the text being moderated" do
      moderator = moderator_class.new(text: "Check this content")
      expect(moderator.user_prompt).to eq("Check this content")
    end
  end

  describe "inheritance" do
    let(:parent_moderator) do
      Class.new(described_class) do
        def self.name
          "ParentModerator"
        end

        model "text-moderation-stable"
        threshold 0.8
        categories :hate, :violence
      end
    end

    let(:child_moderator) do
      Class.new(parent_moderator) do
        def self.name
          "ChildModerator"
        end
      end
    end

    it "inherits settings from parent" do
      expect(child_moderator.model).to eq("text-moderation-stable")
      expect(child_moderator.threshold).to eq(0.8)
      expect(child_moderator.categories).to eq([:hate, :violence])
    end

    it "allows child to override parent settings" do
      child_moderator.threshold 0.5
      expect(child_moderator.threshold).to eq(0.5)
      expect(parent_moderator.threshold).to eq(0.8)
    end

    it "allows child to override categories" do
      child_moderator.categories :harassment
      expect(child_moderator.categories).to eq([:harassment])
      expect(parent_moderator.categories).to eq([:hate, :violence])
    end
  end

  describe "#agent_cache_key" do
    it "generates unique cache key for different texts" do
      moderator1 = moderator_class.new(text: "Text one")
      moderator2 = moderator_class.new(text: "Text two")

      expect(moderator1.agent_cache_key).not_to eq(moderator2.agent_cache_key)
    end

    it "generates same cache key for same text" do
      moderator1 = moderator_class.new(text: "Same text")
      moderator2 = moderator_class.new(text: "Same text")

      expect(moderator1.agent_cache_key).to eq(moderator2.agent_cache_key)
    end

    it "includes model in cache key" do
      moderator_class.model "omni-moderation-latest"
      moderator = moderator_class.new(text: "test")

      expect(moderator.agent_cache_key).to include("omni-moderation-latest")
    end

    it "includes threshold in cache key when set" do
      moderator_class.threshold 0.75
      moderator = moderator_class.new(text: "test")

      expect(moderator.agent_cache_key).to include("0.75")
    end

    it "includes categories in cache key when set" do
      moderator_class.categories :hate, :violence
      moderator = moderator_class.new(text: "test")

      # Categories are sorted and joined
      expect(moderator.agent_cache_key).to include("hate,violence")
    end
  end

  describe "combined configuration" do
    it "allows full configuration" do
      moderator_class.model "text-moderation-latest"
      moderator_class.threshold 0.6
      moderator_class.categories :hate, :violence, :harassment, :sexual

      expect(moderator_class.model).to eq("text-moderation-latest")
      expect(moderator_class.threshold).to eq(0.6)
      expect(moderator_class.categories).to eq([:hate, :violence, :harassment, :sexual])
    end
  end

  describe "runtime overrides vs class defaults" do
    before do
      moderator_class.model "default-model"
      moderator_class.threshold 0.5
      moderator_class.categories :hate
    end

    it "uses class defaults when no runtime options" do
      moderator = moderator_class.new(text: "test")

      expect(moderator.send(:resolved_model)).to eq("default-model")
      expect(moderator.send(:resolved_threshold)).to eq(0.5)
      expect(moderator.send(:resolved_categories)).to eq([:hate])
    end

    it "runtime threshold overrides class threshold" do
      moderator = moderator_class.new(text: "test", threshold: 0.9)

      expect(moderator.send(:resolved_threshold)).to eq(0.9)
      expect(moderator.send(:resolved_categories)).to eq([:hate]) # unchanged
    end

    it "runtime categories override class categories" do
      moderator = moderator_class.new(text: "test", categories: [:violence, :harassment])

      expect(moderator.send(:resolved_threshold)).to eq(0.5) # unchanged
      expect(moderator.send(:resolved_categories)).to eq([:violence, :harassment])
    end

    it "allows overriding both at runtime" do
      moderator = moderator_class.new(
        text: "test",
        threshold: 0.8,
        categories: [:sexual]
      )

      expect(moderator.send(:resolved_threshold)).to eq(0.8)
      expect(moderator.send(:resolved_categories)).to eq([:sexual])
    end
  end
end
