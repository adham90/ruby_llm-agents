# frozen_string_literal: true

# ProductImageGenerator - E-commerce product images
#
# Generates high-quality product images for e-commerce platforms.
# Uses natural style for realistic product photography and HD
# quality for detailed product visualization.
#
# Use cases:
# - Product mockups
# - E-commerce listings
# - Marketing materials
# - Product catalogs
#
# @example Basic usage
#   result = ProductImageGenerator.call(prompt: "Sleek wireless headphones on white background")
#   result.url            # => "https://..."
#   result.save_to("product_headphones.png")
#
# @example Product mockup
#   result = ProductImageGenerator.call(
#     prompt: "Minimalist water bottle, brushed steel finish, studio lighting"
#   )
#
# @example With branding
#   result = ProductImageGenerator.call(
#     prompt: "Premium coffee beans in kraft paper bag with 'Acme Coffee' branding"
#   )
#
class ProductImageGenerator < ApplicationImageGenerator
  description "Generates high-quality product images for e-commerce"
  version "1.0"

  # DALL-E 3 for highest quality
  model "gpt-image-1"

  # Square format for product listings
  size "1024x1024"

  # HD quality for product detail
  quality "hd"

  # Natural style for realistic products
  style "natural"

  # Strict content policy for commercial use
  content_policy :strict

  # Prompt template for consistent product photography style
  template "Professional product photography: {prompt}. Studio lighting, " \
           "clean white background, high-end commercial photography style, " \
           "sharp focus on product details."

  # Cache product images for 1 hour
  cache_for 1.hour
end
