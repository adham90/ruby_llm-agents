# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageTransformer::DSL do
  let(:transformer_class) do
    Class.new(RubyLLM::Agents::ImageTransformer) do
      def self.name
        "TestTransformer"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_transformer_model = "sdxl"
      c.default_image_size = "1024x1024"
    end
  end

  describe "#size" do
    it "sets and gets the size" do
      transformer_class.size "512x512"
      expect(transformer_class.size).to eq("512x512")
    end

    it "defaults to config default_image_size" do
      expect(transformer_class.size).to eq("1024x1024")
    end
  end

  describe "#strength" do
    it "sets and gets the strength" do
      transformer_class.strength 0.5
      expect(transformer_class.strength).to eq(0.5)
    end

    it "defaults to 0.75" do
      expect(transformer_class.strength).to eq(0.75)
    end

    it "validates strength is between 0.0 and 1.0" do
      expect {
        transformer_class.strength(-0.1)
      }.to raise_error(ArgumentError, /must be between 0.0 and 1.0/)

      expect {
        transformer_class.strength(1.5)
      }.to raise_error(ArgumentError, /must be between 0.0 and 1.0/)
    end

    it "accepts boundary values" do
      transformer_class.strength 0.0
      expect(transformer_class.strength).to eq(0.0)

      transformer_class.strength 1.0
      expect(transformer_class.strength).to eq(1.0)
    end

    it "converts to float" do
      transformer_class.strength 1
      expect(transformer_class.strength).to eq(1.0)
    end
  end

  describe "#preserve_composition" do
    it "sets and gets preserve_composition" do
      transformer_class.preserve_composition false
      expect(transformer_class.preserve_composition).to be false
    end

    it "defaults to true" do
      expect(transformer_class.preserve_composition).to be true
    end
  end

  describe "#content_policy" do
    it "sets and gets the content policy" do
      transformer_class.content_policy :strict
      expect(transformer_class.content_policy).to eq(:strict)
    end

    it "defaults to :standard" do
      expect(transformer_class.content_policy).to eq(:standard)
    end
  end

  describe "#template" do
    it "sets and gets the template" do
      transformer_class.template "anime style, {prompt}"
      expect(transformer_class.template).to eq("anime style, {prompt}")
    end

    it "returns nil by default" do
      expect(transformer_class.template).to be_nil
    end
  end

  describe "#template_string" do
    it "returns the same as template" do
      transformer_class.template "test template"
      expect(transformer_class.template_string).to eq("test template")
    end
  end

  describe "#negative_prompt" do
    it "sets and gets the negative prompt" do
      transformer_class.negative_prompt "blurry, low quality"
      expect(transformer_class.negative_prompt).to eq("blurry, low quality")
    end

    it "returns nil by default" do
      expect(transformer_class.negative_prompt).to be_nil
    end
  end

  describe "#guidance_scale" do
    it "sets and gets the guidance scale" do
      transformer_class.guidance_scale 7.5
      expect(transformer_class.guidance_scale).to eq(7.5)
    end

    it "returns nil by default" do
      expect(transformer_class.guidance_scale).to be_nil
    end
  end

  describe "#steps" do
    it "sets and gets the steps" do
      transformer_class.steps 50
      expect(transformer_class.steps).to eq(50)
    end

    it "returns nil by default" do
      expect(transformer_class.steps).to be_nil
    end
  end

  describe "default_model" do
    it "uses default_transformer_model from config" do
      expect(transformer_class.model).to eq("sdxl")
    end

    it "falls back to 'sdxl' when not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(transformer_class.model).to eq("sdxl")
    end
  end

  describe "combined configuration" do
    it "allows full configuration" do
      transformer_class.model "stable-diffusion"
      transformer_class.size "2048x2048"
      transformer_class.strength 0.6
      transformer_class.preserve_composition false
      transformer_class.content_policy :moderate
      transformer_class.template "cinematic, {prompt}"
      transformer_class.negative_prompt "cartoon, anime"
      transformer_class.guidance_scale 8.0
      transformer_class.steps 30

      expect(transformer_class.model).to eq("stable-diffusion")
      expect(transformer_class.size).to eq("2048x2048")
      expect(transformer_class.strength).to eq(0.6)
      expect(transformer_class.preserve_composition).to be false
      expect(transformer_class.content_policy).to eq(:moderate)
      expect(transformer_class.template).to eq("cinematic, {prompt}")
      expect(transformer_class.negative_prompt).to eq("cartoon, anime")
      expect(transformer_class.guidance_scale).to eq(8.0)
      expect(transformer_class.steps).to eq(30)
    end
  end
end
