# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ModerationDSL do
  # Helper to create a fresh agent class for each test
  def create_agent_class(&block)
    Class.new(RubyLLM::Agents::Base) do
      class_eval(&block) if block
    end
  end

  describe ".moderation with simple phases" do
    it "defaults to :input when no phases specified" do
      klass = create_agent_class { moderation }
      expect(klass.moderation_config[:phases]).to eq([:input])
    end

    it "accepts single phase as symbol" do
      klass = create_agent_class { moderation :output }
      expect(klass.moderation_config[:phases]).to eq([:output])
    end

    it "accepts multiple phases as separate arguments" do
      klass = create_agent_class { moderation :input, :output }
      expect(klass.moderation_config[:phases]).to contain_exactly(:input, :output)
    end

    it "expands :both to [:input, :output]" do
      klass = create_agent_class { moderation :both }
      expect(klass.moderation_config[:phases]).to contain_exactly(:input, :output)
    end

    it "handles :both with other options" do
      klass = create_agent_class { moderation :both, threshold: 0.9 }
      expect(klass.moderation_config[:phases]).to contain_exactly(:input, :output)
      expect(klass.moderation_config[:threshold]).to eq(0.9)
    end

    it "converts string phases to symbols" do
      klass = create_agent_class { moderation "input" }
      expect(klass.moderation_config[:phases]).to eq([:input])
    end
  end

  describe ".moderation with options" do
    it "sets model option" do
      klass = create_agent_class do
        moderation :input, model: "text-moderation-007"
      end
      expect(klass.moderation_config[:model]).to eq("text-moderation-007")
    end

    it "sets threshold option" do
      klass = create_agent_class do
        moderation :input, threshold: 0.75
      end
      expect(klass.moderation_config[:threshold]).to eq(0.75)
    end

    it "accepts threshold at boundaries" do
      low_threshold_class = create_agent_class { moderation :input, threshold: 0.0 }
      high_threshold_class = create_agent_class { moderation :input, threshold: 1.0 }

      expect(low_threshold_class.moderation_config[:threshold]).to eq(0.0)
      expect(high_threshold_class.moderation_config[:threshold]).to eq(1.0)
    end

    it "sets categories as array" do
      klass = create_agent_class do
        moderation :input, categories: [:hate, :violence, :sexual]
      end
      expect(klass.moderation_config[:categories]).to eq([:hate, :violence, :sexual])
    end

    it "sets on_flagged action" do
      %i[block raise warn log].each do |action|
        klass = create_agent_class { moderation :input, on_flagged: action }
        expect(klass.moderation_config[:on_flagged]).to eq(action)
      end
    end

    it "defaults on_flagged to :block" do
      klass = create_agent_class { moderation :input }
      expect(klass.moderation_config[:on_flagged]).to eq(:block)
    end

    it "sets custom_handler" do
      klass = create_agent_class do
        moderation :input, custom_handler: :my_moderation_handler
      end
      expect(klass.moderation_config[:custom_handler]).to eq(:my_moderation_handler)
    end

    it "combines all options" do
      klass = create_agent_class do
        moderation :both,
                   model: "omni-moderation-latest",
                   threshold: 0.8,
                   categories: [:hate, :violence],
                   on_flagged: :raise,
                   custom_handler: :handle_flagged
      end

      config = klass.moderation_config
      expect(config[:phases]).to contain_exactly(:input, :output)
      expect(config[:model]).to eq("omni-moderation-latest")
      expect(config[:threshold]).to eq(0.8)
      expect(config[:categories]).to eq([:hate, :violence])
      expect(config[:on_flagged]).to eq(:raise)
      expect(config[:custom_handler]).to eq(:handle_flagged)
    end
  end

  describe ".moderation_config" do
    it "returns nil when not configured" do
      klass = create_agent_class
      expect(klass.moderation_config).to be_nil
    end

    it "returns configuration hash when configured" do
      klass = create_agent_class { moderation :input }
      expect(klass.moderation_config).to be_a(Hash)
      expect(klass.moderation_config).to have_key(:phases)
    end
  end

  describe ".moderation_enabled?" do
    it "returns false when no moderation configured" do
      klass = create_agent_class
      expect(klass.moderation_enabled?).to be false
    end

    it "returns true when moderation is configured" do
      klass = create_agent_class { moderation :input }
      expect(klass.moderation_enabled?).to be true
    end
  end

  describe "inheritance" do
    it "inherits moderation config from parent" do
      parent = create_agent_class do
        moderation :input, threshold: 0.8, on_flagged: :raise
      end
      child = Class.new(parent)

      expect(child.moderation_config[:phases]).to eq([:input])
      expect(child.moderation_config[:threshold]).to eq(0.8)
      expect(child.moderation_config[:on_flagged]).to eq(:raise)
    end

    it "allows child to override parent moderation config" do
      parent = create_agent_class do
        moderation :input, threshold: 0.8
      end
      child = Class.new(parent) do
        moderation :output, threshold: 0.5, on_flagged: :warn
      end

      # Parent unchanged
      expect(parent.moderation_config[:phases]).to eq([:input])
      expect(parent.moderation_config[:threshold]).to eq(0.8)

      # Child has new config
      expect(child.moderation_config[:phases]).to eq([:output])
      expect(child.moderation_config[:threshold]).to eq(0.5)
      expect(child.moderation_config[:on_flagged]).to eq(:warn)
    end

    it "grandchild inherits from parent with no moderation, grandparent has moderation" do
      grandparent = create_agent_class { moderation :input }
      parent = Class.new(grandparent)
      child = Class.new(parent)

      expect(child.moderation_config[:phases]).to eq([:input])
    end
  end
