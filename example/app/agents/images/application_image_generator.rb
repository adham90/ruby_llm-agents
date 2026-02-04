# frozen_string_literal: true

# ApplicationImageGenerator - Base class for all image generators in this application
#
# All image generators inherit from this class. Configure shared settings here
# that apply to all generators, or override them per-generator as needed.
#
# ============================================================================
# IMAGE GENERATOR DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "gpt-image-1"            # Image generation model
#   size "1024x1024"               # Image size ("256x256", "512x512", "1024x1024", "1792x1024", "1024x1792")
#   quality "hd"                   # Quality ("standard", "hd")
#   style "vivid"                  # Style ("vivid", "natural")
#   description "..."              # Human-readable generator description
#
# CONTENT POLICY:
# ---------------
#   content_policy :strict         # Policy level (:none, :standard, :moderate, :strict)
#
# ADVANCED OPTIONS:
# -----------------
#   negative_prompt "..."          # Things to avoid in generation
#   seed 12345                     # Seed for reproducible generation
#   guidance_scale 7.5             # CFG scale (typically 1.0-20.0)
#   steps 50                       # Number of inference steps
#
# TEMPLATES:
# ----------
#   template "A {prompt} in the style of Studio Ghibli"  # Prompt template
#   # Use {prompt} as placeholder for user input
#
# CACHING:
# --------
#   cache_for 1.hour               # Enable caching with TTL
#
# ============================================================================
# AVAILABLE MODELS
# ============================================================================
#
# OpenAI:
#   - gpt-image-1       # DALL-E 3 - highest quality
#   - dall-e-2          # DALL-E 2 - faster, lower cost
#
# Sizes by Model:
#   - DALL-E 3: "1024x1024", "1792x1024", "1024x1792"
#   - DALL-E 2: "256x256", "512x512", "1024x1024"
#
# Quality:
#   - "standard" - Default quality
#   - "hd" - Higher detail (DALL-E 3 only)
#
# Style (DALL-E 3 only):
#   - "vivid" - Hyper-real and dramatic
#   - "natural" - More natural, less hyper-real
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Basic generation
#   result = Images::MyGenerator.call(prompt: "A sunset over mountains")
#   result.url            # => "https://..."
#   result.revised_prompt # => "A beautiful sunset over..."
#   result.save_to("image.png")
#
#   # Multiple images
#   result = Images::MyGenerator.call(prompt: "A cat", count: 4)
#   result.images.each_with_index do |img, i|
#     img.save_to("cat_#{i}.png")
#   end
#
#   # With tenant for budget tracking
#   result = Images::MyGenerator.call(prompt: "Logo design", tenant: organization)
#
#   # With Active Storage
#   result = Images::MyGenerator.call(prompt: "Product photo")
#   product.images.attach(result.as_blob)
#
# ============================================================================
# OTHER IMAGE GENERATOR EXAMPLES
# ============================================================================
#
# See these files for specialized generator implementations:
#   - product_image_generator.rb   - E-commerce product images
#   - logo_generator.rb            - Company logos and branding
#   - thumbnail_generator.rb       - Video/article thumbnails
#   - avatar_generator.rb          - User profile avatars
#   - illustration_generator.rb    - Blog illustrations
#
module Images
  class ApplicationImageGenerator < RubyLLM::Agents::ImageGenerator
    # ============================================
    # Shared Model Configuration
    # ============================================
    # These settings are inherited by all image generators

    model 'gpt-image-1'
    size '1024x1024'
    quality 'standard'
    style 'natural'

    # ============================================
    # Shared Content Policy
    # ============================================

    content_policy :standard

    # ============================================
    # Shared Caching
    # ============================================

    # cache_for 1.hour  # Enable caching for all generators

    # ============================================
    # Shared Helper Methods
    # ============================================
    # Define methods here that can be used by all generators
  end
end
