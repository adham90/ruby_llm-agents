# frozen_string_literal: true

# ContentModerationPipeline - Analyze user-uploaded images for safety
#
# Processes uploaded images through content analysis to detect
# inappropriate content and extract metadata for categorization.
#
# Usage:
#   result = Images::ContentModerationPipeline.call(image: uploaded_file.path)
#
#   if result.analysis.safe?
#     # Image is safe, proceed with upload
#     save_to_storage(result.final_image)
#   else
#     # Image flagged for review
#     queue_for_moderation(result)
#   end
#
#   # Access analysis details
#   result.analysis.caption      # Brief description
#   result.analysis.tags         # Content tags
#   result.analysis.safe?        # Safety check result
#
module Images
  class ContentModerationPipeline < ApplicationImagePipeline
    # Step 1: Analyze the image for content safety and metadata
    step :analyze, analyzer: Images::ContentAnalyzer

    description "Content moderation and analysis pipeline"
    version "1.0"

    # Continue processing even if analysis fails
    # stop_on_error false

    # Add callback to log moderation results
    after_pipeline :log_moderation_result

    private

    def log_moderation_result(result)
      return unless defined?(Rails)

      if result.analysis&.success?
        Rails.logger.info(
          "[ContentModeration] Image analyzed: safe=#{result.analysis.safe?}, " \
          "tags=#{result.analysis.tags.join(', ')}"
        )
      else
        Rails.logger.warn("[ContentModeration] Analysis failed for image")
      end
    end
  end
end
