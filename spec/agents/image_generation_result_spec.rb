# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerationResult do
  let(:mock_image) do
    double(
      "Image",
      url: "https://example.com/image.png",
      data: nil,
      base64?: false,
      mime_type: "image/png",
      revised_prompt: "A beautiful sunset over mountains",
      to_blob: "\x89PNG\r\n",
      save: true
    )
  end

  let(:base64_image) do
    double(
      "Base64Image",
      url: nil,
      data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
      base64?: true,
      mime_type: "image/png",
      revised_prompt: nil,
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
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        generator_class: "TestGenerator"
      )

      expect(result.images).to eq([mock_image])
      expect(result.prompt).to eq("A sunset")
      expect(result.model_id).to eq("gpt-image-1")
      expect(result.size).to eq("1024x1024")
      expect(result.quality).to eq("standard")
      expect(result.style).to eq("vivid")
      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.generator_class).to eq("TestGenerator")
    end

    it "sets error info when provided" do
      result = described_class.new(
        images: [],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator",
        error_class: "StandardError",
        error_message: "API error"
      )

      expect(result.error_class).to eq("StandardError")
      expect(result.error_message).to eq("API error")
    end
  end

  describe "#success?" do
    it "returns true when no error and images present" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(
        images: [],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator",
        error_class: "StandardError"
      )

      expect(result.success?).to be false
    end

    it "returns false when images is empty" do
      result = described_class.new(
        images: [],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns the opposite of success?" do
      success_result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      error_result = described_class.new(
        images: [],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator",
        error_class: "StandardError"
      )

      expect(success_result.error?).to be false
      expect(error_result.error?).to be true
    end
  end

  describe "#single?" do
    it "returns true when count is 1" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.single?).to be true
    end
  end

  describe "#batch?" do
    it "returns true when count > 1" do
      result = described_class.new(
        images: [mock_image, mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.batch?).to be true
    end
  end

  describe "#url" do
    it "returns the URL of the first image" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.url).to eq("https://example.com/image.png")
    end
  end

  describe "#urls" do
    it "returns all image URLs" do
      image2 = double("Image2", url: "https://example.com/image2.png")

      result = described_class.new(
        images: [mock_image, image2],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.urls).to eq([
        "https://example.com/image.png",
        "https://example.com/image2.png"
      ])
    end
  end

  describe "#base64?" do
    it "returns true for base64 encoded images" do
      result = described_class.new(
        images: [base64_image],
        prompt: "A sunset",
        model_id: "imagen-3",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.base64?).to be true
    end

    it "returns false for URL-based images" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.base64?).to be false
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      started = Time.current
      completed = started + 2.5.seconds

      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: started,
        completed_at: completed,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.duration_ms).to eq(2500)
    end
  end

  describe "#count" do
    it "returns the number of images" do
      result = described_class.new(
        images: [mock_image, mock_image, mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      expect(result.count).to eq(3)
    end
  end

  describe "#input_tokens" do
    it "estimates tokens from prompt length" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A beautiful sunset over the mountains", # 40 chars
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      # 40 chars / 4 = 10 tokens
      expect(result.input_tokens).to eq(10)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        generator_class: "TestGenerator"
      )

      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:count]).to eq(1)
      expect(hash[:urls]).to eq(["https://example.com/image.png"])
      expect(hash[:model_id]).to eq("gpt-image-1")
      expect(hash[:size]).to eq("1024x1024")
      expect(hash[:quality]).to eq("standard")
      expect(hash[:style]).to eq("vivid")
      expect(hash[:tenant_id]).to eq("tenant-123")
    end
  end

  describe "#to_cache" do
    it "returns a cacheable hash" do
      result = described_class.new(
        images: [mock_image],
        prompt: "A sunset",
        model_id: "gpt-image-1",
        size: "1024x1024",
        quality: "standard",
        style: "vivid",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        generator_class: "TestGenerator"
      )

      cache = result.to_cache

      expect(cache[:urls]).to eq(["https://example.com/image.png"])
      expect(cache[:model_id]).to eq("gpt-image-1")
      expect(cache).to have_key(:cached_at)
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageGenerationResult do
  describe "#initialize" do
    it "creates from cached data" do
      cached_data = {
        urls: ["https://example.com/image.png"],
        datas: [],
        mime_type: "image/png",
        revised_prompts: ["A beautiful sunset"],
        model_id: "gpt-image-1",
        total_cost: 0.04,
        cached_at: Time.current.iso8601
      }

      result = described_class.new(cached_data)

      expect(result.urls).to eq(["https://example.com/image.png"])
      expect(result.model_id).to eq("gpt-image-1")
      expect(result.total_cost).to eq(0.04)
      expect(result.cached?).to be true
    end
  end

  describe "#success?" do
    it "returns true when urls present" do
      result = described_class.new(urls: ["https://example.com/image.png"])
      expect(result.success?).to be true
    end

    it "returns true when datas present" do
      result = described_class.new(datas: ["base64data"])
      expect(result.success?).to be true
    end

    it "returns false when both empty" do
      result = described_class.new(urls: [], datas: [])
      expect(result.success?).to be false
    end
  end
end
