# frozen_string_literal: true

# SceneAnalyzer - Analyzes scenes for location and context
#
# Provides detailed scene understanding including location type,
# time of day, weather, and environmental context.
#
# Usage:
#   result = SceneAnalyzer.call(image: "vacation_photo.jpg")
#   result.caption      # "Beach scene at sunset"
#   result.description  # "A tropical beach with palm trees..."
#   result.tags         # ["beach", "sunset", "tropical", "vacation"]
#
class SceneAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :detailed
  extract_colors true
  max_tags 12

  description "Analyzes scenes for location and environmental context"
  version "1.0"

  custom_prompt <<~PROMPT
    Analyze this scene image. Provide:
    - Location type (indoor/outdoor, urban/rural, specific venue type)
    - Geographic region if identifiable
    - Time of day and lighting conditions
    - Weather conditions if outdoor
    - Season if determinable
    - Mood and atmosphere
    - Key environmental elements
    - Dominant colors and their emotional impact
  PROMPT
end
