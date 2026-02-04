# frozen_string_literal: true

# ApplicationBackgroundRemover - Base class for all background removers in this application
#
# All background removers inherit from this class. Configure shared settings here
# that apply to all removers, or override them per-remover as needed.
#
# ============================================================================
# BACKGROUND REMOVER DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "rembg"                  # Background removal model
#   description "..."              # Human-readable remover description
#
# OUTPUT FORMAT:
# --------------
#   output_format :png             # PNG with alpha transparency (default)
#   output_format :webp            # WebP with alpha transparency
#
# EDGE REFINEMENT:
# ----------------
#   refine_edges true              # Smooth edge transitions
#   alpha_matting true             # Fine edge detection for hair/fur
#   foreground_threshold 0.6       # Foreground sensitivity (0.0-1.0)
#   background_threshold 0.4       # Background sensitivity (0.0-1.0)
#   erode_size 2                   # Edge erosion pixels
#
# MASK OUTPUT:
# ------------
#   return_mask true               # Also return the binary mask
#
# CACHING:
# --------
#   cache_for 30.days              # Enable caching with TTL
#
# ============================================================================
# AVAILABLE MODELS
# ============================================================================
#
#   - rembg              # Fast, good for general use
#   - segment-anything   # Better quality, slower
#   - u2net              # High quality portraits
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Basic background removal
#   result = Images::MyRemover.call(image: "photo.jpg")
#   result.url            # => "https://..." (foreground with transparency)
#   result.has_alpha?     # => true
#
#   # Save the result
#   result.save("transparent.png")
#
#   # Get mask if configured
#   if result.mask?
#     result.save_mask("mask.png")
#   end
#
#   # With tenant for budget tracking
#   result = Images::MyRemover.call(image: "photo.jpg", tenant: organization)
#
#   # Attach to ActiveStorage
#   product.transparent_image.attach(
#     io: StringIO.new(result.to_blob),
#     filename: "transparent.png",
#     content_type: "image/png"
#   )
#
# ============================================================================
# OTHER BACKGROUND REMOVER EXAMPLES
# ============================================================================
#
# See these files for specialized remover implementations:
#   - product_background_remover.rb   - E-commerce product cutouts
#   - portrait_background_remover.rb  - Portrait extraction
#   - simple_background_remover.rb    - Fast simple removal
#
module Images
  class ApplicationBackgroundRemover < RubyLLM::Agents::BackgroundRemover
    # ============================================
    # Shared Model Configuration
    # ============================================
    # These settings are inherited by all background removers

    model 'rembg'
    output_format :png

    # ============================================
    # Shared Caching
    # ============================================

    # cache_for 30.days  # Enable caching for all removers

    # ============================================
    # Shared Helper Methods
    # ============================================
    # Define methods here that can be used by all removers
  end
end
