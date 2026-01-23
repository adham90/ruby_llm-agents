# frozen_string_literal: true

# AvatarGenerator - User profile avatars
#
# Generates unique profile avatars and character illustrations.
# Uses a smaller size optimized for profile pictures and avatar
# displays across the application.
#
# Use cases:
# - User profile pictures
# - Team member avatars
# - Character creation
# - Placeholder avatars
#
# @example Basic usage
#   result = Images::AvatarGenerator.call(prompt: "Professional woman avatar, friendly smile")
#   result.url            # => "https://..."
#   result.save_to("user_avatar.png")
#
# @example Character avatar
#   result = Images::AvatarGenerator.call(
#     prompt: "Cartoon fox character, adventure style, wearing scarf"
#   )
#
# @example Abstract avatar
#   result = Images::AvatarGenerator.call(
#     prompt: "Abstract geometric pattern avatar in blue and purple"
#   )
#
module Images
  class AvatarGenerator < ApplicationImageGenerator
    description "Generates unique profile avatars and character illustrations"
    version "1.0"

    # DALL-E 3 for quality
    model "gpt-image-1"

    # Square format for profile pictures
    size "1024x1024"

    # Standard quality is good for avatars
    quality "standard"

    # Vivid for distinctive avatars
    style "vivid"

    # Strict content policy for user-facing content
    content_policy :strict

    # Prompt template for avatar style
    template "Profile avatar: {prompt}. Centered composition, clear face or symbol, " \
             "works well at small sizes, distinctive and memorable, " \
             "suitable for professional or social media use."

    # Avoid inappropriate content for avatars
    negative_prompt "offensive, inappropriate, scary, disturbing, " \
                    "too complex, hard to recognize at small sizes"

    # Cache avatars briefly
    cache_for 30.minutes
  end
end
