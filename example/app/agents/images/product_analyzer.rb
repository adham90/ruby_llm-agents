# frozen_string_literal: true

# ProductAnalyzer - Analyzes product images for e-commerce
#
# Extracts product information including category, colors, materials,
# and key features for catalog management.
#
# Usage:
#   result = Llm::Image::ProductAnalyzer.call(image: "product.jpg")
#   result.caption        # "A red leather sneaker"
#   result.tags           # ["sneaker", "red", "leather", "footwear"]
#   result.dominant_color # { hex: "#CC0000", name: "red", percentage: 45 }
#
module Llm
  module Images
    class ProductAnalyzer < ApplicationImageAnalyzer
      model "gpt-4o"
      analysis_type :all
      extract_colors true
      detect_objects true
      max_tags 15

      description "Analyzes product images for e-commerce catalogs"
      version "1.0"

      custom_prompt <<~PROMPT
        Analyze this product image for an e-commerce catalog.
        Identify:
        - Product type and category
        - Brand if visible
        - Colors (provide hex codes and names)
        - Materials and textures
        - Key features and selling points
        - Style and target audience
        Be specific and focus on details useful for product listings.
      PROMPT
    end
  end
end
