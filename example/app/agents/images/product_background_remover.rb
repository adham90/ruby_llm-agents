# frozen_string_literal: true

# ProductBackgroundRemover - Removes backgrounds from product photos
#
# Optimized for e-commerce product images with clean edges and
# proper alpha transparency for compositing on any background.
#
# Usage:
#   result = Images::ProductBackgroundRemover.call(image: "product.jpg")
#   result.save("product_transparent.png")
#
#   # Attach to product
#   product.transparent_image.attach(
#     io: StringIO.new(result.to_blob),
#     filename: "transparent.png",
#     content_type: "image/png"
#   )
#
module Images
  class ProductBackgroundRemover < ApplicationBackgroundRemover
    model "segment-anything"
    output_format :png
    refine_edges true
    alpha_matting true
    foreground_threshold 0.55
    background_threshold 0.45

    description "Removes backgrounds from product photos for e-commerce"
    version "1.0"
  end
end
