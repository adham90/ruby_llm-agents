# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageUpscaler::DSL do
  let(:upscaler_class) do
    Class.new(RubyLLM::Agents::ImageUpscaler) do
      def self.name
        "TestUpscaler"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_upscaler_model = "real-esrgan"
    end
  end

  describe "#scale" do
    it "sets and gets the scale" do
      upscaler_class.scale 2
      expect(upscaler_class.scale).to eq(2)
    end

    it "defaults to 4" do
      expect(upscaler_class.scale).to eq(4)
    end

    it "validates scale is one of valid values" do
      expect {
        upscaler_class.scale 3
      }.to raise_error(ArgumentError, /Scale must be one of: 2, 4, 8/)

      expect {
        upscaler_class.scale 16
      }.to raise_error(ArgumentError, /Scale must be one of/)
    end

    it "accepts all valid scales" do
      [2, 4, 8].each do |s|
        upscaler_class.scale s
        expect(upscaler_class.scale).to eq(s)
      end
    end
  end

  describe "#face_enhance" do
    it "sets and gets face_enhance" do
      upscaler_class.face_enhance true
      expect(upscaler_class.face_enhance).to be true
    end

    it "defaults to false" do
      expect(upscaler_class.face_enhance).to be false
    end

    it "allows setting to false" do
      upscaler_class.face_enhance true
      upscaler_class.face_enhance false
      expect(upscaler_class.face_enhance).to be false
    end
  end

  describe "#denoise_strength" do
    it "sets and gets the denoise strength" do
      upscaler_class.denoise_strength 0.3
      expect(upscaler_class.denoise_strength).to eq(0.3)
    end

    it "defaults to 0.5" do
      expect(upscaler_class.denoise_strength).to eq(0.5)
    end

    it "validates denoise_strength is between 0.0 and 1.0" do
      expect {
        upscaler_class.denoise_strength(-0.1)
      }.to raise_error(ArgumentError, /must be between 0.0 and 1.0/)

      expect {
        upscaler_class.denoise_strength(1.5)
      }.to raise_error(ArgumentError, /must be between 0.0 and 1.0/)
    end

    it "accepts boundary values" do
      upscaler_class.denoise_strength 0.0
      expect(upscaler_class.denoise_strength).to eq(0.0)

      upscaler_class.denoise_strength 1.0
      expect(upscaler_class.denoise_strength).to eq(1.0)
    end

    it "converts to float" do
      upscaler_class.denoise_strength 1
      expect(upscaler_class.denoise_strength).to eq(1.0)
    end
  end

  describe "default_model" do
    it "uses default_upscaler_model from config" do
      expect(upscaler_class.model).to eq("real-esrgan")
    end

    it "falls back to 'real-esrgan' when not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(upscaler_class.model).to eq("real-esrgan")
    end
  end

  describe "combined configuration" do
    it "allows full configuration" do
      upscaler_class.model "espcn"
      upscaler_class.scale 8
      upscaler_class.face_enhance true
      upscaler_class.denoise_strength 0.7
      upscaler_class.cache_for 3600

      expect(upscaler_class.model).to eq("espcn")
      expect(upscaler_class.scale).to eq(8)
      expect(upscaler_class.face_enhance).to be true
      expect(upscaler_class.denoise_strength).to eq(0.7)
      expect(upscaler_class.cache_ttl).to eq(3600)
    end
  end
end
