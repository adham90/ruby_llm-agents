# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::ImagePipeline do
  # Mock classes for testing steps
  let(:mock_generator) do
    Class.new do
      def self.call(**_options)
        OpenStruct.new(success?: true, url: "https://example.com/generated.png", total_cost: 0.04)
      end
    end
  end

  let(:mock_upscaler) do
    Class.new do
      def self.call(**_options)
        OpenStruct.new(success?: true, url: "https://example.com/upscaled.png", total_cost: 0.01)
      end
    end
  end

  let(:mock_analyzer) do
    Class.new do
      def self.call(**_options)
        OpenStruct.new(
          success?: true,
          caption: "A test image",
          tags: ["test", "image"],
          total_cost: 0.001
        )
      end
    end
  end

  let(:mock_remover) do
    Class.new do
      def self.call(**_options)
        OpenStruct.new(success?: true, url: "https://example.com/removed.png", total_cost: 0.01)
      end
    end
  end

  let(:failing_step) do
    Class.new do
      def self.call(**_options)
        OpenStruct.new(success?: false, error?: true, url: nil, total_cost: 0)
      end
    end
  end

  describe "DSL" do
    describe "step definition" do
      let(:test_pipeline_class) do
        gen = mock_generator
        up = mock_upscaler

        Class.new(described_class) do
          step :generate, generator: gen
          step :upscale, upscaler: up, scale: 2

          version "v1"
          description "Test pipeline"
        end
      end

      it "defines steps" do
        expect(test_pipeline_class.steps.size).to eq(2)
      end

      it "captures step configuration" do
        generate_step = test_pipeline_class.steps.find { |s| s[:name] == :generate }
        expect(generate_step[:type]).to eq(:generator)
        expect(generate_step[:config][:generator]).to eq(mock_generator)
      end

      it "captures step options" do
        upscale_step = test_pipeline_class.steps.find { |s| s[:name] == :upscale }
        expect(upscale_step[:config][:scale]).to eq(2)
      end

      it "sets version" do
        expect(test_pipeline_class.version).to eq("v1")
      end

      it "sets description" do
        expect(test_pipeline_class.description).to eq("Test pipeline")
      end
    end

    describe "step validation" do
      it "rejects duplicate step names" do
        gen = mock_generator
        expect {
          Class.new(described_class) do
            step :test, generator: gen
            step :test, generator: gen
          end
        }.to raise_error(ArgumentError, /already defined/)
      end

      it "rejects steps without valid type" do
        expect {
          Class.new(described_class) do
            step :test, invalid: "something"
          end
        }.to raise_error(ArgumentError, /must specify one of/)
      end

      it "rejects steps with multiple types" do
        gen = mock_generator
        up = mock_upscaler
        expect {
          Class.new(described_class) do
            step :test, generator: gen, upscaler: up
          end
        }.to raise_error(ArgumentError, /can only specify one step type/)
      end

      it "rejects steps with non-callable class" do
        expect {
          Class.new(described_class) do
            step :test, generator: "NotAClass"
          end
        }.to raise_error(ArgumentError, /must respond to \.call/)
      end
    end

    describe "all step types" do
      it "accepts generator steps" do
        gen = mock_generator
        expect {
          Class.new(described_class) { step :gen, generator: gen }
        }.not_to raise_error
      end

      it "accepts upscaler steps" do
        up = mock_upscaler
        expect {
          Class.new(described_class) { step :up, upscaler: up }
        }.not_to raise_error
      end

      it "accepts analyzer steps" do
        an = mock_analyzer
        expect {
          Class.new(described_class) { step :an, analyzer: an }
        }.not_to raise_error
      end

      it "accepts remover steps" do
        rm = mock_remover
        expect {
          Class.new(described_class) { step :rm, remover: rm }
        }.not_to raise_error
      end
    end

    describe "conditional steps" do
      it "accepts :if condition" do
        gen = mock_generator
        expect {
          Class.new(described_class) do
            step :gen, generator: gen, if: ->(ctx) { ctx[:generate] }
          end
        }.not_to raise_error
      end

      it "accepts :unless condition" do
        gen = mock_generator
        expect {
          Class.new(described_class) do
            step :gen, generator: gen, unless: ->(ctx) { ctx[:skip] }
          end
        }.not_to raise_error
      end
    end

    describe "stop_on_error" do
      it "defaults to true" do
        pipeline_class = Class.new(described_class)
        expect(pipeline_class.stop_on_error?).to be true
      end

      it "can be set to false" do
        pipeline_class = Class.new(described_class) do
          stop_on_error false
        end
        expect(pipeline_class.stop_on_error?).to be false
      end
    end

    describe "caching" do
      let(:cached_pipeline) do
        gen = mock_generator
        Class.new(described_class) do
          step :generate, generator: gen
          cache_for 1.hour
        end
      end

      it "enables caching with TTL" do
        expect(cached_pipeline.cache_enabled?).to be true
        expect(cached_pipeline.cache_ttl).to eq(1.hour)
      end

      let(:uncached_pipeline) do
        gen = mock_generator
        Class.new(described_class) do
          step :generate, generator: gen
        end
      end

      it "disables caching by default" do
        expect(uncached_pipeline.cache_enabled?).to be false
      end
    end

    describe "callbacks" do
      it "registers before_pipeline callbacks" do
        pipeline_class = Class.new(described_class) do
          before_pipeline :setup
          before_pipeline { |_| "block" }
        end

        expect(pipeline_class.callbacks[:before].size).to eq(2)
        expect(pipeline_class.callbacks[:before].first).to eq(:setup)
      end

      it "registers after_pipeline callbacks" do
        pipeline_class = Class.new(described_class) do
          after_pipeline :cleanup
          after_pipeline { |_result| "block" }
        end

        expect(pipeline_class.callbacks[:after].size).to eq(2)
        expect(pipeline_class.callbacks[:after].first).to eq(:cleanup)
      end
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      gen = mock_generator

      Class.new(described_class) do
        step :generate, generator: gen
        version "parent"
        stop_on_error false
      end
    end

    let(:child_class) do
      up = mock_upscaler

      Class.new(parent_class) do
        step :upscale, upscaler: up
      end
    end

    it "inherits steps from parent" do
      expect(child_class.steps.size).to eq(2)
    end

    it "inherits version from parent" do
      expect(child_class.version).to eq("parent")
    end

    it "inherits stop_on_error from parent" do
      expect(child_class.stop_on_error?).to be false
    end
  end

  describe ".call" do
    let(:pipeline_class) do
      gen = mock_generator

      Class.new(described_class) do
        step :generate, generator: gen
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(pipeline_class)
      allow(pipeline_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      pipeline_class.call(prompt: "test prompt")

      expect(pipeline_class).to have_received(:new).with(prompt: "test prompt")
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets options and context" do
      pipeline = described_class.new(prompt: "test", tenant: "org1")

      expect(pipeline.options).to eq({ prompt: "test", tenant: "org1" })
      expect(pipeline.context).to eq({ prompt: "test", tenant: "org1" })
    end

    it "initializes with empty step results" do
      pipeline = described_class.new(prompt: "test")
      expect(pipeline.step_results).to eq([])
    end
  end
end
