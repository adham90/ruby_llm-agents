# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BackgroundRemovalResult do
  let(:mock_foreground) do
    RubyLLM::Agents::TestSupport::MockImage.foreground
  end

  let(:mock_mask) do
    RubyLLM::Agents::TestSupport::MockImage.mask
  end

  let(:successful_result) do
    described_class.new(
      foreground: mock_foreground,
      mask: mock_mask,
      source_image: "photo.jpg",
      model_id: "rembg",
      output_format: :png,
      alpha_matting: true,
      refine_edges: true,
      started_at: 2.seconds.ago,
      completed_at: Time.current,
      tenant_id: "tenant-123",
      remover_class: "TestRemover"
    )
  end

  let(:result_without_mask) do
    described_class.new(
      foreground: mock_foreground,
      mask: nil,
      source_image: "photo.jpg",
      model_id: "rembg",
      output_format: :png,
      alpha_matting: false,
      refine_edges: false,
      started_at: 1.second.ago,
      completed_at: Time.current,
      tenant_id: nil,
      remover_class: "TestRemover"
    )
  end

  let(:error_result) do
    described_class.new(
      foreground: nil,
      mask: nil,
      source_image: "photo.jpg",
      model_id: "rembg",
      output_format: :png,
      alpha_matting: false,
      refine_edges: false,
      started_at: 1.second.ago,
      completed_at: Time.current,
      tenant_id: nil,
      remover_class: "TestRemover",
      error_class: "RuntimeError",
      error_message: "Model not available"
    )
  end

  describe "#success?" do
    it "returns true when foreground is present" do
      expect(successful_result.success?).to be true
    end

    it "returns false when there is an error" do
      expect(error_result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns false when successful" do
      expect(successful_result.error?).to be false
    end

    it "returns true when there is an error" do
      expect(error_result.error?).to be true
    end
  end

  describe "#image" do
    it "returns the foreground image" do
      expect(successful_result.image).to eq(mock_foreground)
    end
  end

  describe "#url" do
    it "returns the foreground URL" do
      expect(successful_result.url).to eq("https://example.com/foreground.png")
    end

    it "returns nil for error result" do
      expect(error_result.url).to be_nil
    end
  end

  describe "#urls" do
    it "returns array with foreground URL" do
      expect(successful_result.urls).to eq(["https://example.com/foreground.png"])
    end

    it "returns empty array for error result" do
      expect(error_result.urls).to be_empty
    end
  end

  describe "#data" do
    it "returns the foreground data" do
      expect(successful_result.data).to eq("base64data")
    end
  end

  describe "#base64?" do
    it "returns true when foreground is base64" do
      expect(successful_result.base64?).to be true
    end

    it "returns false for error result" do
      expect(error_result.base64?).to be false
    end
  end

  describe "#mime_type" do
    it "returns the mime type from foreground" do
      expect(successful_result.mime_type).to eq("image/png")
    end

    it "falls back to format-based mime type" do
      result_without_foreground_mime = described_class.new(
        foreground: RubyLLM::Agents::TestSupport::MockImage.new(url: "url", mime_type: nil),
        mask: nil,
        source_image: "photo.jpg",
        model_id: "rembg",
        output_format: :webp,
        alpha_matting: false,
        refine_edges: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        remover_class: "Test"
      )
      expect(result_without_foreground_mime.mime_type).to eq("image/webp")
    end
  end

  describe "#mask?" do
    it "returns true when mask is present" do
      expect(successful_result.mask?).to be true
    end

    it "returns false when mask is nil" do
      expect(result_without_mask.mask?).to be false
    end
  end

  describe "#mask_url" do
    it "returns the mask URL" do
      expect(successful_result.mask_url).to eq("https://example.com/mask.png")
    end

    it "returns nil when no mask" do
      expect(result_without_mask.mask_url).to be_nil
    end
  end

  describe "#mask_data" do
    it "returns the mask data" do
      expect(successful_result.mask_data).to eq("mask_base64")
    end
  end

  describe "#has_alpha?" do
    it "returns true for PNG format" do
      expect(successful_result.has_alpha?).to be true
    end

    it "returns true for WebP format" do
      webp_result = described_class.new(
        foreground: mock_foreground,
        mask: nil,
        source_image: "photo.jpg",
        model_id: "rembg",
        output_format: :webp,
        alpha_matting: false,
        refine_edges: false,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        remover_class: "Test"
      )
      expect(webp_result.has_alpha?).to be true
    end

    it "returns false for error result" do
      expect(error_result.has_alpha?).to be false
    end
  end

  describe "#count" do
    it "returns 1 for successful result" do
      expect(successful_result.count).to eq(1)
    end

    it "returns 0 for error result" do
      expect(error_result.count).to eq(0)
    end
  end

  describe "#single?" do
    it "always returns true" do
      expect(successful_result.single?).to be true
      expect(error_result.single?).to be true
    end
  end

  describe "#batch?" do
    it "always returns false" do
      expect(successful_result.batch?).to be false
      expect(error_result.batch?).to be false
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      expect(successful_result.duration_ms).to be > 0
    end
  end

  describe "#save" do
    it "saves the foreground image" do
      successful_result.save("/tmp/output.png")
      expect(mock_foreground.saved_paths).to include("/tmp/output.png")
    end

    it "raises error when no foreground" do
      expect { error_result.save("/tmp/output.png") }.to raise_error("No foreground image to save")
    end
  end

  describe "#save_mask" do
    it "saves the mask image" do
      successful_result.save_mask("/tmp/mask.png")
      expect(mock_mask.saved_paths).to include("/tmp/mask.png")
    end

    it "raises error when no mask" do
      expect { result_without_mask.save_mask("/tmp/mask.png") }.to raise_error("No mask to save")
    end
  end

  describe "#to_blob" do
    it "returns the foreground blob" do
      expect(successful_result.to_blob).to eq("blob_data")
    end
  end

  describe "#mask_blob" do
    it "returns the mask blob" do
      expect(successful_result.mask_blob).to eq("mask_blob")
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      hash = successful_result.to_h

      expect(hash[:success]).to be true
      expect(hash[:url]).to eq("https://example.com/foreground.png")
      expect(hash[:mask_url]).to eq("https://example.com/mask.png")
      expect(hash[:has_alpha]).to be true
      expect(hash[:has_mask]).to be true
      expect(hash[:model_id]).to eq("rembg")
      expect(hash[:output_format]).to eq(:png)
      expect(hash[:alpha_matting]).to be true
      expect(hash[:refine_edges]).to be true
    end
  end

  describe "#to_cache" do
    it "returns cacheable hash" do
      cache = successful_result.to_cache

      expect(cache[:url]).to eq("https://example.com/foreground.png")
      expect(cache[:mask_url]).to eq("https://example.com/mask.png")
      expect(cache[:output_format]).to eq(:png)
      expect(cache[:cached_at]).to be_present
    end
  end

  describe ".from_cache" do
    it "creates a CachedBackgroundRemovalResult" do
      cache_data = successful_result.to_cache
      cached = described_class.from_cache(cache_data)

      expect(cached).to be_a(RubyLLM::Agents::CachedBackgroundRemovalResult)
      expect(cached.url).to eq("https://example.com/foreground.png")
      expect(cached.cached?).to be true
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedBackgroundRemovalResult do
  let(:cached_result) do
    described_class.new(
      url: "https://example.com/foreground.png",
      data: "base64data",
      mask_url: "https://example.com/mask.png",
      mask_data: "mask_base64",
      mime_type: "image/png",
      model_id: "rembg",
      output_format: :png,
      total_cost: 0.01,
      cached_at: Time.current.iso8601
    )
  end

  describe "#cached?" do
    it "returns true" do
      expect(cached_result.cached?).to be true
    end
  end

  describe "#success?" do
    it "returns true when url or data present" do
      expect(cached_result.success?).to be true
    end
  end

  describe "#mask?" do
    it "returns true when mask_url or mask_data present" do
      expect(cached_result.mask?).to be true
    end
  end

  describe "#has_alpha?" do
    it "returns true for PNG format" do
      expect(cached_result.has_alpha?).to be true
    end
  end

  describe "#base64?" do
    it "returns true when data present" do
      expect(cached_result.base64?).to be true
    end
  end

  describe "data accessors" do
    it "returns url" do
      expect(cached_result.url).to eq("https://example.com/foreground.png")
    end

    it "returns mask_url" do
      expect(cached_result.mask_url).to eq("https://example.com/mask.png")
    end

    it "returns model_id" do
      expect(cached_result.model_id).to eq("rembg")
    end
  end
end
