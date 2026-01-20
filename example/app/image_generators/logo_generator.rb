# frozen_string_literal: true

# LogoGenerator - Company logos and branding
#
# Generates professional logo concepts and branding elements.
# Uses vivid style for bold, distinctive designs and HD quality
# for clean vector-like output.
#
# Use cases:
# - Company logo concepts
# - Brand identity exploration
# - Icon design
# - App icons
#
# @example Basic usage
#   result = LogoGenerator.call(prompt: "Tech startup logo for AI company called 'Nexus'")
#   result.url            # => "https://..."
#   result.save_to("nexus_logo.png")
#
# @example Minimal logo
#   result = LogoGenerator.call(
#     prompt: "Minimalist logo for coffee shop 'Bean There', coffee cup icon"
#   )
#
# @example App icon
#   result = LogoGenerator.call(
#     prompt: "Modern app icon for fitness tracking app, abstract running figure"
#   )
#
class LogoGenerator < ApplicationImageGenerator
  description "Generates company logos and branding concepts"
  version "1.0"

  # DALL-E 3 for highest quality
  model "gpt-image-1"

  # Square format for logos
  size "1024x1024"

  # HD quality for clean lines
  quality "hd"

  # Vivid style for bold designs
  style "vivid"

  # Strict content policy for commercial use
  content_policy :strict

  # Prompt template for logo design
  template "Professional logo design: {prompt}. Minimalist, scalable, " \
           "clean vector-style design, suitable for print and digital use, " \
           "transparent background concept, memorable and distinctive."

  # Avoid common logo pitfalls
  negative_prompt "text-heavy, complex gradients, photorealistic, cluttered, " \
                  "too many colors, difficult to scale, trendy effects"

  # Cache logos for 1 hour
  cache_for 1.hour
end
