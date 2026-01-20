# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageEditResult do
  let(:mock_image) do
    double(
      "Image",
      url: "https://example.com/edited.png",
      data: nil,
      base64?: false,
      mime_type: "image/png",
      revised_prompt: "Edited background",
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