end

RSpec.describe RubyLLM::Agents::ModerationBuilder do
  subject(:builder) { described_class.new }

  describe "#initialize" do
    it "starts with empty phases" do
      expect(builder.config[:phases]).to eq([])
    end

    it "defaults on_flagged to :block" do
      expect(builder.config[:on_flagged]).to eq(:block)
    end
  end

  describe "#input" do
    it "adds :input to phases when enabled" do
      builder.input(enabled: true)
      expect(builder.config[:phases]).to include(:input)
    end

    it "does not add :input when disabled" do
      builder.input(enabled: false)
      expect(builder.config[:phases]).not_to include(:input)
    end

    it "sets input-specific threshold" do
      builder.input(enabled: true, threshold: 0.6)
      expect(builder.config[:input_threshold]).to eq(0.6)
    end

    it "does not set threshold if not provided" do
      builder.input(enabled: true)
      expect(builder.config[:input_threshold]).to be_nil
    end
  end

  describe "#output" do
    it "adds :output to phases when enabled" do
      builder.output(enabled: true)
      expect(builder.config[:phases]).to include(:output)
    end

    it "does not add :output when disabled" do
      builder.output(enabled: false)
      expect(builder.config[:phases]).not_to include(:output)
    end

    it "sets output-specific threshold" do
      builder.output(enabled: true, threshold: 0.9)
      expect(builder.config[:output_threshold]).to eq(0.9)
    end
  end

  describe "#model" do
    it "sets the moderation model" do
      builder.model("text-moderation-stable")
      expect(builder.config[:model]).to eq("text-moderation-stable")
    end
  end

  describe "#threshold" do
    it "sets the global threshold" do
      builder.threshold(0.7)
      expect(builder.config[:threshold]).to eq(0.7)
    end
  end

  describe "#categories" do
    it "sets categories from arguments" do
      builder.categories(:hate, :violence, :sexual)
      expect(builder.config[:categories]).to eq([:hate, :violence, :sexual])
    end

    it "flattens array arguments" do
      builder.categories([:hate, :violence], :sexual)
      expect(builder.config[:categories]).to eq([:hate, :violence, :sexual])
    end

    it "converts strings to symbols" do
      builder.categories("hate", "violence")
      expect(builder.config[:categories]).to eq([:hate, :violence])
    end
  end

  describe "#on_flagged" do
    it "sets the flagged action" do
      builder.on_flagged(:raise)
      expect(builder.config[:on_flagged]).to eq(:raise)
    end
  end

  describe "#custom_handler" do
    it "sets the custom handler method name" do
      builder.custom_handler(:my_handler)
      expect(builder.config[:custom_handler]).to eq(:my_handler)
    end
  end

  describe "complete builder configuration" do
    it "builds a complete config using all methods" do
      builder.input(enabled: true, threshold: 0.6)
      builder.output(enabled: true, threshold: 0.9)
      builder.model("omni-moderation-latest")
      builder.threshold(0.7)
      builder.categories(:hate, :violence)
      builder.on_flagged(:warn)
      builder.custom_handler(:log_flagged_content)

      config = builder.config

      expect(config[:phases]).to contain_exactly(:input, :output)
      expect(config[:input_threshold]).to eq(0.6)
      expect(config[:output_threshold]).to eq(0.9)
      expect(config[:model]).to eq("omni-moderation-latest")
      expect(config[:threshold]).to eq(0.7)
      expect(config[:categories]).to eq([:hate, :violence])
      expect(config[:on_flagged]).to eq(:warn)
      expect(config[:custom_handler]).to eq(:log_flagged_content)
    end
  end
end
