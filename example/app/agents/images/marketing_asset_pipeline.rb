# frozen_string_literal: true

# MarketingAssetPipeline - Generate high-quality marketing images
#
# Creates and upscales images for marketing campaigns with
# optional variations for A/B testing.
#
# Usage:
#   # Single high-quality image
#   result = Llm::Image::MarketingAssetPipeline.call(
#     prompt: "Modern tech startup office with diverse team",
#     size: "1792x1024"  # Landscape for social media
#   )
#   result.save("marketing_hero.png")
#
#   # With tenant tracking for cost allocation
#   result = Llm::Image::MarketingAssetPipeline.call(
#     prompt: "Product launch announcement banner",
#     tenant: current_organization
#   )
#   result.total_cost  # Track costs per organization
#
module Llm
  module Images
    class MarketingAssetPipeline < ApplicationImagePipeline
      # Step 1: Generate the marketing image
      step :generate, generator: MarketingGenerator

      # Step 2: Upscale for high resolution output
      step :upscale, upscaler: PhotoUpscaler, scale: 2

      description "High-quality marketing asset generation"
      version "1.0"

      # Cache marketing assets since they're often regenerated
      cache_for 1.day

      # Validate inputs before processing
      before_pipeline :validate_prompt

      private

      def validate_prompt
        prompt = context[:prompt]
        raise ArgumentError, "Prompt is required" if prompt.nil? || prompt.empty?
        raise ArgumentError, "Prompt too short" if prompt.length < 10
      end
    end
  end
end
