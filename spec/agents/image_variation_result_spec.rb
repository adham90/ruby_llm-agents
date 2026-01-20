# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageVariationResult do
  let(:mock_image) do
    double(
      "Image",
      url: "https://example.com/variation.png",
      data: nil,
      base64?: false,
      mime_type: "image/png",
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
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        variator_class: "TestVariator"
      )

      expect(result.images).to eq([mock_image])
      expect(result.source_image).to eq("original.png")
      expect(result.model_id).to eq("gpt-image-1")
      expect(result.size).to eq("1024x1024")
      expect(result.variation_strength).to eq(0.5)
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.variator_class).to eq("TestVariator")
    end
  end

  describe "#success?" do
    it "returns true when no error and images present" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        variator_class: "TestVariator"
      )

      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(
        images: [],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        variator_class: "TestVariator",
        error_class: "StandardError"
      )

      expect(result.success?).to be false
    end
  end

  describe "#single? and #batch?" do
    it "returns correct values based on count" do
      single_result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        variator_class: "TestVariator"
      )

      batch_result = described_class.new(
        images: [mock_image, mock_image, mock_image],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        variator_class: "TestVariator"
      )

      expect(single_result.single?).to be true
      expect(single_result.batch?).to be false
      expect(batch_result.single?).to be false
      expect(batch_result.batch?).to be true
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      started = Time.current
      completed = started + 3.seconds

      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: started,
        completed_at: completed,
        tenant_id: nil,
        variator_class: "TestVariator"
      )

      expect(result.duration_ms).to eq(3000)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        model_id: "gpt-image-1",
        size: "1024x1024",
        variation_strength: 0.5,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        variator_class: "TestVariator"
      )

      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:count]).to eq(1)
      expect(hash[:source_image]).to eq("original.png")
      expect(hash[:variation_strength]).to eq(0.5)
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageVariationResult do
  describe "#initialize" do
    it "creates from cached data" do
      cached_data = {
        urls: ["https://example.com/variation.png"],
        datas: [],
        mime_type: "image/png",
        model_id: "gpt-image-1",
        total_cost: 0.04,
        cached_at: Time.current.iso8601
      }

      result = described_class.new(cached_data)

      expect(result.urls).to eq(["https://example.com/variation.png"])
      expect(result.model_id).to eq("gpt-image-1")
      expect(result.cached?).to be true
    end
  end
end
