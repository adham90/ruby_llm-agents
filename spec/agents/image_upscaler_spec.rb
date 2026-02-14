# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageUpscaler do
  describe "DSL" do
    let(:test_upscaler_class) do
      Class.new(described_class) do
        model "real-esrgan"
        scale 4
        face_enhance true
        denoise_strength 0.3
        description "Test upscaler"
      end
    end

    it "sets model" do
      expect(test_upscaler_class.model).to eq("real-esrgan")
    end

    it "sets scale" do
      expect(test_upscaler_class.scale).to eq(4)
    end

    it "sets face_enhance" do
      expect(test_upscaler_class.face_enhance).to be true
    end

    it "sets denoise_strength" do
      expect(test_upscaler_class.denoise_strength).to eq(0.3)
    end

    it "sets description" do
      expect(test_upscaler_class.description).to eq("Test upscaler")
    end

    it "validates scale is 2, 4, or 8" do
      expect {
        Class.new(described_class) do
          scale 3
        end
      }.to raise_error(ArgumentError, /must be one of: 2, 4, 8/)
    end

    it "validates scale is not 1" do
      expect {
        Class.new(described_class) do
          scale 1
        end
      }.to raise_error(ArgumentError, /must be one of: 2, 4, 8/)
    end

    it "validates denoise_strength range" do
      expect {
        Class.new(described_class) do
          denoise_strength 1.5
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end

    it "validates denoise_strength is not negative" do
      expect {
        Class.new(described_class) do
          denoise_strength(-0.1)
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end
  end

  describe "defaults" do
    let(:default_upscaler) do
      Class.new(described_class)
    end

    it "has default scale of 4" do
      expect(default_upscaler.scale).to eq(4)
    end

    it "has face_enhance false by default" do
      expect(default_upscaler.face_enhance).to be false
    end

    it "has default denoise_strength of 0.5" do
      expect(default_upscaler.denoise_strength).to eq(0.5)
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-upscaler"
        scale 8
        face_enhance true
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-upscaler")
      expect(child_class.scale).to eq(8)
      expect(child_class.face_enhance).to be true
    end
  end

  describe ".call" do
    let(:upscaler_class) do
      Class.new(described_class) do
        model "real-esrgan"
        scale 4
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(upscaler_class)
      allow(upscaler_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      upscaler_class.call(image: "low_res.jpg")

      expect(upscaler_class).to have_received(:new).with(image: "low_res.jpg")
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image and options" do
      upscaler = described_class.new(image: "photo.jpg", scale: 8, face_enhance: true)

      expect(upscaler.image).to eq("photo.jpg")
      expect(upscaler.options).to eq({ scale: 8, face_enhance: true })
    end
  end

  describe "caching" do
    let(:cached_upscaler) do
      Class.new(described_class) do
        model "real-esrgan"
        cache_for 1.day
      end
    end

    it "enables caching with TTL" do
      expect(cached_upscaler.cache_enabled?).to be true
      expect(cached_upscaler.cache_ttl).to eq(1.day)
    end

    let(:uncached_upscaler) do
      Class.new(described_class) do
        model "real-esrgan"
      end
    end

    it "disables caching by default" do
      expect(uncached_upscaler.cache_enabled?).to be false
    end
  end
end
