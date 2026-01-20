# frozen_string_literal: true

# SimpleBackgroundRemover - Fast background removal for simple images
#
# Optimized for speed with basic background removal. Best for images
# with clear subject/background separation and solid backgrounds.
#
# Usage:
#   result = Llm::Image::SimpleBackgroundRemover.call(image: "logo.png")
#   result.save("logo_transparent.png")
#
module Llm
  module Image
    class SimpleBackgroundRemover < ApplicationBackgroundRemover
      model "rembg"
      output_format :png
      refine_edges false
      alpha_matting false

      description "Fast background removal for simple images"
      version "1.0"

      # Enable caching since simple removals are fast and deterministic
      cache_for 30.days
    end
  end
end
