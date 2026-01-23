# frozen_string_literal: true

# ContentAnalyzer - Analyzes images for content moderation
#
# Identifies potentially problematic content, objects, and themes
# for content moderation workflows.
#
# Usage:
#   result = Images::ContentAnalyzer.call(image: uploaded_image)
#   result.has_object?("weapon")  # => false
#   result.has_tag?("violence")   # => false
#   result.tags                   # ["landscape", "nature", "peaceful"]
#
module Images
  class ContentAnalyzer < ApplicationImageAnalyzer
    model "gpt-4o"
    analysis_type :all
    detect_objects true
    max_tags 20

    description "Analyzes images for content moderation"
    version "1.0"

    custom_prompt <<~PROMPT
      Analyze this image for content moderation purposes.
      Identify:
      - Main subjects and objects in the image
      - Any potentially inappropriate content
      - Violence, weapons, or dangerous items
      - Nudity or sexually suggestive content
      - Hate symbols or offensive imagery
      - Drug paraphernalia or illegal activities

      Be thorough and flag anything that might require human review.
      Include confidence levels for concerning detections.
    PROMPT
  end
end
