# frozen_string_literal: true

# PortraitBackgroundRemover - Extracts portraits with fine edge detail
#
# Optimized for human portraits with advanced alpha matting for
# hair and fine details. Returns both foreground and mask.
#
# Usage:
#   result = Images::PortraitBackgroundRemover.call(image: "headshot.jpg")
#   result.save("portrait_transparent.png")
#
#   if result.mask?
#     result.save_mask("portrait_mask.png")
#   end
#
#   # Composite with new background
#   composite_with_background(result.to_blob, "office_background.jpg")
#
module Images
  class PortraitBackgroundRemover < ApplicationBackgroundRemover
    model "segment-anything"
    output_format :png
    refine_edges true
    alpha_matting true
    foreground_threshold 0.6
    background_threshold 0.4
    erode_size 1
    return_mask true

    description "Extracts portraits with fine edge detail for hair/fur"
    version "1.0"
  end
end
