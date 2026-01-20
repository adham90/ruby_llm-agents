# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Moderator do
  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_moderation_model).and_return("omni-moderation-latest")
    allow(config).to receive(:default_timeout).and_return(120)
    allow(config).to receive(:default_temperature).and_return(0.7)
    allow(config).to receive(:default_streaming).and_return(false)
    allow(config).to receive(:budgets_enabled?).and_return(false)
    allow(config).to receive(:track_moderation).and_return(false)
    allow(config).to receive(:track_embeddings).and_return(false)
    allow(config).to receive(:track_executions).and_return(false)
    allow(config).to receive(:track_image_generation).and_return(false)
    allow(config).to receive(:track_audio).and_return(false)
  end

  # Mock RubyLLM.moderate response
  let(:mock_result) do
    double(
      "ModerationResponse",
      flagged?: false,
      flagged_categories: [],
      category_scores: { "hate" => 0.01, "violence" => 0.02 },
      id: "mod-123",
      model: "omni-moderation-latest"
    )
  end

  let(:flagged_result) do
    double(
      "ModerationResponse",
      flagged?: true,
      flagged_categories: ["hate", "violence"],
      category_scores: { "hate" => 0.85, "violence" => 0.72 },
      id: "mod-456",
      model: "omni-moderation-latest"
    )
  end

  describe ".agent_type" do
    it "returns :moderation" do
      expect(described_class.agent_type).to eq(:moderation)
    end
  end

  describe "DSL" do
    let(:base_moderator) do
      Class.new(described_class) do
        def self.name
          "TestModerator"
        end
      end
    end

    describe ".model" do
      it "sets and returns the model" do
        base_moderator.model "text-moderation-latest"
        expect(base_moderator.model).to eq("text-moderation-latest")
      end

      it "returns default when not set" do
        expect(base_moderator.model).to eq("omni-moderation-latest")
      end

      it "inherits from parent class" do
        base_moderator.model "custom-moderation"
        child = Class.new(base_moderator) do
          def self.name
            "ChildModerator"
          end
        end
        expect(child.model).to eq("custom-moderation")
      end
    end

    describe ".threshold" do
      it "sets and returns threshold" do
        base_moderator.threshold 0.8
        expect(base_moderator.threshold).to eq(0.8)
      end

      it "returns nil when not set" do
        expect(base_moderator.threshold).to be_nil
      end

      it "inherits from parent class" do
        base_moderator.threshold 0.7
        child = Class.new(base_moderator) do
          def self.name
            "ChildModerator"
          end
        end
        expect(child.threshold).to eq(0.7)
      end
    end

    describe ".categories" do
      it "sets and returns categories" do
        base_moderator.categories :hate, :violence
        expect(base_moderator.categories).to eq([:hate, :violence])
      end

      it "returns nil when not set" do
        expect(base_moderator.categories).to be_nil
      end

      it "accepts array syntax" do
        base_moderator.categories [:hate, :harassment]
        expect(base_moderator.categories).to eq([:hate, :harassment])
      end

      it "inherits from parent class" do
        base_moderator.categories :hate
        child = Class.new(base_moderator) do
          def self.name
            "ChildModerator"
          end
        end
        expect(child.categories).to eq([:hate])
      end
    end

    describe ".version" do
      it "sets and returns version" do
        base_moderator.version "2.0"
        expect(base_moderator.version).to eq("2.0")
      end

      it "returns default when not set" do
        expect(base_moderator.version).to eq("1.0")
      end
    end
  end

  describe "#call" do
    let(:test_moderator) do
      Class.new(described_class) do
        def self.name
          "TestModerator"
        end

        model "omni-moderation-latest"
      end
    end

    context "with safe content" do
      it "returns a ModerationResult" do
        allow(RubyLLM).to receive(:moderate).and_return(mock_result)

        result = test_moderator.call(text: "Hello world")

        expect(result).to be_a(RubyLLM::Agents::ModerationResult)
      end

      it "passes text to RubyLLM.moderate" do
        expect(RubyLLM).to receive(:moderate)
          .with("Hello world", hash_including(model: "omni-moderation-latest"))
          .and_return(mock_result)

        test_moderator.call(text: "Hello world")
      end

      it "returns not flagged for safe content" do
        allow(RubyLLM).to receive(:moderate).and_return(mock_result)

        result = test_moderator.call(text: "Hello world")

        expect(result.flagged?).to be false
        expect(result.passed?).to be true
      end
    end

    context "with flagged content" do
      it "returns flagged for dangerous content" do
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = test_moderator.call(text: "hate speech content")

        expect(result.flagged?).to be true
        expect(result.passed?).to be false
      end

      it "returns flagged categories" do
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = test_moderator.call(text: "hate speech content")

        expect(result.flagged_categories).to include("hate", "violence")
      end
    end

    context "with threshold" do
      let(:moderator_with_threshold) do
        Class.new(described_class) do
          def self.name
            "ThresholdModerator"
          end

          model "omni-moderation-latest"
          threshold 0.9
        end
      end

      it "uses class-level threshold" do
        # Score 0.85 is below threshold 0.9, so should not be flagged
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = moderator_with_threshold.call(text: "content")

        # flagged_result has max_score 0.85, threshold is 0.9
        # So should not be flagged due to threshold
        expect(result.flagged?).to be false
      end

      it "allows runtime threshold override" do
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = moderator_with_threshold.call(text: "content", threshold: 0.5)

        # max_score 0.85 is above threshold 0.5
        expect(result.flagged?).to be true
      end
    end

    context "with categories filter" do
      let(:moderator_with_categories) do
        Class.new(described_class) do
          def self.name
            "CategoryModerator"
          end

          model "omni-moderation-latest"
          categories :harassment
        end
      end

      it "filters by class-level categories" do
        # flagged_result has hate and violence, not harassment
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = moderator_with_categories.call(text: "content")

        # Should not be flagged because categories don't match
        expect(result.flagged?).to be false
      end

      it "allows runtime categories override" do
        allow(RubyLLM).to receive(:moderate).and_return(flagged_result)

        result = moderator_with_categories.call(text: "content", categories: [:hate])

        # Should be flagged because :hate matches
        expect(result.flagged?).to be true
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:moderate)
          .with(anything, hash_including(model: "text-moderation-stable"))
          .and_return(mock_result)

        test_moderator.call(text: "Hello", model: "text-moderation-stable")
      end
    end
  end

  describe "#agent_cache_key" do
    let(:test_moderator) do
      Class.new(described_class) do
        def self.name
          "CacheKeyModerator"
        end

        model "omni-moderation-latest"
        version "1.0"
      end
    end

    it "generates unique cache key" do
      moderator = test_moderator.new(text: "Hello world")
      key = moderator.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/moderation/CacheKeyModerator/1.0/")
    end

    it "generates different keys for different texts" do
      mod1 = test_moderator.new(text: "Hello")
      mod2 = test_moderator.new(text: "World")

      expect(mod1.agent_cache_key).not_to eq(mod2.agent_cache_key)
    end

    it "generates same key for same text" do
      mod1 = test_moderator.new(text: "Hello")
      mod2 = test_moderator.new(text: "Hello")

      expect(mod1.agent_cache_key).to eq(mod2.agent_cache_key)
    end

    it "includes threshold in cache key when set" do
      moderator_class = Class.new(described_class) do
        def self.name
          "ThresholdCacheModerator"
        end

        threshold 0.8
      end

      mod = moderator_class.new(text: "Hello")
      expect(mod.agent_cache_key).to include("0.8")
    end

    it "includes categories in cache key when set" do
      moderator_class = Class.new(described_class) do
        def self.name
          "CategoryCacheModerator"
        end

        categories :hate, :violence
      end

      mod = moderator_class.new(text: "Hello")
      expect(mod.agent_cache_key).to include("hate,violence")
    end
  end
end
