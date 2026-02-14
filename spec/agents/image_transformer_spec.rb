# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageTransformer do
  describe "DSL" do
    let(:test_transformer_class) do
      Class.new(described_class) do
        model "sdxl"
        size "1024x1024"
        strength 0.8
        preserve_composition true
        template "anime style, {prompt}"
        negative_prompt "blurry, low quality"
        guidance_scale 7.5
        steps 30
        description "Test transformer"
      end
    end

    it "sets model" do
      expect(test_transformer_class.model).to eq("sdxl")
    end

    it "sets size" do
      expect(test_transformer_class.size).to eq("1024x1024")
    end

    it "sets strength" do
      expect(test_transformer_class.strength).to eq(0.8)
    end

    it "sets preserve_composition" do
      expect(test_transformer_class.preserve_composition).to be true
    end

    it "sets template" do
      expect(test_transformer_class.template).to eq("anime style, {prompt}")
      expect(test_transformer_class.template_string).to eq("anime style, {prompt}")
    end

    it "sets negative_prompt" do
      expect(test_transformer_class.negative_prompt).to eq("blurry, low quality")
    end

    it "sets guidance_scale" do
      expect(test_transformer_class.guidance_scale).to eq(7.5)
    end

    it "sets steps" do
      expect(test_transformer_class.steps).to eq(30)
    end

    it "sets description" do
      expect(test_transformer_class.description).to eq("Test transformer")
    end

    it "validates strength range" do
      expect {
        Class.new(described_class) do
          strength 1.5
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end

    it "validates strength is not negative" do
      expect {
        Class.new(described_class) do
          strength(-0.5)
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end
  end

  describe "defaults" do
    let(:default_transformer) do
      Class.new(described_class)
    end

    it "has default strength of 0.75" do
      expect(default_transformer.strength).to eq(0.75)
    end

    it "has preserve_composition true by default" do
      expect(default_transformer.preserve_composition).to be true
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-model"
        strength 0.6
        template "parent template, {prompt}"
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-model")
      expect(child_class.strength).to eq(0.6)
      expect(child_class.template_string).to eq("parent template, {prompt}")
    end
  end

  describe ".call" do
    let(:transformer_class) do
      Class.new(described_class) do
        model "sdxl"
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(transformer_class)
      allow(transformer_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      transformer_class.call(image: "photo.jpg", prompt: "Convert to watercolor")

      expect(transformer_class).to have_received(:new).with(
        image: "photo.jpg",
        prompt: "Convert to watercolor"
      )
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image, prompt and options" do
      transformer = described_class.new(
        image: "photo.jpg",
        prompt: "anime style",
        strength: 0.9
      )

      expect(transformer.image).to eq("photo.jpg")
      expect(transformer.prompt).to eq("anime style")
      expect(transformer.options).to eq({ strength: 0.9 })
    end
  end
end
