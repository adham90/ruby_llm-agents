# frozen_string_literal: true

# ProductImagePipeline - Complete e-commerce product image workflow
#
# Generates, upscales, removes background, and analyzes product images
# in a single automated workflow.
#
# Usage:
#   result = ProductImagePipeline.call(
#     prompt: "Professional photo of wireless headphones",
#     high_quality: true,
#     transparent: true
#   )
#   result.final_image    # Processed image ready for e-commerce
#   result.analysis       # Product analysis with tags and description
#   result.total_cost     # Combined cost of all operations
#
#   # Access individual steps
#   result.step(:generate)    # Generation result
#   result.step(:upscale)     # Upscale result (if high_quality: true)
#   result.step(:remove_bg)   # Background removal result (if transparent: true)
#   result.step(:analyze)     # Analysis result
#
class ProductImagePipeline < ApplicationImagePipeline
  # Step 1: Generate the base product image
  step :generate, generator: ProductGenerator

  # Step 2: Upscale for high quality (conditional)
  step :upscale, upscaler: PhotoUpscaler, scale: 2, if: ->(ctx) { ctx[:high_quality] }

  # Step 3: Remove background for transparent images (conditional)
  step :remove_bg, remover: ProductBackgroundRemover, if: ->(ctx) { ctx[:transparent] }

  # Step 4: Analyze the final image for metadata
  step :analyze, analyzer: ProductAnalyzer

  description "Complete e-commerce product image workflow"
  version "1.0"

  # Optional: Enable caching for repeated prompts
  # cache_for 1.hour
end
