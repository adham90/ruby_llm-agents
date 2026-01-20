# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageTransformResult do
  let(:mock_image) do
    double(
      "Image",
      url: "https://example.com/transformed.png",
      data: nil,
      base64?: false,
      mime_type: "image/png",
      revised_prompt: "Anime style portrait",
      to_blob: "\x89PNG\r\n",
      save: true
    )
  end

  describe "#initialize" do
    it "sets all required attributes" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        images: [mock_image],
        source_image: "photo.jpg",
        prompt: "Convert to anime style",
        model_id: "sdxl",
        size: "1024x1024",
        strength: 0.8,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        transformer_class: "AnimeTransformer"
      )

      expect(result.images).to eq([mock_image])
      expect(result.source_image).to eq("photo.jpg")
      expect(result.prompt).to eq("Convert to anime style")
      expect(result.model_id).to eq("sdxl")
      expect(result.size).to eq("1024x1024")
      expect(result.strength).to eq(0.8)
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.transformer_class).to eq("AnimeTransformer")
    end
  end

  describe "#success?" do
    it "returns true when no error and images present" do
      result = described_class.new(
        images: [mock_image],
        source_image: "photo.jpg",
        prompt: "Transform prompt",
        model_id: "sdxl",
        size: "1024x1024",
        strength: 0.75,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        transformer_class: "TestTransformer"
      )

      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(
        images: [],
        source_image: "photo.jpg",
        prompt: "Transform prompt",
        model_id: "sdxl",
        size: "1024x1024",
        strength: 0.75,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        transformer_class: "TestTransformer",
        error_class: "StandardError"
      )

      expect(result.success?).to be false
    end
  end

  describe "#single? and #batch?" do
    it "returns correct values based on count" do
      single_result = described_class.new(
        images: [mock_image],
        source_image: "photo.jpg",
        prompt: "Transform",
        model_id: "sdxl",
        size: "1024x1024",
        strength: 0.75,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        transformer_class: "TestTransformer"
      )

      expect(single_result.single?).to be true
      expect(single_result.batch?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      result = described_class.new(
        images: [mock_image],
        source_image: "photo.jpg",
        prompt: "Transform prompt",
        model_id: "sdxl",
        size: "1024x1024",
        strength: 0.8,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        transformer_class: "TestTransformer"
      )

      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:source_image]).to eq("photo.jpg")
      expect(hash[:prompt]).to eq("Transform prompt")
      expect(hash[:strength]).to eq(0.8)
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageTransformResult do
  describe "#initialize" do
    it "creates from cached data" do
      cached_data = {
        urls: ["https://example.com/transformed.png"],
        datas: [],
        mime_type: "image/png",
        model_id: "sdxl",
        total_cost: 0.04,
        cached_at: Time.current.iso8601
      }

      result = described_class.new(cached_data)

      expect(result.urls).to eq(["https://example.com/transformed.png"])
      expect(result.model_id).to eq("sdxl")
      expect(result.cached?).to be true
    end
  end
end
