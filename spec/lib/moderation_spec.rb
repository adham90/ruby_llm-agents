# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "Moderation Support" do
  # Helper to create a fresh agent class for each test
  def create_agent_class(&block)
    Class.new(RubyLLM::Agents::Base) do
      class_eval(&block) if block
    end
  end

  # Mock moderation result
  def mock_moderation_result(flagged:, categories: [], scores: {})
    OpenStruct.new(
      flagged?: flagged,
      flagged_categories: categories,
      category_scores: scores,
      model: "omni-moderation-latest",
      id: "modr-123"
    )
  end

  describe "DSL" do
    describe ".moderation" do
      it "configures input moderation by default" do
        klass = create_agent_class { moderation :input }
        expect(klass.moderation_config[:phases]).to eq([:input])
      end

      it "configures output moderation" do
        klass = create_agent_class { moderation :output }
        expect(klass.moderation_config[:phases]).to eq([:output])
      end

      it "configures both input and output moderation" do
        klass = create_agent_class { moderation :input, :output }
        expect(klass.moderation_config[:phases]).to include(:input, :output)
      end

      it "supports :both shorthand" do
        klass = create_agent_class { moderation :both }
        expect(klass.moderation_config[:phases]).to include(:input, :output)
      end

      it "sets threshold" do
        klass = create_agent_class { moderation :input, threshold: 0.8 }
        expect(klass.moderation_config[:threshold]).to eq(0.8)
      end

      it "sets categories" do
        klass = create_agent_class { moderation :input, categories: [:hate, :violence] }
        expect(klass.moderation_config[:categories]).to eq([:hate, :violence])
      end

      it "sets on_flagged action" do
        klass = create_agent_class { moderation :input, on_flagged: :raise }
        expect(klass.moderation_config[:on_flagged]).to eq(:raise)
      end

      it "sets custom handler" do
        klass = create_agent_class { moderation :input, custom_handler: :my_handler }
        expect(klass.moderation_config[:custom_handler]).to eq(:my_handler)
      end

      it "sets model" do
        klass = create_agent_class { moderation :input, model: "text-moderation-007" }
        expect(klass.moderation_config[:model]).to eq("text-moderation-007")
      end

      it "defaults on_flagged to :block" do
        klass = create_agent_class { moderation :input }
        expect(klass.moderation_config[:on_flagged]).to eq(:block)
      end

      it "returns nil when not configured" do
        klass = create_agent_class
        expect(klass.moderation_config).to be_nil
      end
    end

    describe ".moderation with block" do
      it "configures using block syntax" do
        klass = create_agent_class do
          moderation do
            input enabled: true
            output enabled: true
            threshold 0.7
            categories :hate, :violence
            on_flagged :raise
          end
        end

        config = klass.moderation_config
        expect(config[:phases]).to include(:input, :output)
        expect(config[:threshold]).to eq(0.7)
        expect(config[:categories]).to eq([:hate, :violence])
        expect(config[:on_flagged]).to eq(:raise)
      end

      it "supports phase-specific thresholds" do
        klass = create_agent_class do
          moderation do
            input enabled: true, threshold: 0.6
            output enabled: true, threshold: 0.9
          end
        end

        config = klass.moderation_config
        expect(config[:input_threshold]).to eq(0.6)
        expect(config[:output_threshold]).to eq(0.9)
      end

      it "skips disabled phases" do
        klass = create_agent_class do
          moderation do
            input enabled: true
            output enabled: false
          end
        end

        config = klass.moderation_config
        expect(config[:phases]).to eq([:input])
      end
    end

    describe ".moderation_enabled?" do
      it "returns true when moderation is configured" do
        klass = create_agent_class { moderation :input }
        expect(klass.moderation_enabled?).to be true
      end

      it "returns false when not configured" do
        klass = create_agent_class
        expect(klass.moderation_enabled?).to be false
      end
    end

    describe "inheritance" do
      it "inherits moderation config from parent" do
        parent = create_agent_class { moderation :input, threshold: 0.8 }
        child = Class.new(parent)

        expect(child.moderation_config[:phases]).to eq([:input])
        expect(child.moderation_config[:threshold]).to eq(0.8)
      end

      it "can override parent moderation config" do
        parent = create_agent_class { moderation :input, threshold: 0.8 }
        child = Class.new(parent) { moderation :output, threshold: 0.5 }

        expect(child.moderation_config[:phases]).to eq([:output])
        expect(child.moderation_config[:threshold]).to eq(0.5)
      end
    end
  end

  describe "Configuration" do
    describe "moderation defaults" do
      let(:config) { RubyLLM::Agents::Configuration.new }

      it "has default_moderation_model" do
        expect(config.default_moderation_model).to eq("omni-moderation-latest")
      end

      it "has default_moderation_threshold as nil" do
        expect(config.default_moderation_threshold).to be_nil
      end

      it "has default_moderation_action as :block" do
        expect(config.default_moderation_action).to eq(:block)
      end

      it "has track_moderation enabled" do
        expect(config.track_moderation).to be true
      end

      it "allows setting custom moderation model" do
        config.default_moderation_model = "text-moderation-007"
        expect(config.default_moderation_model).to eq("text-moderation-007")
      end

      it "allows setting custom threshold" do
        config.default_moderation_threshold = 0.75
        expect(config.default_moderation_threshold).to eq(0.75)
      end

      it "allows disabling moderation tracking" do
        config.track_moderation = false
        expect(config.track_moderation).to be false
      end
    end
  end

  describe "Result" do
    describe "moderation attributes" do
      it "initializes with status" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          status: :input_moderation_blocked
        )
        expect(result.status).to eq(:input_moderation_blocked)
      end

      it "defaults status to :success" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.status).to eq(:success)
      end

      it "initializes with moderation_flagged" do
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_flagged: true
        )
        expect(result.moderation_flagged?).to be true
      end

      it "defaults moderation_flagged to false" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.moderation_flagged?).to be false
      end

      it "initializes with moderation_result" do
        mod_result = mock_moderation_result(flagged: true, categories: [:hate])
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_result: mod_result
        )
        expect(result.moderation_result).to eq(mod_result)
      end

      it "initializes with moderation_phase" do
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_phase: :input
        )
        expect(result.moderation_phase).to eq(:input)
      end
    end

    describe "#moderation_flagged?" do
      it "returns true when moderation_flagged is true" do
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_flagged: true
        )
        expect(result.moderation_flagged?).to be true
      end

      it "returns false when moderation_flagged is false" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.moderation_flagged?).to be false
      end
    end

    describe "#moderation_passed?" do
      it "returns true when not flagged" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.moderation_passed?).to be true
      end

      it "returns false when flagged" do
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_flagged: true
        )
        expect(result.moderation_passed?).to be false
      end
    end

    describe "#moderation_categories" do
      it "returns flagged categories from moderation result" do
        mod_result = mock_moderation_result(
          flagged: true,
          categories: [:hate, :violence]
        )
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_result: mod_result
        )
        expect(result.moderation_categories).to eq([:hate, :violence])
      end

      it "returns empty array when no moderation result" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.moderation_categories).to eq([])
      end
    end

    describe "#moderation_scores" do
      it "returns category scores from moderation result" do
        mod_result = mock_moderation_result(
          flagged: true,
          scores: { hate: 0.95, violence: 0.80 }
        )
        result = RubyLLM::Agents::Result.new(
          content: nil,
          moderation_result: mod_result
        )
        expect(result.moderation_scores).to eq({ hate: 0.95, violence: 0.80 })
      end

      it "returns empty hash when no moderation result" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.moderation_scores).to eq({})
      end
    end

    describe "#to_h" do
      it "includes moderation attributes" do
        mod_result = mock_moderation_result(
          flagged: true,
          categories: [:hate],
          scores: { hate: 0.9 }
        )
        result = RubyLLM::Agents::Result.new(
          content: nil,
          status: :input_moderation_blocked,
          moderation_flagged: true,
          moderation_result: mod_result,
          moderation_phase: :input
        )

        hash = result.to_h

        expect(hash[:status]).to eq(:input_moderation_blocked)
        expect(hash[:moderation_flagged]).to be true
        expect(hash[:moderation_phase]).to eq(:input)
        expect(hash[:moderation_categories]).to eq([:hate])
        expect(hash[:moderation_scores]).to eq({ hate: 0.9 })
      end
    end
  end

  describe "ModerationResult" do
    describe "#flagged?" do
      it "returns true when raw result is flagged" do
        raw = mock_moderation_result(flagged: true, categories: [:hate])
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.flagged?).to be true
      end

      it "returns false when raw result is not flagged" do
        raw = mock_moderation_result(flagged: false)
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.flagged?).to be false
      end

      it "returns false when score is below threshold" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate],
          scores: { hate: 0.5 }
        )
        result = RubyLLM::Agents::ModerationResult.new(result: raw, threshold: 0.8)
        expect(result.flagged?).to be false
      end

      it "returns true when score meets threshold" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate],
          scores: { hate: 0.9 }
        )
        result = RubyLLM::Agents::ModerationResult.new(result: raw, threshold: 0.8)
        expect(result.flagged?).to be true
      end

      it "returns false when category does not match filter" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:sexual]
        )
        result = RubyLLM::Agents::ModerationResult.new(
          result: raw,
          categories: [:hate, :violence]
        )
        expect(result.flagged?).to be false
      end

      it "returns true when category matches filter" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate]
        )
        result = RubyLLM::Agents::ModerationResult.new(
          result: raw,
          categories: [:hate, :violence]
        )
        expect(result.flagged?).to be true
      end
    end

    describe "#passed?" do
      it "returns opposite of flagged?" do
        raw = mock_moderation_result(flagged: false)
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.passed?).to be true
      end
    end

    describe "#flagged_categories" do
      it "returns all categories when no filter" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate, :violence, :sexual]
        )
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.flagged_categories).to eq([:hate, :violence, :sexual])
      end

      it "filters categories based on configuration" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate, :violence, :sexual]
        )
        result = RubyLLM::Agents::ModerationResult.new(
          result: raw,
          categories: [:hate, :violence]
        )
        expect(result.flagged_categories).to eq([:hate, :violence])
      end
    end

    describe "#max_score" do
      it "returns highest category score" do
        raw = mock_moderation_result(
          flagged: true,
          scores: { hate: 0.5, violence: 0.9, sexual: 0.3 }
        )
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.max_score).to eq(0.9)
      end

      it "returns 0.0 when no scores" do
        raw = mock_moderation_result(flagged: false, scores: {})
        result = RubyLLM::Agents::ModerationResult.new(result: raw)
        expect(result.max_score).to eq(0.0)
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        raw = mock_moderation_result(
          flagged: true,
          categories: [:hate],
          scores: { hate: 0.9 }
        )
        result = RubyLLM::Agents::ModerationResult.new(
          result: raw,
          threshold: 0.8,
          categories: [:hate]
        )

        hash = result.to_h

        expect(hash[:flagged]).to be true
        expect(hash[:threshold]).to eq(0.8)
        expect(hash[:filter_categories]).to eq([:hate])
        expect(hash[:model]).to eq("omni-moderation-latest")
      end
    end
  end

  describe "ModerationError" do
    it "includes phase in message" do
      mod_result = mock_moderation_result(
        flagged: true,
        categories: [:hate, :violence]
      )
      error = RubyLLM::Agents::ModerationError.new(mod_result, :input)

      expect(error.message).to include("input moderation")
      expect(error.message).to include("hate")
      expect(error.message).to include("violence")
    end

    it "exposes moderation_result" do
      mod_result = mock_moderation_result(flagged: true, categories: [:hate])
      error = RubyLLM::Agents::ModerationError.new(mod_result, :input)

      expect(error.moderation_result).to eq(mod_result)
    end

    it "exposes phase" do
      mod_result = mock_moderation_result(flagged: true, categories: [:hate])
      error = RubyLLM::Agents::ModerationError.new(mod_result, :output)

      expect(error.phase).to eq(:output)
    end

    it "exposes flagged_categories" do
      mod_result = mock_moderation_result(
        flagged: true,
        categories: [:hate, :violence]
      )
      error = RubyLLM::Agents::ModerationError.new(mod_result, :input)

      expect(error.flagged_categories).to eq([:hate, :violence])
    end

    it "exposes category_scores" do
      mod_result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.95 }
      )
      error = RubyLLM::Agents::ModerationError.new(mod_result, :input)

      expect(error.category_scores).to eq({ hate: 0.95 })
    end
  end

  describe "Moderator" do
    describe "DSL" do
      it "sets model" do
        klass = Class.new(RubyLLM::Agents::Moderator) do
          model "text-moderation-007"
        end
        expect(klass.model).to eq("text-moderation-007")
      end

      it "sets threshold" do
        klass = Class.new(RubyLLM::Agents::Moderator) do
          threshold 0.8
        end
        expect(klass.threshold).to eq(0.8)
      end

      it "sets categories" do
        klass = Class.new(RubyLLM::Agents::Moderator) do
          categories :hate, :violence
        end
        expect(klass.categories).to eq([:hate, :violence])
      end

      it "defaults to configuration model" do
        expect(RubyLLM::Agents::Moderator.model).to eq("omni-moderation-latest")
      end
    end

    describe ".call" do
      let(:moderator_class) do
        Class.new(RubyLLM::Agents::Moderator) do
          threshold 0.8
          categories :hate, :violence
        end
      end

      before do
        allow(RubyLLM).to receive(:moderate).and_return(
          mock_moderation_result(
            flagged: true,
            categories: [:hate],
            scores: { hate: 0.9 }
          )
        )
      end

      it "returns ModerationResult" do
        result = moderator_class.call(text: "test content")
        expect(result).to be_a(RubyLLM::Agents::ModerationResult)
      end

      it "applies configured threshold" do
        result = moderator_class.call(text: "test content")
        expect(result.threshold).to eq(0.8)
      end

      it "applies configured categories" do
        result = moderator_class.call(text: "test content")
        expect(result.filter_categories).to eq([:hate, :violence])
      end

      it "allows runtime override of threshold" do
        result = moderator_class.call(text: "test", threshold: 0.5)
        expect(result.threshold).to eq(0.5)
      end

      it "allows runtime override of categories" do
        result = moderator_class.call(text: "test", categories: [:sexual])
        expect(result.filter_categories).to eq([:sexual])
      end
    end
  end

  describe "Execution" do
    let(:agent_class) do
      create_agent_class do
        moderation :input

        def system_prompt
          "You are a helpful assistant"
        end

        def user_prompt
          "Test prompt"
        end
      end
    end

    before do
      allow_any_instance_of(RubyLLM::Agents::Base).to receive(:build_client).and_return(double)
    end

    describe "#should_moderate?" do
      it "returns true for configured phase" do
        agent = agent_class.new
        expect(agent.send(:should_moderate?, :input)).to be true
      end

      it "returns false for unconfigured phase" do
        agent = agent_class.new
        expect(agent.send(:should_moderate?, :output)).to be false
      end

      it "returns false when runtime moderation is disabled" do
        agent = agent_class.new(moderation: false)
        expect(agent.send(:should_moderate?, :input)).to be false
      end
    end

    describe "#resolved_moderation_config" do
      it "returns class config when no runtime override" do
        agent = agent_class.new
        config = agent.send(:resolved_moderation_config)
        expect(config[:phases]).to eq([:input])
      end

      it "returns nil when moderation disabled at runtime" do
        agent = agent_class.new(moderation: false)
        config = agent.send(:resolved_moderation_config)
        expect(config).to be_nil
      end

      it "merges runtime options with class config" do
        agent = agent_class.new(moderation: { threshold: 0.9 })
        config = agent.send(:resolved_moderation_config)
        expect(config[:phases]).to eq([:input])
        expect(config[:threshold]).to eq(0.9)
      end
    end

    describe "#content_flagged?" do
      let(:agent) { agent_class.new }

      it "returns false when result is not flagged" do
        result = mock_moderation_result(flagged: false)
        config = { phases: [:input], on_flagged: :block }
        expect(agent.send(:content_flagged?, result, config, :input)).to be false
      end

      it "returns true when result is flagged" do
        result = mock_moderation_result(flagged: true, categories: [:hate])
        config = { phases: [:input], on_flagged: :block }
        expect(agent.send(:content_flagged?, result, config, :input)).to be true
      end

      it "returns false when score below threshold" do
        result = mock_moderation_result(
          flagged: true,
          categories: [:hate],
          scores: { hate: 0.5 }
        )
        config = { phases: [:input], threshold: 0.8, on_flagged: :block }
        expect(agent.send(:content_flagged?, result, config, :input)).to be false
      end

      it "returns false when category not in filter" do
        result = mock_moderation_result(flagged: true, categories: [:sexual])
        config = { phases: [:input], categories: [:hate, :violence], on_flagged: :block }
        expect(agent.send(:content_flagged?, result, config, :input)).to be false
      end
    end
  end

  describe "complete agent with moderation" do
    it "supports full configuration with moderation" do
      tool = Class.new { def self.name; "TestTool"; end }

      klass = create_agent_class do
        model "gpt-4o"
        temperature 0.8
        moderation :both, threshold: 0.7, categories: [:hate, :violence]

        cache_for 2.hours
        streaming true
        tools [tool]

        param :message, required: true

        def system_prompt
          "You are a helpful assistant"
        end

        def user_prompt
          message
        end
      end

      expect(klass.model).to eq("gpt-4o")
      expect(klass.temperature).to eq(0.8)
      expect(klass.moderation_enabled?).to be true
      expect(klass.moderation_config[:phases]).to include(:input, :output)
      expect(klass.moderation_config[:threshold]).to eq(0.7)
      expect(klass.cache_enabled?).to be true
      expect(klass.streaming).to be true
      expect(klass.tools).to include(tool)
    end
  end
end
