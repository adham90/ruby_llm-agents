# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::ImagePipelineResult do
  let(:mock_image) do
    OpenStruct.new(
      url: "https://example.com/image.png",
      data: nil,
      base64?: false,
      to_blob: "binary_data",
      save: true
    )
  end

  let(:generator_result) do
    OpenStruct.new(
      success?: true,
      error?: false,
      url: "https://example.com/generated.png",
      data: nil,
      base64?: false,
      model_id: "gpt-image-1",
      total_cost: 0.04,
      to_blob: "generated_blob",
      save: ->(path) { File.write(path, "fake") if false }
    )
  end

  let(:upscaler_result) do
    OpenStruct.new(
      success?: true,
      error?: false,
      url: "https://example.com/upscaled.png",
      data: nil,
      base64?: false,
      model_id: "real-esrgan",
      total_cost: 0.01,
      to_blob: "upscaled_blob",
      save: ->(path) { File.write(path, "fake") if false }
    )
  end

  let(:analyzer_result) do
    OpenStruct.new(
      success?: true,
      error?: false,
      caption: "A product photo",
      tags: ["product", "photo"],
      model_id: "gpt-4o",
      total_cost: 0.001
    )
  end

  let(:failed_result) do
    OpenStruct.new(
      success?: false,
      error?: true,
      url: nil,
      total_cost: 0
    )
  end

  let(:successful_step_results) do
    [
      { name: :generate, type: :generator, result: generator_result },
      { name: :upscale, type: :upscaler, result: upscaler_result },
      { name: :analyze, type: :analyzer, result: analyzer_result }
    ]
  end

  let(:successful_result) do
    described_class.new(
      step_results: successful_step_results,
      started_at: Time.current - 5.seconds,
      completed_at: Time.current,
      tenant_id: "org-123",
      pipeline_class: "TestPipeline",
      context: { prompt: "test" }
    )
  end

  describe "status helpers" do
    describe "#success?" do
      it "returns true when all steps succeeded" do
        expect(successful_result.success?).to be true
      end

      it "returns false when any step failed" do
        step_results = [
          { name: :generate, type: :generator, result: generator_result },
          { name: :upscale, type: :upscaler, result: failed_result }
        ]

        result = described_class.new(
          step_results: step_results,
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {}
        )

        expect(result.success?).to be false
      end

      it "returns false when there's a pipeline error" do
        result = described_class.new(
          step_results: [],
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {},
          error_class: "StandardError",
          error_message: "Pipeline failed"
        )

        expect(result.success?).to be false
      end
    end

    describe "#error?" do
      it "returns false when successful" do
        expect(successful_result.error?).to be false
      end

      it "returns true when failed" do
        result = described_class.new(
          step_results: [],
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {},
          error_class: "StandardError"
        )

        expect(result.error?).to be true
      end
    end

    describe "#partial?" do
      it "returns false when all steps succeed" do
        expect(successful_result.partial?).to be false
      end

      it "returns true when some succeed and some fail" do
        step_results = [
          { name: :generate, type: :generator, result: generator_result },
          { name: :upscale, type: :upscaler, result: failed_result }
        ]

        result = described_class.new(
          step_results: step_results,
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {}
        )

        expect(result.partial?).to be true
      end
    end
  end

  describe "step access" do
    describe "#step" do
      it "returns specific step result by name" do
        expect(successful_result.step(:generate)).to eq(generator_result)
        expect(successful_result.step(:upscale)).to eq(upscaler_result)
      end

      it "returns nil for unknown step" do
        expect(successful_result.step(:unknown)).to be_nil
      end
    end

    describe "#[]" do
      it "aliases step method" do
        expect(successful_result[:generate]).to eq(generator_result)
      end
    end

    describe "#step_names" do
      it "returns array of step names" do
        expect(successful_result.step_names).to eq([:generate, :upscale, :analyze])
      end
    end

    describe "#steps" do
      it "returns all step results" do
        expect(successful_result.steps.size).to eq(3)
      end
    end
  end

  describe "count helpers" do
    describe "#step_count" do
      it "returns total number of steps" do
        expect(successful_result.step_count).to eq(3)
      end
    end

    describe "#successful_step_count" do
      it "returns number of successful steps" do
        expect(successful_result.successful_step_count).to eq(3)
      end
    end

    describe "#failed_step_count" do
      it "returns number of failed steps" do
        step_results = [
          { name: :generate, type: :generator, result: generator_result },
          { name: :upscale, type: :upscaler, result: failed_result }
        ]

        result = described_class.new(
          step_results: step_results,
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {}
        )

        expect(result.failed_step_count).to eq(1)
      end
    end
  end

  describe "image access" do
    describe "#final_image" do
      it "returns URL from last non-analyzer step" do
        expect(successful_result.final_image).to eq("https://example.com/upscaled.png")
      end

      it "skips analyzer steps" do
        # The upscaler is the last image-producing step
        expect(successful_result.final_image).not_to eq(analyzer_result.url)
      end
    end

    describe "#url" do
      it "returns URL from last image step" do
        expect(successful_result.url).to eq("https://example.com/upscaled.png")
      end
    end
  end

  describe "shortcut accessors" do
    describe "#analysis" do
      it "returns analyzer step result" do
        expect(successful_result.analysis).to eq(analyzer_result)
      end

      it "returns nil if no analyzer step" do
        step_results = [
          { name: :generate, type: :generator, result: generator_result }
        ]

        result = described_class.new(
          step_results: step_results,
          started_at: Time.current,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {}
        )

        expect(result.analysis).to be_nil
      end
    end

    describe "#generation" do
      it "returns generator step result" do
        expect(successful_result.generation).to eq(generator_result)
      end
    end

    describe "#upscale" do
      it "returns upscaler step result" do
        expect(successful_result.upscale).to eq(upscaler_result)
      end
    end
  end

  describe "timing" do
    describe "#duration_ms" do
      it "calculates duration in milliseconds" do
        result = described_class.new(
          step_results: [],
          started_at: Time.current - 2.5.seconds,
          completed_at: Time.current,
          tenant_id: nil,
          pipeline_class: "TestPipeline",
          context: {}
        )

        expect(result.duration_ms).to be_within(100).of(2500)
      end
    end
  end

  describe "cost" do
    describe "#total_cost" do
      it "sums cost of all steps" do
        expect(successful_result.total_cost).to be_within(0.0001).of(0.051) # 0.04 + 0.01 + 0.001
      end
    end

    describe "#primary_model_id" do
      it "returns model_id from first step" do
        expect(successful_result.primary_model_id).to eq("gpt-image-1")
      end
    end
  end

  describe "serialization" do
    describe "#to_h" do
      it "returns hash representation" do
        hash = successful_result.to_h

        expect(hash[:success]).to be true
        expect(hash[:step_count]).to eq(3)
        expect(hash[:total_cost]).to be_within(0.0001).of(0.051)
        expect(hash[:pipeline_class]).to eq("TestPipeline")
      end

      it "includes step summaries" do
        hash = successful_result.to_h

        expect(hash[:steps].size).to eq(3)
        expect(hash[:steps].first[:name]).to eq(:generate)
        expect(hash[:steps].first[:success]).to be true
      end
    end

    describe "#to_cache" do
      it "returns cacheable hash" do
        cache = successful_result.to_cache

        expect(cache[:step_results].size).to eq(3)
        expect(cache[:total_cost]).to be_within(0.0001).of(0.051)
        expect(cache[:cached_at]).to be_present
      end
    end
  end

  describe "from_cache" do
    it "creates CachedImagePipelineResult" do
      cache_data = {
        step_results: [
          { name: :generate, type: :generator, cached_result: { url: "https://example.com/cached.png" } }
        ],
        total_cost: 0.04,
        cached_at: Time.current.iso8601
      }

      cached = described_class.from_cache(cache_data)

      expect(cached).to be_a(RubyLLM::Agents::CachedImagePipelineResult)
      expect(cached.cached?).to be true
      expect(cached.total_cost).to eq(0.04)
    end
  end
end

RSpec.describe RubyLLM::Agents::CachedImagePipelineResult do
  let(:cached_data) do
    {
      step_results: [
        {
          name: :generate,
          type: :generator,
          cached_result: { url: "https://example.com/cached.png", urls: ["https://example.com/cached.png"] }
        }
      ],
      total_cost: 0.04,
      cached_at: Time.current.iso8601
    }
  end

  let(:cached_result) { described_class.new(cached_data) }

  describe "#cached?" do
    it "returns true" do
      expect(cached_result.cached?).to be true
    end
  end

  describe "#success?" do
    it "returns true when step_results present" do
      expect(cached_result.success?).to be true
    end

    it "returns false when empty" do
      result = described_class.new({ step_results: [], total_cost: 0 })
      expect(result.success?).to be false
    end
  end

  describe "#step" do
    it "returns cached result for step" do
      result = cached_result.step(:generate)
      expect(result[:url]).to eq("https://example.com/cached.png")
    end
  end

  describe "#final_image" do
    it "extracts image from cached results" do
      expect(cached_result.final_image).to eq("https://example.com/cached.png")
    end
  end
end
