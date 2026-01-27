# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageEditResult do
  let(:mock_image) do
    RubyLLM::Agents::TestSupport::MockImage.edited
  end

  describe "#initialize" do
    it "sets all required attributes" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: "mask.png",
        prompt: "Replace background with beach",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123",
        editor_class: "TestEditor"
      )

      expect(result.images).to eq([mock_image])
      expect(result.source_image).to eq("original.png")
      expect(result.mask).to eq("mask.png")
      expect(result.prompt).to eq("Replace background with beach")
      expect(result.model_id).to eq("gpt-image-1")
      expect(result.size).to eq("1024x1024")
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.editor_class).to eq("TestEditor")
    end
  end

  describe "#success?" do
    it "returns true when no error and images present" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: "mask.png",
        prompt: "Edit prompt",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(
        images: [],
        source_image: "original.png",
        mask: "mask.png",
        prompt: "Edit prompt",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor",
        error_class: "StandardError",
        error_message: "API error"
      )

      expect(result.success?).to be false
      expect(result.error?).to be true
    end
  end

  describe "#input_tokens" do
    it "estimates tokens from prompt length" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: "mask.png",
        prompt: "Replace the background with a sunset", # 36 chars
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      # 36 chars / 4 = 9 tokens
      expect(result.input_tokens).to eq(9)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: "mask.png",
        prompt: "Edit prompt",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      hash = result.to_h

      expect(hash[:success]).to be true
      expect(hash[:source_image]).to eq("original.png")
      expect(hash[:prompt]).to eq("Edit prompt")
    end
  end

  describe "#single?" do
    it "returns true when count is 1" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.single?).to be true
    end
  end

  describe "#batch?" do
    it "returns true when count > 1" do
      result = described_class.new(
        images: [mock_image, mock_image],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.batch?).to be true
    end
  end

  describe "#url" do
    it "returns the URL of the first image" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.url).to eq(mock_image.url)
    end
  end

  describe "#urls" do
    it "returns all image URLs" do
      img2 = RubyLLM::Agents::TestSupport::MockImage.with_url("https://example.com/edited2.png")
      result = described_class.new(
        images: [mock_image, img2],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.urls.size).to eq(2)
    end
  end

  describe "#data" do
    it "returns base64 data of the first image" do
      base64_img = RubyLLM::Agents::TestSupport::MockImage.with_base64("base64data")
      result = described_class.new(
        images: [base64_img],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.data).to eq("base64data")
    end
  end

  describe "#datas" do
    it "returns all base64 data" do
      img1 = RubyLLM::Agents::TestSupport::MockImage.with_base64("data1")
      img2 = RubyLLM::Agents::TestSupport::MockImage.with_base64("data2")
      result = described_class.new(
        images: [img1, img2],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.datas).to eq(["data1", "data2"])
    end
  end

  describe "#revised_prompt" do
    it "returns revised prompt of first image" do
      revised_img = RubyLLM::Agents::TestSupport::MockImage.with_url(
        "https://example.com/edited.png",
        revised_prompt: "Revised edit prompt"
      )
      result = described_class.new(
        images: [revised_img],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.revised_prompt).to eq("Revised edit prompt")
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      started = Time.current
      completed = started + 1.5.seconds
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: started,
        completed_at: completed,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.duration_ms).to eq(1500)
    end

    it "returns 0 when timing info is missing" do
      result = described_class.new(
        images: [mock_image],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: nil,
        completed_at: nil,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.duration_ms).to eq(0)
    end
  end

  describe "#save" do
    it "raises error when no image" do
      result = described_class.new(
        images: [],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect { result.save("/tmp/test.png") }.to raise_error("No image to save")
    end

    it "delegates to image.save" do
      saveable = RubyLLM::Agents::TestSupport::MockImage.edited
      allow(saveable).to receive(:save)

      result = described_class.new(
        images: [saveable],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      result.save("/tmp/test.png")
      expect(saveable).to have_received(:save).with("/tmp/test.png")
    end
  end

  describe "#save_all" do
    it "saves all images" do
      img1 = RubyLLM::Agents::TestSupport::MockImage.edited
      img2 = RubyLLM::Agents::TestSupport::MockImage.edited
      allow(img1).to receive(:save)
      allow(img2).to receive(:save)

      result = described_class.new(
        images: [img1, img2],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      result.save_all("/tmp/images")

      expect(img1).to have_received(:save).with("/tmp/images/edited_1.png")
      expect(img2).to have_received(:save).with("/tmp/images/edited_2.png")
    end
  end

  describe "#to_blob" do
    it "returns binary data of first image" do
      blob_img = RubyLLM::Agents::TestSupport::MockImage.edited
      allow(blob_img).to receive(:to_blob).and_return("binary")

      result = described_class.new(
        images: [blob_img],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.to_blob).to eq("binary")
    end
  end

  describe "#blobs" do
    it "returns all binary data" do
      img1 = RubyLLM::Agents::TestSupport::MockImage.edited
      img2 = RubyLLM::Agents::TestSupport::MockImage.edited
      allow(img1).to receive(:to_blob).and_return("blob1")
      allow(img2).to receive(:to_blob).and_return("blob2")

      result = described_class.new(
        images: [img1, img2],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor"
      )

      expect(result.blobs).to eq(["blob1", "blob2"])
    end
  end

  describe "#total_cost" do
    it "returns 0 for error results" do
      result = described_class.new(
        images: [],
        source_image: "original.png",
        mask: nil,
        prompt: "Edit",
        model_id: "gpt-image-1",
        size: "1024x1024",
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        editor_class: "TestEditor",
        error_class: "StandardError"
      )

      expect(result.total_cost).to eq(0)
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageEditResult do
  describe "#initialize" do
    it "creates from cached data" do
      cached_data = {
        urls: ["https://example.com/edited.png"],
        datas: [],
        mime_type: "image/png",
        model_id: "gpt-image-1",
        total_cost: 0.04,
        cached_at: Time.current.iso8601
      }

      result = described_class.new(cached_data)

      expect(result.urls).to eq(["https://example.com/edited.png"])
      expect(result.cached?).to be true
    end
  end
end
