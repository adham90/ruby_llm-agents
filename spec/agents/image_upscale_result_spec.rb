# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageUpscaleResult do
  let(:mock_image) do
    RubyLLM::Agents::TestSupport::MockImage.upscaled
  end

  describe "#initialize" do
    it "sets all required attributes" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        face_enhance: true,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        upscaler_class: "PhotoUpscaler"
      )

      expect(result.image).to eq(mock_image)
      expect(result.source_image).to eq("low_res.jpg")
      expect(result.model_id).to eq("real-esrgan")
      expect(result.scale).to eq(4)
      expect(result.output_size).to eq("4096x4096")
      expect(result.face_enhance).to be true
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.upscaler_class).to eq("PhotoUpscaler")
    end
  end

  describe "#success?" do
    it "returns true when no error and image present" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(
        image: nil,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: nil,
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler",
        error_class: "StandardError",
        error_message: "API error"
      )

      expect(result.success?).to be false
      expect(result.error?).to be true
    end

    it "returns false when image is nil" do
      result = described_class.new(
        image: nil,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: nil,
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.success?).to be false
    end
  end

  describe "#single? and #batch?" do
    it "always returns single true and batch false for upscaling" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.single?).to be true
      expect(result.batch?).to be false
    end
  end

  describe "#count" do
    it "returns 1 when successful" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.count).to eq(1)
    end

    it "returns 0 when failed" do
      result = described_class.new(
        image: nil,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: nil,
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler",
        error_class: "StandardError"
      )

      expect(result.count).to eq(0)
    end
  end

  describe "#output_width and #output_height" do
    it "parses dimensions from output_size" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x3072",
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.output_width).to eq(4096)
      expect(result.output_height).to eq(3072)
    end

    it "returns nil when output_size is nil" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: nil,
        face_enhance: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      expect(result.output_width).to be_nil
      expect(result.output_height).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      result = described_class.new(
        image: mock_image,
        source_image: "low_res.jpg",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        face_enhance: true,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        upscaler_class: "TestUpscaler"
      )

      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:source_image]).to eq("low_res.jpg")
      expect(hash[:scale]).to eq(4)
      expect(hash[:output_size]).to eq("4096x4096")
      expect(hash[:face_enhance]).to be true
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageUpscaleResult do
  describe "#initialize" do
    it "creates from cached data" do
      cached_data = {
        url: "https://example.com/upscaled.png",
        data: nil,
        mime_type: "image/png",
        model_id: "real-esrgan",
        scale: 4,
        output_size: "4096x4096",
        total_cost: 0.01,
        cached_at: Time.current.iso8601
      }

      result = described_class.new(cached_data)

      expect(result.url).to eq("https://example.com/upscaled.png")
      expect(result.scale).to eq(4)
      expect(result.output_size).to eq("4096x4096")
      expect(result.cached?).to be true
    end
  end

  describe "#success?" do
    it "returns true when url present" do
      result = described_class.new(url: "https://example.com/upscaled.png")
      expect(result.success?).to be true
    end

    it "returns true when data present" do
      result = described_class.new(data: "base64data")
      expect(result.success?).to be true
    end

    it "returns false when both nil" do
      result = described_class.new(url: nil, data: nil)
      expect(result.success?).to be false
    end
  end
end
