# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageAnalysisResult do
  let(:successful_result) do
    described_class.new(
      image: "photo.jpg",
      model_id: "gpt-4o",
      analysis_type: :detailed,
      caption: "A sunset over mountains",
      description: "A beautiful sunset over mountain ranges with orange and purple hues.",
      tags: %w[sunset mountains nature landscape orange sky],
      objects: [
        { name: "mountain", location: "center", confidence: "high" },
        { name: "sun", location: "top", confidence: "high" }
      ],
      colors: [
        { hex: "#FF6B35", name: "orange", percentage: 30 },
        { hex: "#4A1A6C", name: "purple", percentage: 25 },
        { hex: "#1E3A5F", name: "navy", percentage: 20 }
      ],
      text: nil,
      raw_response: { caption: "A sunset over mountains" },
      started_at: 2.seconds.ago,
      completed_at: Time.current,
      tenant_id: "tenant-123",
      analyzer_class: "TestAnalyzer"
    )
  end

  let(:error_result) do
    described_class.new(
      image: "photo.jpg",
      model_id: "gpt-4o",
      analysis_type: :detailed,
      caption: nil,
      description: nil,
      tags: [],
      objects: [],
      colors: [],
      text: nil,
      raw_response: nil,
      started_at: 1.second.ago,
      completed_at: Time.current,
      tenant_id: nil,
      analyzer_class: "TestAnalyzer",
      error_class: "RuntimeError",
      error_message: "API error"
    )
  end

  describe "#success?" do
    it "returns true when there is content" do
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

  describe "#caption?" do
    it "returns true when caption is present" do
      expect(successful_result.caption?).to be true
    end

    it "returns false when caption is nil" do
      expect(error_result.caption?).to be false
    end
  end

  describe "#tags?" do
    it "returns true when tags are present" do
      expect(successful_result.tags?).to be true
    end

    it "returns false when tags are empty" do
      expect(error_result.tags?).to be false
    end
  end

  describe "#objects?" do
    it "returns true when objects are detected" do
      expect(successful_result.objects?).to be true
    end

    it "returns false when no objects" do
      expect(error_result.objects?).to be false
    end
  end

  describe "#colors?" do
    it "returns true when colors are extracted" do
      expect(successful_result.colors?).to be true
    end

    it "returns false when no colors" do
      expect(error_result.colors?).to be false
    end
  end

  describe "#tag_symbols" do
    it "converts tags to symbols" do
      expect(successful_result.tag_symbols).to include(:sunset, :mountains, :nature)
    end

    it "handles multi-word tags" do
      result = described_class.new(
        image: "test.jpg",
        model_id: "gpt-4o",
        analysis_type: :tags,
        caption: nil,
        description: nil,
        tags: ["red car", "blue sky"],
        objects: [],
        colors: [],
        text: nil,
        raw_response: nil,
        started_at: Time.current,
        completed_at: Time.current,
        tenant_id: nil,
        analyzer_class: "Test"
      )

      expect(result.tag_symbols).to include(:red_car, :blue_sky)
    end
  end

  describe "#dominant_color" do
    it "returns the color with highest percentage" do
      expect(successful_result.dominant_color[:hex]).to eq("#FF6B35")
      expect(successful_result.dominant_color[:percentage]).to eq(30)
    end

    it "returns nil when no colors" do
      expect(error_result.dominant_color).to be_nil
    end
  end

  describe "#objects_with_confidence" do
    it "filters objects by confidence level" do
      high_confidence = successful_result.objects_with_confidence("high")
      expect(high_confidence.size).to eq(2)
    end

    it "returns empty array for non-matching confidence" do
      low_confidence = successful_result.objects_with_confidence("low")
      expect(low_confidence).to be_empty
    end
  end

  describe "#high_confidence_objects" do
    it "returns objects with high confidence" do
      expect(successful_result.high_confidence_objects.size).to eq(2)
    end
  end

  describe "#has_object?" do
    it "returns true when object is detected" do
      expect(successful_result.has_object?("mountain")).to be true
    end

    it "returns false when object is not detected" do
      expect(successful_result.has_object?("car")).to be false
    end

    it "is case insensitive" do
      expect(successful_result.has_object?("MOUNTAIN")).to be true
    end
  end

  describe "#has_tag?" do
    it "returns true when tag is present" do
      expect(successful_result.has_tag?("sunset")).to be true
    end

    it "returns false when tag is not present" do
      expect(successful_result.has_tag?("beach")).to be false
    end

    it "is case insensitive" do
      expect(successful_result.has_tag?("SUNSET")).to be true
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      expect(successful_result.duration_ms).to be > 0
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

  describe "#to_h" do
    it "returns a hash representation" do
      hash = successful_result.to_h

      expect(hash[:success]).to be true
      expect(hash[:caption]).to eq("A sunset over mountains")
      expect(hash[:tags]).to include("sunset")
      expect(hash[:model_id]).to eq("gpt-4o")
      expect(hash[:analysis_type]).to eq(:detailed)
    end
  end

  describe "#to_cache" do
    it "returns cacheable hash" do
      cache = successful_result.to_cache

      expect(cache[:caption]).to eq("A sunset over mountains")
      expect(cache[:tags]).to eq(successful_result.tags)
      expect(cache[:cached_at]).to be_present
    end
  end

  describe ".from_cache" do
    it "creates a CachedImageAnalysisResult" do
      cache_data = successful_result.to_cache
      cached = described_class.from_cache(cache_data)

      expect(cached).to be_a(RubyLLM::Agents::CachedImageAnalysisResult)
      expect(cached.caption).to eq("A sunset over mountains")
      expect(cached.cached?).to be true
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImageAnalysisResult do
  let(:cached_result) do
    described_class.new(
      image: "photo.jpg",
      model_id: "gpt-4o",
      analysis_type: :detailed,
      caption: "A sunset",
      description: "Description",
      tags: %w[sunset mountains],
      objects: [{ name: "sun" }],
      colors: [{ hex: "#FF0000", percentage: 50 }],
      text: nil,
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
    it "returns true when content present" do
      expect(cached_result.success?).to be true
    end
  end

  describe "data accessors" do
    it "returns caption" do
      expect(cached_result.caption).to eq("A sunset")
    end

    it "returns tags" do
      expect(cached_result.tags).to eq(%w[sunset mountains])
    end

    it "returns tag_symbols" do
      expect(cached_result.tag_symbols).to include(:sunset, :mountains)
    end

    it "returns dominant_color" do
      expect(cached_result.dominant_color[:hex]).to eq("#FF0000")
    end
  end
end
