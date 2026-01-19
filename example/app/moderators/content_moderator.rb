# frozen_string_literal: true

# ContentModerator - Standalone moderation without an agent
#
# Use this when you need to moderate content independently from
# agent execution, such as:
# - Background jobs for user-generated content
# - API endpoints for content validation
# - Batch processing of content
#
# @example Basic usage
#   result = ContentModerator.call(text: "content to check")
#   if result.flagged?
#     puts "Content is inappropriate"
#   end
#
# @example In a Rails controller
#   def create
#     result = ContentModerator.call(text: params[:content])
#     if result.flagged?
#       render json: { error: "Content rejected" }, status: :unprocessable_entity
#     else
#       @post = Post.create!(content: params[:content])
#       render json: @post
#     end
#   end
#
# @example In a background job
#   class ModeratePendingContentJob < ApplicationJob
#     def perform(content_id)
#       content = UserContent.find(content_id)
#       result = ContentModerator.call(text: content.body)
#
#       if result.flagged?
#         content.update!(
#           status: :flagged,
#           moderation_categories: result.flagged_categories
#         )
#       else
#         content.update!(status: :approved)
#       end
#     end
#   end
#
class ContentModerator < RubyLLM::Agents::Moderator
  # Model to use for moderation
  model "omni-moderation-latest"

  # Score threshold - content is only flagged if max score >= threshold
  threshold 0.7

  # Categories to check - only flag if category matches
  categories :hate, :violence, :harassment, :sexual
end

# Example: Strict moderation for children's content
#
# class ChildSafeModerator < RubyLLM::Agents::Moderator
#   model "omni-moderation-latest"
#   threshold 0.3  # Very sensitive
#   categories :sexual, :violence, :self_harm
# end

# Example: Forum moderation
#
# class ForumModerator < RubyLLM::Agents::Moderator
#   model "omni-moderation-latest"
#   threshold 0.8
#   categories :hate, :harassment
# end
